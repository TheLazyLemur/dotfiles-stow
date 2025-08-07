package handlers

import (
	"context"
	"encoding/json"
	"fmt"

	"agent/internal/core"

	"github.com/mark3labs/mcp-go/mcp"
)

// PermissionHandler handles MCP permission tool requests
type PermissionHandler struct {
	evaluator core.PermissionEvaluator
}

// NewPermissionHandler creates a new permission handler
func NewPermissionHandler(evaluator core.PermissionEvaluator) *PermissionHandler {
	return &PermissionHandler{
		evaluator: evaluator,
	}
}

// Handle processes MCP tool requests for permission evaluation
func (h *PermissionHandler) Handle(ctx context.Context, request mcp.CallToolRequest) (*mcp.CallToolResult, error) {
	// Extract tool name
	toolName, err := request.RequireString("tool_name")
	if err != nil {
		return nil, fmt.Errorf("invalid tool_name parameter: %w", err)
	}

	// Extract input object
	inputRaw, exists := request.GetArguments()["input"]
	if !exists {
		return nil, fmt.Errorf("missing required parameter: input")
	}

	// Extract optional tool_use_id
	toolUseID := request.GetString("tool_use_id", "")

	// Create core permission request
	permReq := core.PermissionRequest{
		ToolName:  toolName,
		Input:     inputRaw,
		ToolUseID: toolUseID,
	}

	// Evaluate permission using core service
	response, err := h.evaluator.Evaluate(ctx, permReq)
	if err != nil {
		return nil, fmt.Errorf("failed to evaluate permission: %w", err)
	}

	// Convert response to JSON string (required by Claude Code SDK)
	responseJSON, err := json.Marshal(response)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal response: %w", err)
	}

	// Return the JSON-stringified response as required by Claude Code SDK
	return mcp.NewToolResultText(string(responseJSON)), nil
}

// CreateTool creates the MCP tool definition for permission prompts
func (h *PermissionHandler) CreateTool() mcp.Tool {
	return mcp.NewTool(
		"approval_prompt",
		mcp.WithDescription(
			"Simulate a permission check - evaluates tool requests and returns allow/deny decisions",
		),
		mcp.WithString("tool_name",
			mcp.Required(),
			mcp.Description("The name of the tool requesting permission"),
		),
		mcp.WithObject("input",
			mcp.Required(),
			mcp.Description("The input parameters for the tool"),
		),
		mcp.WithString("tool_use_id",
			mcp.Description("The unique tool use request ID"),
		),
	)
}