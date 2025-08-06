# MCP Permission Integration System

## Overview

This system creates a **human-in-the-loop permission gateway** for MCP (Model Context Protocol) tool calls, using Neovim as an interactive approval interface. It solves the AI safety problem by requiring explicit human approval for potentially dangerous operations while maintaining the convenience of automated tool usage.

## Architecture

```
┌─────────────┐    ┌──────────────┐    ┌─────────────┐    ┌──────────┐
│ MCP Client  │───▶│ Agent Server │───▶│ Neovim UI   │───▶│   User   │
│ (Claude)    │    │ (Go Process) │    │ (Lua)       │    │ Decision │
└─────────────┘    └──────────────┘    └─────────────┘    └──────────┘
       ▲                    ▲                    │              │
       │                    │                    ▼              ▼
       │                    │            ┌─────────────┐┌─────────────┐
       │                    │            │vim.confirm()││Allow/Deny   │
       │                    │            │Dialog       ││Choice       │
       │                    │            └─────────────┘└─────────────┘
       │                    │                    │              │
       │                    ◀────────────────────┴──────────────┘
       │                           JSON Response
       │                      (STDIN to server)
       │
       └──────── HTTP Response (Allow/Deny + Input) ────────
```

## Components

### 1. Agent Server (`agent` binary)
- **Role**: MCP Server that provides `approval_prompt` tool
- **Language**: Go
- **Communication**: 
  - **HTTP** for MCP client interactions
  - **STDIO** for permission requests with Neovim
- **Strategy**: `--strategy stdio` enables interactive permission mode

### 2. Neovim Module (`agent.lua`)
- **Role**: Interactive permission gateway and process manager
- **Responsibilities**:
  - Spawn and manage the agent server process
  - Parse permission requests from server STDOUT
  - Show interactive UI for user decisions
  - Send responses back to server via STDIN
  - Maintain audit logs of all decisions

## Data Flow

### Complete Permission Flow
```
1. MCP Client → Agent Server (HTTP)
   POST /messages
   {
     "method": "tools/call",
     "params": {
       "name": "approval_prompt",
       "arguments": {
         "tool_name": "bash",
         "input": {"command": "rm -rf /"},
         "tool_use_id": "dangerous-123"
       }
     }
   }

2. Agent Server → Neovim (STDOUT)
   {"type":"permission_request","tool":"bash","input":{"command":"rm -rf /"},"id":"req-1"}

3. Neovim → User (UI Dialog)
   ┌─────────────────────────────────────┐
   │ MCP Permission Request              │
   │                                     │
   │ Tool: bash                          │
   │ Input: {"command":"rm -rf /"}       │
   │                                     │
   │ Allow this operation?               │
   │                                     │
   │ [ Allow ] [ Deny ] [ Details ]      │
   └─────────────────────────────────────┘

4. User → Neovim (Choice)
   User clicks "Deny"

5. Neovim → Agent Server (STDIN)
   {"type":"permission_response","id":"req-1","allowed":false}

6. Agent Server → MCP Client (HTTP Response)
   {
     "result": {
       "content": [{"type":"text","text":"{\"behavior\":\"deny\",\"message\":\"Permission denied by user\"}"}]
     }
   }
```

## Technical Implementation Details

### JSON Message Reconstruction
**Problem**: Neovim's job STDOUT callback splits long JSON across multiple chunks
```lua
-- WRONG: This fails with truncated JSON
for _, line in ipairs(data) do
    handle_json(line)  -- line might be incomplete!
end

-- RIGHT: Accumulate and detect complete objects
message_buffer = message_buffer .. chunk
while true do
    local start_pos = message_buffer:find("{")
    -- Count braces to find matching closing brace
    local brace_count = 0
    for i = start_pos, #message_buffer do
        if char == "{" then brace_count = brace_count + 1
        elseif char == "}" then brace_count = brace_count - 1
        end
        if brace_count == 0 then
            -- Found complete JSON!
            local json_str = message_buffer:sub(start_pos, i)
            handle_json(json_str)
            break
        end
    end
end
```

### Async UI Integration
**Problem**: Job callbacks run outside main Neovim event loop
```lua
-- WRONG: This fails silently
on_stdout = function(_, data, _)
    vim.fn.confirm("Allow?", "&Yes\n&No")  -- Doesn't show!
end

-- RIGHT: Schedule on main event loop
on_stdout = function(_, data, _)
    vim.schedule(function()
        vim.fn.confirm("Allow?", "&Yes\n&No")  -- Works!
    end)
end
```

### Bi-directional Process Communication
```lua
-- Start server with STDIO pipes
mcp_job_id = vim.fn.jobstart({"agent", "--strategy", "stdio"}, {
    on_stdout = function(_, data, _)
        -- Receive permission requests
        process_stdout_data(data)
    end
})

-- Send response back to server
vim.fn.chansend(mcp_job_id, response_json .. "\n")
```

## Security Model

### Human-in-the-Loop Control
- **Every dangerous operation** requires explicit human approval
- **Zero automatic approvals** - no AI can bypass the permission system
- **Detailed inspection** - users can view exact parameters before deciding
- **Audit trail** - all decisions are logged with timestamps

### Request Validation
- **Cryptographic ID matching** - responses must match request IDs exactly
- **Type validation** - only `permission_request` messages trigger UI
- **Input sanitization** - malformed JSON is safely rejected

### Trust Boundaries
```
Trusted:     Neovim UI, Human User, Agent Server
Untrusted:   MCP Clients, Tool Calls, Input Parameters
Boundary:    Permission request/response protocol
```

## API Reference

### Process Management
```lua
local agent = require('agent')

-- Start the permission server
agent.start()  -- Spawns agent server with STDIO strategy

-- Check if running
if agent.is_running() then
    print("Server active")
end

-- Stop the server
agent.stop()  -- Terminates process and cleans up state
```

### Permission Management
```lua
-- View pending approvals
local pending = agent.get_pending_requests()
for id, request in pairs(pending) do
    print("Pending:", request.tool, id)
end

-- Programmatic approval (for automation/testing)
agent.respond_to_request("req-123", true)   -- Allow
agent.respond_to_request("req-456", false)  -- Deny

-- Batch operations
local allowed_count = agent.allow_all_pending()
local denied_count = agent.deny_all_pending()
```

### Debugging & Monitoring
```lua
-- View all communication logs
local logs = agent.get_logs()
for _, entry in ipairs(logs) do
    print(entry)  -- [timestamp] MCP SOURCE: data
end

-- Clear log buffer
agent.clear_logs()

-- Test UI without server
agent.test_ui()  -- Shows fake permission dialog
```

## Configuration

### Agent Server Arguments
```bash
agent --port :8080 --strategy stdio --log-file /tmp/agent.log
```
- `--port :8080`: HTTP endpoint for MCP clients
- `--strategy stdio`: Enable interactive permission mode
- `--log-file`: Server-side logging (separate from Neovim logs)

### Neovim Integration
```lua
-- In init.lua or plugin config
local agent = require('agent')

-- Auto-start on Neovim startup
vim.api.nvim_create_autocmd("VimEnter", {
    callback = function()
        agent.start()
    end
})

-- Keybindings for management
vim.keymap.set('n', '<leader>as', agent.start, {desc = "Start MCP agent"})
vim.keymap.set('n', '<leader>aq', agent.stop, {desc = "Stop MCP agent"})
vim.keymap.set('n', '<leader>al', function()
    print(vim.inspect(agent.get_logs()))
end, {desc = "Show MCP logs"})
```

## Integration Patterns

### MCP Client Usage
```javascript
// From Claude Desktop or other MCP client
const result = await mcpClient.callTool("approval_prompt", {
    tool_name: "filesystem",
    input: {
        operation: "delete",
        path: "/important/file.txt",
        recursive: false
    },
    tool_use_id: "delete-operation-001"
});

// Result contains user's decision:
// {"behavior": "allow", "updated_input": {...}} OR
// {"behavior": "deny", "message": "Permission denied by user"}
```

### Server-Side Tool Registration
```go
// In the agent server
func (h *PermissionHandler) CreateTool() mcp.Tool {
    return mcp.NewTool(
        "approval_prompt",
        mcp.WithDescription("Request permission for potentially dangerous operations"),
        mcp.WithStringParameter("tool_name", "Name of the tool requesting permission", true),
        mcp.WithParameter("input", "Tool input parameters", true),
        mcp.WithStringParameter("tool_use_id", "Unique identifier for this tool use", false),
    )
}
```

## Error Handling

### Process Management Errors
```lua
-- Server startup failure
if not agent.is_running() then
    print("Failed to start agent server - check if 'agent' binary is in PATH")
end

-- Server crash handling
-- The on_exit callback automatically cleans up state
```

### Communication Errors
```lua
-- JSON parsing failures are logged but don't crash the system
-- Malformed requests are ignored with debug logging
-- UI failures fall back to vim.fn.input() instead of vim.fn.confirm()
```

### UI Fallbacks
```lua
-- If vim.fn.confirm() fails, system falls back to text input
local success, choice = pcall(vim.fn.confirm, message, options)
if not success then
    local response = vim.fn.input("Allow (y/n)? ")
    choice = (response:lower():match("^y") and 1) or 2
end
```

## Performance Considerations

### Stream Processing
- JSON parsing happens **as data arrives**, not batched
- **Memory efficient** - message buffer is trimmed after processing complete objects
- **Low latency** - UI appears immediately when complete request is received

### UI Responsiveness
- `vim.schedule()` ensures UI doesn't block job processing
- Permission dialogs are **non-blocking** for other Neovim operations
- Background server continues running during UI interactions

### Resource Management
- Single server process handles multiple permission requests
- **Automatic cleanup** on Neovim exit or server crash
- Log buffer has **bounded growth** (can be cleared periodically)

## Use Cases

### Development Workflow
1. **Code Generation**: AI requests to create/modify files → User approves each change
2. **System Commands**: AI requests to run shell commands → User sees exact command before allowing
3. **File Operations**: AI requests to delete/move files → User confirms each operation

### Security Scenarios
1. **Dangerous Commands**: `rm -rf`, `sudo`, network operations require approval
2. **Sensitive Files**: Operations on config files, secrets, system directories
3. **External Network**: API calls, downloads, uploads get human oversight

### Automation vs Control
- **Automated**: Safe operations like reading public files, basic calculations
- **Interactive**: Dangerous operations, file modifications, system commands
- **Batch Approval**: Multiple similar operations can be approved at once

This system elegantly balances AI capabilities with human control, ensuring that powerful AI tools remain safe and auditable while preserving their utility for development workflows.