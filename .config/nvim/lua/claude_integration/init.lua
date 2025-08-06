local server = require("claude_integration.server")
local claude = require("claude_integration.agent")
local ui = require("claude_integration.ui")

local M = {}

M.setup = function()
    server.start()
    if not server.is_running() then
        vim.notify("Failed to start MCP server")
    else
        vim.notify("MCP server started successfully")
    end
end

-- Original CLI-style prompt
M.prompt = claude.execute_command

-- UI-based chat interface
M.open_chat = ui.open_chat
M.send_prompt = ui.send_prompt
M.clear_chat = ui.clear_chat

-- Utility functions
M.view_log = claude.view_log
M.clear_log = claude.clear_log
M.set_log_level = claude.set_log_level

return M
