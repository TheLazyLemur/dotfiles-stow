-- Command service - handles Claude CLI execution
-- Extracted from ui.lua to separate concerns

local M = {}
M.__index = M

function M.new()
  local self = setmetatable({}, M)
  return self
end

-- Execute Claude command with exact same logic as ui.lua
function M:execute(prompt, session_id, callbacks)
  -- Prepare Claude command (exact copy from ui.lua)
  local cmd = "claude"
  local args = {
    "--output-format",
    "stream-json",
    "--verbose",
    "--permission-prompt-tool",
    "mcp__permission__approval_prompt",
    "--system-prompt",
    "You are an AI assitant integrated into neovim. You responses are always rendered in Markdown. The permission prompt tool mcp is used to request user approval for actions that require it. It is also integrated into the MCP server running in the background.",
    "--mcp-config",
    "/Users/danielr/dotfiles/.config/nvim/config.json",
  }

  -- Add resume flag if we have a session ID
  if session_id then
    table.insert(args, "--resume")
    table.insert(args, session_id)
  end

  table.insert(args, "-p")
  table.insert(args, prompt)

  -- Start the job (exact copy from ui.lua)
  local job_id = vim.fn.jobstart({ cmd, unpack(args) }, {
    stdout_buffered = false,
    stderr_buffered = false,
    pty = true,
    on_stdout = function(_, data)
      if data and callbacks.on_stdout then
        callbacks.on_stdout(data)
      end
    end,
    on_stderr = function(_, data)
      if data and callbacks.on_stderr then
        callbacks.on_stderr(data)
      end
    end,
    on_exit = function(_, exit_code)
      if callbacks.on_exit then
        callbacks.on_exit(exit_code)
      end
    end,
  })

  return job_id
end

return M