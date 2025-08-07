-- Command service - handles Claude CLI execution
-- Extracted from ui.lua to separate concerns

local M = {}
M.__index = M

function M.new()
  local self = setmetatable({}, M)
  return self
end

-- Execute Claude command with configurable parameters
function M:execute(prompt, session_id, callbacks)
  if not prompt or prompt == "" then
    vim.notify("Error: Empty prompt provided", vim.log.levels.ERROR)
    return -1
  end
  
  if not callbacks then
    vim.notify("Error: No callbacks provided", vim.log.levels.ERROR)
    return -1
  end
  
  -- Prepare Claude command
  local cmd = "claude"
  local args = {
    "--output-format",
    "stream-json",
    "--verbose",
    "--permission-prompt-tool",
    "mcp__permission__approval_prompt",
    "--system-prompt",
    "You are an AI assistant integrated into neovim. Your responses are always rendered in Markdown. The permission prompt tool mcp is used to request user approval for actions that require it. It is also integrated into the MCP server running in the background.",
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

  -- Start the job with error handling
  local job_id = vim.fn.jobstart({ cmd, unpack(args) }, {
    stdout_buffered = false,
    stderr_buffered = false,
    pty = true,
    on_stdout = function(_, data)
      if data and callbacks.on_stdout then
        local ok, err = pcall(callbacks.on_stdout, data)
        if not ok then
          vim.notify("Error in stdout callback: " .. tostring(err), vim.log.levels.ERROR)
        end
      end
    end,
    on_stderr = function(_, data)
      if data and callbacks.on_stderr then
        local ok, err = pcall(callbacks.on_stderr, data)
        if not ok then
          vim.notify("Error in stderr callback: " .. tostring(err), vim.log.levels.ERROR)
        end
      end
    end,
    on_exit = function(_, exit_code)
      if callbacks.on_exit then
        local ok, err = pcall(callbacks.on_exit, exit_code)
        if not ok then
          vim.notify("Error in exit callback: " .. tostring(err), vim.log.levels.ERROR)
        end
      end
    end,
  })
  
  if not job_id or job_id <= 0 then
    local error_msg = "Failed to start Claude command"
    if job_id == 0 then
      error_msg = error_msg .. ": Invalid arguments"
    elseif job_id == -1 then
      error_msg = error_msg .. ": Command not executable"
    end
    vim.notify(error_msg, vim.log.levels.ERROR)
  end

  return job_id
end

return M