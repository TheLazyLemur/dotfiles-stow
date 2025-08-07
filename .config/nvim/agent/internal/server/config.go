package server

import "agent/internal/core"

// Config holds the server configuration
type Config struct {
	Port       string
	BaseURL    string
	SSEPath    string
	MsgPath    string
	Strategy   core.EvaluationStrategy
	LogFile    string
}

// DefaultConfig returns a configuration with sensible defaults
func DefaultConfig() Config {
	return Config{
		Port:     ":8080",
		BaseURL:  "http://localhost:8080",
		SSEPath:  "/sse",
		MsgPath:  "/messages",
		Strategy: core.StrategyAutomated,
		LogFile:  "/tmp/agent.log",
	}
}