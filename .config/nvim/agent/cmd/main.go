package main

import (
	"flag"
	"fmt"
	"io"
	"log"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"
	"time"

	"agent/internal/core"
	"agent/internal/server"
)

func main() {
	// Parse command line flags
	config := parseFlags()

	// Setup file logging
	logFile := setupLogging(config.LogFile)
	fmt.Printf("Logging to: %s\n", logFile)

	// Create evaluator based on strategy
	evaluator, err := createEvaluator(config.Strategy)
	if err != nil {
		log.Fatalf("Failed to create evaluator: %v", err)
	}

	// Create and configure server
	srv := server.New(config)
	if err := srv.RegisterPermissionTool(evaluator); err != nil {
		log.Fatalf("Failed to register tools: %v", err)
	}

	// Setup graceful shutdown
	c := make(chan os.Signal, 1)
	signal.Notify(c, os.Interrupt, syscall.SIGTERM)

	go func() {
		<-c
		log.Println("Shutting down permission prompt server...")
		os.Exit(0)
	}()

	// Start the server
	log.Println("Starting Permission Prompt MCP Server on", config.Port)
	log.Printf("SSE endpoint: %s%s", config.BaseURL, config.SSEPath)
	log.Printf("Message endpoint: %s%s", config.BaseURL, config.MsgPath)
	log.Println("Permission tool: approval_prompt")
	log.Printf("Evaluation strategy: %s", config.Strategy)

	// Start the server (this blocks)
	if err := srv.Start(); err != nil {
		log.Fatalf("Server failed to start: %v", err)
	}
}

// parseFlags parses command line flags and returns server configuration
func parseFlags() server.Config {
	config := server.DefaultConfig()

	flag.StringVar(&config.Port, "port", config.Port, "Server port (e.g., :8080)")
	flag.StringVar(&config.BaseURL, "base-url", config.BaseURL, "Base URL for the server")
	flag.StringVar(&config.SSEPath, "sse-path", config.SSEPath, "SSE endpoint path")
	flag.StringVar(&config.MsgPath, "msg-path", config.MsgPath, "Message endpoint path")
	flag.StringVar(&config.LogFile, "log-file", config.LogFile, "Log file name")

	var strategyStr string
	flag.StringVar(&strategyStr, "strategy", string(config.Strategy), "Evaluation strategy (automated|interactive|stdio)")

	flag.Parse()

	// Validate and set strategy
	switch strategyStr {
	case string(core.StrategyAutomated):
		config.Strategy = core.StrategyAutomated
	case string(core.StrategyInteractive):
		config.Strategy = core.StrategyInteractive
	case string(core.StrategyStdio):
		config.Strategy = core.StrategyStdio
	default:
		log.Fatalf("Invalid strategy: %s. Must be 'automated', 'interactive', or 'stdio'", strategyStr)
	}

	return config
}

// setupLogging configures file-based logging and returns the log file path
func setupLogging(filename string) string {
	logFile, err := os.OpenFile(filename, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0666)
	if err != nil {
		log.Fatalf("Failed to open log file %s: %v", filename, err)
	}

	// Set log output to both file and stderr for visibility
	multiWriter := io.MultiWriter(os.Stderr, logFile)
	log.SetOutput(multiWriter)

	// Return the absolute path of the log file
	absPath, err := filepath.Abs(filename)
	if err != nil {
		return filename
	}
	return absPath
}

// createEvaluator creates the appropriate permission evaluator based on strategy
func createEvaluator(strategy core.EvaluationStrategy) (core.PermissionEvaluator, error) {
	switch strategy {
	case core.StrategyAutomated:
		return core.NewAutomatedEvaluator(), nil
	case core.StrategyInteractive:
		prompter := core.NewConsolePrompter()
		return core.NewInteractiveEvaluator(prompter), nil
	case core.StrategyStdio:
		prompter := core.NewStdioPrompter(os.Stdin, os.Stdout, 120*time.Second)
		return core.NewInteractiveEvaluator(prompter), nil
	default:
		return nil, fmt.Errorf("unknown evaluation strategy: %s", strategy)
	}
}