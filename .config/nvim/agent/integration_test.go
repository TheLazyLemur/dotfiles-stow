package main

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"io"
	"strings"
	"testing"
	"time"

	"agent/internal/core"
	"agent/internal/handlers"

	"github.com/mark3labs/mcp-go/mcp"
)

// TestStdioStrategy_HappyPath tests the complete STDIO integration flow
func TestStdioStrategy_HappyPath(t *testing.T) {
	// given - simulate stdio pipes
	stdinReader, stdinWriter := io.Pipe()
	stdoutReader, stdoutWriter := io.Pipe()

	// Create stdio prompter with our pipes
	prompter := core.NewStdioPrompter(stdinReader, stdoutWriter, 5*time.Second)
	evaluator := core.NewInteractiveEvaluator(prompter)
	handler := handlers.NewPermissionHandler(evaluator)

	// Create MCP tool request
	toolRequest := mcp.CallToolRequest{
		Params: mcp.CallToolParams{
			Name: "approval_prompt",
			Arguments: map[string]interface{}{
				"tool_name": "bash",
				"input": map[string]interface{}{
					"command": "ls -la",
				},
				"tool_use_id": "test-123",
			},
		},
	}

	// Channel to capture the STDIO request that gets sent
	requestChan := make(chan core.StdioRequest, 1)
	
	// Goroutine to read the STDIO request from stdout
	go func() {
		scanner := bufio.NewScanner(stdoutReader)
		if scanner.Scan() {
			var req core.StdioRequest
			if err := json.Unmarshal([]byte(scanner.Text()), &req); err == nil {
				requestChan <- req
			}
		}
	}()

	// Goroutine to send the STDIO response to stdin after we get the request
	go func() {
		// Wait for the request to be sent
		req := <-requestChan
		
		// Send response back
		response := core.StdioResponse{
			Type:    "permission_response",
			ID:      req.ID, // Use the same ID
			Allowed: true,
		}
		responseJSON, _ := json.Marshal(response)
		
		// Write response to stdin
		stdinWriter.Write(append(responseJSON, '\n'))
		stdinWriter.Close()
	}()

	// when - make the MCP call
	result, err := handler.Handle(context.Background(), toolRequest)

	// then - verify the response
	if err != nil {
		t.Fatalf("Handler.Handle() error = %v", err)
	}

	if result == nil {
		t.Fatal("Handler.Handle() returned nil result")
	}

	// Parse the MCP response
	textContent, ok := mcp.AsTextContent(result.Content[0])
	if !ok {
		t.Fatal("Expected TextContent in response")
	}
	
	var permissionResponse core.PermissionResponse
	if err := json.Unmarshal([]byte(textContent.Text), &permissionResponse); err != nil {
		t.Fatalf("Failed to parse permission response: %v", err)
	}

	// Verify the response indicates permission was granted
	if permissionResponse.Behavior != "allow" {
		t.Errorf("Expected behavior 'allow', got %v", permissionResponse.Behavior)
	}

	if permissionResponse.UpdatedInput == nil {
		t.Error("Expected UpdatedInput to be present in allow response")
	}

	// Wait briefly to ensure goroutines complete
	time.Sleep(100 * time.Millisecond)
	
	// Close pipes
	stdoutWriter.Close()
	stdoutReader.Close()
	stdinReader.Close()
}

// TestStdioStrategy_DenyResponse tests the deny path
func TestStdioStrategy_DenyResponse(t *testing.T) {
	// given 
	stdinReader, stdinWriter := io.Pipe()
	stdoutReader, stdoutWriter := io.Pipe()

	prompter := core.NewStdioPrompter(stdinReader, stdoutWriter, 5*time.Second)
	evaluator := core.NewInteractiveEvaluator(prompter)
	handler := handlers.NewPermissionHandler(evaluator)

	toolRequest := mcp.CallToolRequest{
		Params: mcp.CallToolParams{
			Name: "approval_prompt",
			Arguments: map[string]interface{}{
				"tool_name": "rm",
				"input": map[string]interface{}{
					"path": "/important/file",
				},
			},
		},
	}

	requestChan := make(chan core.StdioRequest, 1)
	
	go func() {
		scanner := bufio.NewScanner(stdoutReader)
		if scanner.Scan() {
			var req core.StdioRequest
			if err := json.Unmarshal([]byte(scanner.Text()), &req); err == nil {
				requestChan <- req
			}
		}
	}()

	go func() {
		req := <-requestChan
		response := core.StdioResponse{
			Type:    "permission_response",
			ID:      req.ID,
			Allowed: false, // Deny this time
		}
		responseJSON, _ := json.Marshal(response)
		stdinWriter.Write(append(responseJSON, '\n'))
		stdinWriter.Close()
	}()

	// when
	result, err := handler.Handle(context.Background(), toolRequest)

	// then
	if err != nil {
		t.Fatalf("Handler.Handle() error = %v", err)
	}

	textContent2, ok := mcp.AsTextContent(result.Content[0])
	if !ok {
		t.Fatal("Expected TextContent in response")
	}
	
	var permissionResponse core.PermissionResponse
	json.Unmarshal([]byte(textContent2.Text), &permissionResponse)

	if permissionResponse.Behavior != "deny" {
		t.Errorf("Expected behavior 'deny', got %v", permissionResponse.Behavior)
	}

	if permissionResponse.Message == "" {
		t.Error("Expected Message to be present in deny response")
	}

	time.Sleep(100 * time.Millisecond)
	stdoutWriter.Close()
	stdoutReader.Close()
	stdinReader.Close()
}

// TestStdioProtocol_MessageFormat tests the exact JSON protocol
func TestStdioProtocol_MessageFormat(t *testing.T) {
	// given
	var stdoutCapture bytes.Buffer
	stdinContent := `{"type":"permission_response","id":"req-1","allowed":true}`
	stdin := strings.NewReader(stdinContent + "\n")

	prompter := core.NewStdioPrompter(stdin, &stdoutCapture, time.Second)

	request := core.PermissionRequest{
		ToolName:  "git",
		Input:     map[string]interface{}{"command": "status", "directory": "/tmp"},
		ToolUseID: "protocol-test",
	}

	// when
	allowed, err := prompter.PromptUser(request)

	// then
	if err != nil {
		t.Fatalf("PromptUser() error = %v", err)
	}

	if !allowed {
		t.Error("Expected permission to be allowed")
	}

	// Verify the JSON request format
	var sentRequest core.StdioRequest
	if err := json.Unmarshal(stdoutCapture.Bytes()[:len(stdoutCapture.Bytes())-1], &sentRequest); err != nil {
		t.Fatalf("Failed to parse sent request: %v", err)
	}

	if sentRequest.Type != "permission_request" {
		t.Errorf("Expected type 'permission_request', got %v", sentRequest.Type)
	}

	if sentRequest.Tool != "git" {
		t.Errorf("Expected tool 'git', got %v", sentRequest.Tool)  
	}

	if sentRequest.ID == "" {
		t.Error("Expected non-empty request ID")
	}

	// Verify input structure
	inputMap, ok := sentRequest.Input.(map[string]interface{})
	if !ok {
		t.Error("Expected input to be a map")
	}

	if inputMap["command"] != "status" {
		t.Errorf("Expected command 'status', got %v", inputMap["command"])
	}
}