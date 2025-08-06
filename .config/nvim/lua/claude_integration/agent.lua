local M = {}

-- Logging configuration
local log_file = vim.fn.stdpath("data") .. "/claude_integration.log"
local log_level = "all" -- Options: "all", "error", "none"

-- Initialize log file
local function init_log()
    local file = io.open(log_file, "a")
    if file then
        file:write(string.format("\n=== Claude Integration Started: %s ===\n", os.date("%Y-%m-%d %H:%M:%S")))
        file:close()
    end
end

-- Log function
local function log(level, message)
    if log_level == "none" then
        return
    end

    if log_level == "error" and level ~= "ERROR" then
        return
    end

    local file = io.open(log_file, "a")
    if file then
        local timestamp = os.date("%Y-%m-%d %H:%M:%S")
        file:write(string.format("[%s] [%s] %s\n", timestamp, level, message))
        file:close()
    end
end

-- Initialize logging on module load
init_log()

local cmd = "claude"
local args = {
    "--output-format",
    "json",
    "--permission-prompt-tool",
    "--system-prompt",
    "Always respond in markdown.",
    "mcp__permission__approval_prompt",
    "--mcp-config",
    "/Users/danielr/dotfiles/.config/nvim/config.json",
    "-p",
}

M.execute_command = function(prompt)
    log("INFO", "Executing command with prompt: " .. prompt)

    local full_args = vim.tbl_deep_extend("force", {}, args)
    table.insert(full_args, prompt)

    log("DEBUG", "Command: " .. cmd)
    log("DEBUG", "Arguments: " .. vim.inspect(full_args))

    local job_id = vim.fn.jobstart({ cmd, unpack(full_args) }, {
        stdout_buffered = false, -- Don't buffer - stream output immediately
        stderr_buffered = false, -- Don't buffer - stream errors immediately
        pty = true, -- Use a pseudo-terminal for better interactive behavior
        on_stdout = function(_, data)
            if data then
                for _, line in ipairs(data) do
                    if line ~= "" then
                        log("STDOUT", line)
                        -- Print each line to Neovim's message area
                        vim.schedule(function()
                            vim.api.nvim_echo({ { line, "Normal" } }, false, {})
                        end)
                    end
                end
            end
        end,
        on_stderr = function(_, data)
            if data then
                for _, line in ipairs(data) do
                    if line ~= "" then
                        log("ERROR", "stderr: " .. line)
                        vim.schedule(function()
                            vim.api.nvim_echo({ { line, "ErrorMsg" } }, false, {})
                        end)
                    end
                end
            end
        end,
        on_exit = function(_, exit_code)
            log("INFO", "Command exited with code: " .. exit_code)
            if exit_code ~= 0 then
                log("ERROR", "Non-zero exit code: " .. exit_code)
                vim.schedule(function()
                    vim.api.nvim_echo({ { "Command exited with code: " .. exit_code, "ErrorMsg" } }, false, {})
                end)
            else
                vim.schedule(function()
                    vim.api.nvim_echo({ { "Claude command completed successfully", "Normal" } }, false, {})
                end)
            end
        end,
    })

    if job_id <= 0 then
        log("ERROR", "Failed to start command. Job ID: " .. job_id)
        vim.api.nvim_echo({ { "Failed to start command", "ErrorMsg" } }, false, {})
    else
        log("INFO", "Command started successfully with job ID: " .. job_id)
    end
end

-- Function to view the log file
M.view_log = function()
    vim.cmd("edit " .. log_file)
end

-- Function to clear the log file
M.clear_log = function()
    local file = io.open(log_file, "w")
    if file then
        file:write("=== Log cleared: " .. os.date("%Y-%m-%d %H:%M:%S") .. " ===\n")
        file:close()
        log("INFO", "Log file cleared")
        print("Claude integration log cleared")
    end
end

-- Function to set log level
M.set_log_level = function(level)
    if level == "all" or level == "error" or level == "none" then
        log_level = level
        log("INFO", "Log level changed to: " .. level)
        print("Claude integration log level set to: " .. level)
    else
        print("Invalid log level. Use 'all', 'error', or 'none'")
    end
end

-- Function to get log file path
M.get_log_path = function()
    return log_file
end

return M
