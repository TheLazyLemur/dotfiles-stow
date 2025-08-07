package core

// PermissionRequest represents a request for permission to execute a tool
type PermissionRequest struct {
	ToolName   string
	Input      interface{}
	ToolUseID  string
}

// PermissionResponse represents the response to a permission request
type PermissionResponse struct {
	Behavior     string      `json:"behavior"`               // "allow" or "deny"
	UpdatedInput interface{} `json:"updatedInput,omitempty"` // for allow responses
	Message      string      `json:"message,omitempty"`      // for deny responses
}

// EvaluationStrategy defines the strategy for evaluating permissions
type EvaluationStrategy string

const (
	StrategyAutomated   EvaluationStrategy = "automated"
	StrategyInteractive EvaluationStrategy = "interactive"
	StrategyStdio       EvaluationStrategy = "stdio"
)