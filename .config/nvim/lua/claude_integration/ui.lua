local M = {}

-- Buffer state
local chat_bufnr = nil
local job_id = nil
local conversation = {}
local is_processing = false
local current_session_id = nil

-- UI configuration
local separator = " "
local assistant_marker = "## Claude"

-- Create or get the chat buffer
function M.open_chat()
    -- If buffer already exists and is valid, switch to it
    if chat_bufnr and vim.api.nvim_buf_is_valid(chat_bufnr) then
        -- Find or create a window for the buffer
        local win = vim.fn.bufwinnr(chat_bufnr)
        if win == -1 then
            vim.cmd("vsplit")
            vim.api.nvim_set_current_buf(chat_bufnr)
        else
            vim.api.nvim_set_current_win(vim.fn.win_getid(win))
        end
        return chat_bufnr
    end

    -- Create new buffer
    chat_bufnr = vim.api.nvim_create_buf(false, true)

    -- Set buffer options
    vim.api.nvim_buf_set_option(chat_bufnr, "buftype", "nofile")
    vim.api.nvim_buf_set_option(chat_bufnr, "bufhidden", "hide")
    vim.api.nvim_buf_set_option(chat_bufnr, "swapfile", false)
    vim.api.nvim_buf_set_option(chat_bufnr, "filetype", "markdown")
    vim.api.nvim_buf_set_name(chat_bufnr, "Claude Chat")

    -- Open in a vertical split
    vim.cmd("vsplit")
    vim.api.nvim_set_current_buf(chat_bufnr)

    -- Initialize buffer with welcome message
    local welcome = {
        "# Claude Chat",
        "",
        "Type your message after the '>' prompt at the bottom.",
        "Press `<CR>` in normal mode on the last line to send.",
        "",
        "Commands:",
        "- `:ClaudeSend` - Send the current prompt",
        "- `:ClaudeClear` - Clear the chat",
        "",
        separator,
        "## Chat",
        separator,
    }
    vim.api.nvim_buf_set_lines(chat_bufnr, 0, -1, false, welcome)

    -- Add initial prompt marker
    M.add_prompt_marker()

    -- Set up keymaps for this buffer
    vim.api.nvim_buf_set_keymap(
        chat_bufnr,
        "n",
        "<CR>",
        ':lua require("claude_integration.ui").send_prompt()<CR>',
        { noremap = true, silent = true }
    )

    return chat_bufnr
end

-- Add a prompt marker at the end of the buffer
function M.add_prompt_marker()
    if not chat_bufnr or not vim.api.nvim_buf_is_valid(chat_bufnr) then
        return
    end

    local lines = vim.api.nvim_buf_get_lines(chat_bufnr, 0, -1, false)
    local last_line = lines[#lines]

    -- Only add marker if the last line doesn't already have it
    if not last_line:match("^> ") then
        table.insert(lines, "> ")
        vim.api.nvim_buf_set_lines(chat_bufnr, 0, -1, false, lines)
    end

    -- Move cursor to end of buffer
    local line_count = vim.api.nvim_buf_line_count(chat_bufnr)
    vim.api.nvim_win_set_cursor(0, { line_count, 2 })
end

-- Extract the current prompt from the buffer
function M.get_current_prompt()
    if not chat_bufnr or not vim.api.nvim_buf_is_valid(chat_bufnr) then
        return nil
    end

    local lines = vim.api.nvim_buf_get_lines(chat_bufnr, 0, -1, false)
    local prompt_lines = {}
    local in_prompt = false

    -- Find the last prompt marker and extract everything after it
    for i = #lines, 1, -1 do
        if lines[i]:match("^> ") then
            -- Found the prompt marker, extract the prompt
            local first_line = lines[i]:sub(3) -- Remove "> " prefix
            if first_line ~= "" then
                table.insert(prompt_lines, 1, first_line)
            end
            -- Get any additional lines after the prompt marker
            for j = i + 1, #lines do
                if lines[j] ~= "" then
                    table.insert(prompt_lines, lines[j])
                end
            end
            break
        end
    end

    if #prompt_lines == 0 then
        return nil
    end

    return table.concat(prompt_lines, "\n")
end

-- Append text to the chat buffer
function M.append_to_chat(text, is_user)
    if not chat_bufnr or not vim.api.nvim_buf_is_valid(chat_bufnr) then
        return
    end

    local lines = vim.api.nvim_buf_get_lines(chat_bufnr, 0, -1, false)

    -- Remove empty prompt line if it exists
    if lines[#lines] == "> " then
        table.remove(lines)
    end

    -- Add the message
    if is_user then
        table.insert(lines, "## User")
        table.insert(lines, "")
        table.insert(lines, text)
    else
        table.insert(lines, assistant_marker)
        table.insert(lines, "")
        -- Split text into lines and add them
        local text_lines = vim.split(text, "\n", { plain = true })
        for _, line in ipairs(text_lines) do
            table.insert(lines, line)
        end
    end

    -- Add separator
    table.insert(lines, separator)
    table.insert(lines, "")

    -- Update buffer
    vim.api.nvim_buf_set_lines(chat_bufnr, 0, -1, false, lines)

    -- Add new prompt marker
    M.add_prompt_marker()

    -- Scroll to bottom
    local win = vim.fn.bufwinnr(chat_bufnr)
    if win ~= -1 then
        local win_id = vim.fn.win_getid(win)
        vim.api.nvim_win_set_cursor(win_id, { vim.api.nvim_buf_line_count(chat_bufnr), 0 })
    end
end

-- Parse JSON response from Claude CLI
function M.parse_claude_response(data)
    -- Try to parse JSON
    local ok, decoded = pcall(vim.json.decode, data)
    if not ok then
        return nil, nil
    end

    -- Extract the result text and session ID
    local result = nil
    local session_id = nil
    
    if decoded.type == "result" and decoded.result then
        result = decoded.result
    end
    
    if decoded.session_id then
        session_id = decoded.session_id
    end

    return result, session_id
end

-- Send the current prompt to Claude
function M.send_prompt()
    if is_processing then
        vim.notify("Claude is still processing. Please wait.", vim.log.levels.WARN)
        return
    end

    local prompt = M.get_current_prompt()
    if not prompt or prompt == "" then
        vim.notify("Please enter a prompt after the '>' marker", vim.log.levels.WARN)
        return
    end

    -- Mark as processing
    is_processing = true

    -- Add user message to chat
    M.append_to_chat(prompt, true)

    -- Prepare Claude command
    local cmd = "claude"
    local args = {
        "--output-format",
        "json",
        "--permission-prompt-tool",
        "mcp__permission__approval_prompt",
        "--system-prompt",
        "You are an AI assitant integrated into neovim. You responses are always rendered in Markdown. The permission prompt tool mcp is used to request user approval for actions that require it. It is also integrated into the MCP server running in the background.",
        "--mcp-config",
        "/Users/danielr/dotfiles/.config/nvim/config.json",
    }
    
    -- Add resume flag if we have a session ID
    if current_session_id then
        table.insert(args, "--resume")
        table.insert(args, current_session_id)
    end
    
    table.insert(args, "-p")
    table.insert(args, prompt)

    local response_buffer = ""

    -- Start the job
    job_id = vim.fn.jobstart({ cmd, unpack(args) }, {
        stdout_buffered = false,
        stderr_buffered = false,
        pty = true,
        on_stdout = function(_, data)
            if data then
                for _, line in ipairs(data) do
                    if line ~= "" then
                        response_buffer = response_buffer .. line

                        -- Try to parse complete JSON response
                        local response, session_id = M.parse_claude_response(response_buffer)
                        if response then
                            vim.schedule(function()
                                -- Update session ID if we got one
                                if session_id then
                                    current_session_id = session_id
                                end
                                M.append_to_chat(response, false)
                                response_buffer = ""
                            end)
                        end
                    end
                end
            end
        end,
        on_stderr = function(_, data)
            if data then
                for _, line in ipairs(data) do
                    if line ~= "" then
                        vim.schedule(function()
                            vim.notify("Claude error: " .. line, vim.log.levels.ERROR)
                        end)
                    end
                end
            end
        end,
        on_exit = function(_, exit_code)
            is_processing = false
            if exit_code ~= 0 then
                vim.schedule(function()
                    vim.notify("Claude command failed with exit code: " .. exit_code, vim.log.levels.ERROR)
                end)
            end
        end,
    })

    if job_id <= 0 then
        is_processing = false
        vim.notify("Failed to start Claude command", vim.log.levels.ERROR)
    end
end

-- Clear the chat
function M.clear_chat()
    if not chat_bufnr or not vim.api.nvim_buf_is_valid(chat_bufnr) then
        return
    end

    conversation = {}
    current_session_id = nil

    local welcome = {
        "# Claude Chat",
        "",
        "Type your message after the '>' prompt at the bottom.",
        "Press `<CR>` in normal mode on the last line to send.",
        "",
        "Commands:",
        "- `:ClaudeSend` - Send the current prompt",
        "- `:ClaudeClear` - Clear the chat",
        "",
        separator,
        "",
        "> ",
    }
    vim.api.nvim_buf_set_lines(chat_bufnr, 0, -1, false, welcome)

    -- Move cursor to prompt
    local line_count = vim.api.nvim_buf_line_count(chat_bufnr)
    vim.api.nvim_win_set_cursor(0, { line_count, 2 })
end

-- Check if cursor is on the prompt line
function M.is_on_prompt_line()
    if not chat_bufnr or not vim.api.nvim_buf_is_valid(chat_bufnr) then
        return false
    end

    local cursor = vim.api.nvim_win_get_cursor(0)
    local current_line = cursor[1]
    local lines = vim.api.nvim_buf_get_lines(chat_bufnr, current_line - 1, current_line, false)

    if #lines > 0 then
        return lines[1]:match("^> ") ~= nil
    end

    -- Also check if we're on lines immediately after the prompt marker
    for i = current_line - 1, math.max(1, current_line - 5), -1 do
        lines = vim.api.nvim_buf_get_lines(chat_bufnr, i - 1, i, false)
        if #lines > 0 and lines[1]:match("^> ") then
            return true
        elseif #lines > 0 and lines[1]:match("^---") then
            -- Hit a separator, not in prompt area
            return false
        end
    end

    return false
end

-- Create user commands
vim.api.nvim_create_user_command("ClaudeChat", M.open_chat, {})
vim.api.nvim_create_user_command("ClaudeSend", M.send_prompt, {})
vim.api.nvim_create_user_command("ClaudeClear", M.clear_chat, {})

return M
