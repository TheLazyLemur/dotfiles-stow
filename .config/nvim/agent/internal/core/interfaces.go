package core

import "context"

// PermissionEvaluator defines the interface for evaluating permission requests
type PermissionEvaluator interface {
	Evaluate(ctx context.Context, req PermissionRequest) (PermissionResponse, error)
}

// UserPrompter defines the interface for prompting users for permission decisions
type UserPrompter interface {
	PromptUser(req PermissionRequest) (bool, error)
}