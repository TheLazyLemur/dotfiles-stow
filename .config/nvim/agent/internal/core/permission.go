package core

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"strings"
	"sync"
	"time"
)

// AutomatedEvaluator implements PermissionEvaluator with rule-based evaluation
type AutomatedEvaluator struct{}

// NewAutomatedEvaluator creates a new automated evaluator
func NewAutomatedEvaluator() *AutomatedEvaluator {
	return &AutomatedEvaluator{}
}

// Evaluate evaluates permission requests using automated rules
func (e *AutomatedEvaluator) Evaluate(ctx context.Context, req PermissionRequest) (PermissionResponse, error) {
	inputStr := fmt.Sprintf("%v", req.Input)
	inputJSON, _ := json.Marshal(req.Input)
	inputJSONStr := string(inputJSON)

	switch {
	// Deny dangerous operations
	case strings.Contains(strings.ToLower(req.ToolName), "delete") && !strings.Contains(strings.ToLower(inputStr), "safe"):
		return PermissionResponse{
			Behavior: "deny",
			Message:  "Delete operations require explicit 'safe' confirmation in input",
		}, nil

	case strings.Contains(strings.ToLower(req.ToolName), "system") && strings.Contains(strings.ToLower(inputStr), "admin"):
		return PermissionResponse{
			Behavior: "deny",
			Message:  "System administration tools are not permitted",
		}, nil

	case strings.Contains(strings.ToLower(req.ToolName), "execute") && !hasValidJustification(inputStr):
		return PermissionResponse{
			Behavior: "deny",
			Message:  "Execute operations require valid justification",
		}, nil

	// Deny if input contains sensitive patterns
	case containsSensitiveData(inputJSONStr):
		return PermissionResponse{
			Behavior: "deny",
			Message:  "Input contains sensitive data patterns",
		}, nil

	// Allow read operations on public resources
	case strings.Contains(strings.ToLower(req.ToolName), "read") && containsPublicResource(inputStr):
		return PermissionResponse{
			Behavior:     "allow",
			UpdatedInput: req.Input,
		}, nil

	// Allow if input explicitly contains "allow" keyword (for testing)
	case strings.Contains(strings.ToLower(inputJSONStr), "allow"):
		return PermissionResponse{
			Behavior:     "allow",
			UpdatedInput: req.Input,
		}, nil

	// Allow tools with proper justification
	case hasValidJustification(inputStr):
		return PermissionResponse{
			Behavior:     "allow",
			UpdatedInput: req.Input,
		}, nil

	// Allow common safe operations
	case isSafeOperation(req.ToolName):
		return PermissionResponse{
			Behavior:     "allow",
			UpdatedInput: req.Input,
		}, nil

	// Default policy - allow by default for demonstration
	// In production, you might want to deny by default
	default:
		return PermissionResponse{
			Behavior:     "allow",
			UpdatedInput: req.Input,
		}, nil
	}
}

// InteractiveEvaluator implements PermissionEvaluator with user prompting
type InteractiveEvaluator struct {
	prompter UserPrompter
}

// NewInteractiveEvaluator creates a new interactive evaluator
func NewInteractiveEvaluator(prompter UserPrompter) *InteractiveEvaluator {
	return &InteractiveEvaluator{
		prompter: prompter,
	}
}

// Evaluate evaluates permission requests by prompting the user
func (e *InteractiveEvaluator) Evaluate(ctx context.Context, req PermissionRequest) (PermissionResponse, error) {
	allowed, err := e.prompter.PromptUser(req)
	if err != nil {
		return PermissionResponse{
			Behavior: "deny",
			Message:  fmt.Sprintf("Failed to get user input: %v", err),
		}, err
	}

	if allowed {
		return PermissionResponse{
			Behavior:     "allow",
			UpdatedInput: req.Input,
		}, nil
	}

	return PermissionResponse{
		Behavior: "deny",
		Message:  "Permission denied by user",
	}, nil
}

// ConsolePrompter implements UserPrompter for stdin/stdout interaction
type ConsolePrompter struct{}

// NewConsolePrompter creates a new console prompter
func NewConsolePrompter() *ConsolePrompter {
	return &ConsolePrompter{}
}

// PromptUser prompts the user via console for permission decision
func (p *ConsolePrompter) PromptUser(req PermissionRequest) (bool, error) {
	inputJSON, _ := json.Marshal(req.Input)
	inputJSONStr := string(inputJSON)

	fmt.Printf("\n=== PERMISSION REQUEST ===\n")
	fmt.Printf("Tool Name: %s\n", req.ToolName)
	if req.ToolUseID != "" {
		fmt.Printf("Tool Use ID: %s\n", req.ToolUseID)
	}
	fmt.Printf("Input: %s\n", inputJSONStr)
	fmt.Printf("==========================\n")

	scanner := bufio.NewScanner(os.Stdin)

	for {
		fmt.Print("Allow or Deny? (Allow/Deny): ")

		if !scanner.Scan() {
			return false, fmt.Errorf("no input received")
		}

		userInput := strings.TrimSpace(strings.ToLower(scanner.Text()))

		switch userInput {
		case "allow", "a":
			return true, nil
		case "deny", "d":
			return false, nil
		default:
			fmt.Printf("Invalid input '%s'. Please enter 'Allow' or 'Deny' (or 'a'/'d' for short)\n", scanner.Text())
		}
	}
}

// StdioPrompter implements UserPrompter for STDIO communication with external tools like neovim
type StdioPrompter struct {
	stdin   *bufio.Scanner
	stdout  io.Writer
	timeout time.Duration
	mu      sync.Mutex
	idCount int
}

// StdioRequest represents a permission request sent over STDIO
type StdioRequest struct {
	Type    string      `json:"type"`
	Tool    string      `json:"tool"`
	Input   interface{} `json:"input"`
	ID      string      `json:"id"`
}

// StdioResponse represents a permission response received over STDIO
type StdioResponse struct {
	Type    string `json:"type"`
	ID      string `json:"id"`
	Allowed bool   `json:"allowed"`
}

// NewStdioPrompter creates a new STDIO prompter
func NewStdioPrompter(stdin io.Reader, stdout io.Writer, timeout time.Duration) *StdioPrompter {
	return &StdioPrompter{
		stdin:   bufio.NewScanner(stdin),
		stdout:  stdout,
		timeout: timeout,
	}
}

// PromptUser prompts the user via STDIO for permission decision
func (p *StdioPrompter) PromptUser(req PermissionRequest) (bool, error) {
	p.mu.Lock()
	defer p.mu.Unlock()

	p.idCount++
	requestID := fmt.Sprintf("req-%d", p.idCount)

	stdioReq := StdioRequest{
		Type:  "permission_request",
		Tool:  req.ToolName,
		Input: req.Input,
		ID:    requestID,
	}

	requestJSON, err := json.Marshal(stdioReq)
	if err != nil {
		return false, fmt.Errorf("failed to marshal request: %w", err)
	}

	if _, err := fmt.Fprintln(p.stdout, string(requestJSON)); err != nil {
		return false, fmt.Errorf("failed to write request: %w", err)
	}

	responseChan := make(chan StdioResponse, 1)
	errorChan := make(chan error, 1)

	go func() {
		if !p.stdin.Scan() {
			if err := p.stdin.Err(); err != nil {
				errorChan <- fmt.Errorf("failed to read response: %w", err)
			} else {
				errorChan <- fmt.Errorf("no response received")
			}
			return
		}

		responseText := p.stdin.Text()
		var response StdioResponse
		if err := json.Unmarshal([]byte(responseText), &response); err != nil {
			errorChan <- fmt.Errorf("failed to unmarshal response: %w", err)
			return
		}

		if response.ID != requestID {
			errorChan <- fmt.Errorf("response ID mismatch: expected %s, got %s", requestID, response.ID)
			return
		}

		if response.Type != "permission_response" {
			errorChan <- fmt.Errorf("invalid response type: %s", response.Type)
			return
		}

		responseChan <- response
	}()

	select {
	case response := <-responseChan:
		return response.Allowed, nil
	case err := <-errorChan:
		return false, err
	case <-time.After(p.timeout):
		return false, fmt.Errorf("request timed out after %v", p.timeout)
	}
}

// Helper functions

func hasValidJustification(inputStr string) bool {
	justificationWords := []string{
		"justification",
		"reason",
		"because",
		"need",
		"required",
		"purpose",
	}
	inputLower := strings.ToLower(inputStr)

	for _, word := range justificationWords {
		if strings.Contains(inputLower, word) && len(inputStr) > 20 {
			return true
		}
	}
	return false
}

func containsSensitiveData(inputStr string) bool {
	sensitivePatterns := []string{
		"password", "secret", "key", "token", "credential",
		"ssh", "private", "confidential", "classified",
	}

	inputLower := strings.ToLower(inputStr)
	for _, pattern := range sensitivePatterns {
		if strings.Contains(inputLower, pattern) {
			return true
		}
	}
	return false
}

func containsPublicResource(inputStr string) bool {
	publicPatterns := []string{
		"public", "docs", "help", "readme", "documentation",
		"api", "guide", "tutorial", "example",
	}

	inputLower := strings.ToLower(inputStr)
	for _, pattern := range publicPatterns {
		if strings.Contains(inputLower, pattern) {
			return true
		}
	}
	return false
}

func isSafeOperation(toolName string) bool {
	safeOperations := []string{
		"get_time", "get_date", "calculate", "convert",
		"search", "find", "list", "show", "display",
		"help", "info", "status", "version",
	}

	toolLower := strings.ToLower(toolName)
	for _, safe := range safeOperations {
		if strings.Contains(toolLower, safe) {
			return true
		}
	}
	return false
}