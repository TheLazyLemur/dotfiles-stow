local server = require("claude_integration.server")
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

-- UI-based chat interface
M.open_chat = ui.open_chat
M.send_prompt = ui.send_prompt
M.clear_chat = ui.clear_chat

return M
