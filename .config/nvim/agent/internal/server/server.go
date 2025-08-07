package server

import (
	"fmt"

	"agent/internal/core"
	"agent/internal/handlers"

	"github.com/mark3labs/mcp-go/server"
)

// Server wraps the MCP server and manages tool registration
type Server struct {
	mcpServer *server.MCPServer
	sseServer *server.SSEServer
	config    Config
}

// New creates a new server with the given configuration
func New(config Config) *Server {
	// Create the core MCP server with minimal capabilities
	mcpServer := server.NewMCPServer(
		"Permission Prompt MCP Server",
		"1.0.0",
		server.WithToolCapabilities(false), // Static tool list
		server.WithRecovery(),              // Add panic recovery
	)

	// Create SSE server with configuration
	sseServer := server.NewSSEServer(
		mcpServer,
		server.WithBaseURL(config.BaseURL),
		server.WithSSEEndpoint(config.SSEPath),
		server.WithMessageEndpoint(config.MsgPath),
	)

	return &Server{
		mcpServer: mcpServer,
		sseServer: sseServer,
		config:    config,
	}
}

// RegisterPermissionTool registers the permission tool with the given evaluator
func (s *Server) RegisterPermissionTool(evaluator core.PermissionEvaluator) error {
	handler := handlers.NewPermissionHandler(evaluator)
	tool := handler.CreateTool()
	
	s.mcpServer.AddTool(tool, handler.Handle)
	return nil
}

// Start starts the server and blocks until shutdown
func (s *Server) Start() error {
	if err := s.sseServer.Start(s.config.Port); err != nil {
		return fmt.Errorf("failed to start SSE server: %w", err)
	}
	return nil
}

// GetConfig returns the server configuration
func (s *Server) GetConfig() Config {
	return s.config
}