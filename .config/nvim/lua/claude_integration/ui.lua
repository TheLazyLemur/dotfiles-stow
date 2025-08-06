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

-- Parse streaming ND-JSON response from Claude CLI
function M.parse_claude_streaming_message(data)
    local ok, decoded = pcall(vim.json.decode, data)
    if not ok then
        return nil
    end

    return decoded
end

-- Track message state for streaming updates
local message_tracker = {
    current_assistant_message_id = nil,
    current_assistant_content = {},
    current_tool_uses = {}
}

-- Handle different types of streaming messages
function M.handle_streaming_message(message)
    if not message or not message.type then
        return
    end

    if message.type == "system" then
        M.handle_system_message(message)
    elseif message.type == "assistant" then
        M.handle_assistant_message(message)
    elseif message.type == "user" then
        M.handle_user_message(message)
    elseif message.type == "result" then
        M.handle_result_message(message)
    end
end

-- Handle system initialization messages
function M.handle_system_message(message)
    if message.subtype == "init" and message.session_id then
        current_session_id = message.session_id
    end
end

-- Handle assistant messages (text and tool use)
function M.handle_assistant_message(message)
    if not message.message then
        return
    end

    local msg = message.message
    local message_id = msg.id

    -- Check if this is a new message or update to existing
    if message_tracker.current_assistant_message_id ~= message_id then
        -- New message - add Claude marker if we haven't started streaming yet
        if message_tracker.current_assistant_message_id == nil then
            M.add_assistant_marker()
        else
            -- Finish previous message and start new one
            M.finalize_current_message()
            M.add_assistant_marker()
        end
        message_tracker.current_assistant_message_id = message_id
        message_tracker.current_assistant_content = {}
        message_tracker.current_tool_uses = {}
    end

    -- Process content
    if msg.content then
        for _, content_block in ipairs(msg.content) do
            if content_block.type == "text" then
                M.handle_text_content(content_block.text)
            elseif content_block.type == "tool_use" then
                M.handle_tool_use_content(content_block)
            end
        end
    end
end

-- Handle user messages (tool results)
function M.handle_user_message(message)
    -- Usually tool results, we can show these as system messages
    if message.message and message.message.content then
        for _, content_block in ipairs(message.message.content) do
            if content_block.type == "tool_result" then
                M.show_tool_result(content_block)
            end
        end
    end
end

-- Handle final result message
function M.handle_result_message(message)
    -- Finalize any current message
    M.finalize_current_message()
    
    -- Show session summary if needed
    if message.total_cost_usd then
        M.show_session_summary(message)
    end
end

-- Helper functions for content handling

-- Add assistant marker to start a new assistant response
function M.add_assistant_marker()
    if not chat_bufnr or not vim.api.nvim_buf_is_valid(chat_bufnr) then
        return
    end

    local lines = vim.api.nvim_buf_get_lines(chat_bufnr, 0, -1, false)
    
    -- Remove empty prompt line if it exists
    if lines[#lines] == "> " then
        table.remove(lines)
    end

    table.insert(lines, assistant_marker)
    table.insert(lines, "")
    
    vim.api.nvim_buf_set_lines(chat_bufnr, 0, -1, false, lines)
end

-- Handle streaming text content
function M.handle_text_content(text)
    if not text or text == "" then
        return
    end
    
    -- Update the current message content
    table.insert(message_tracker.current_assistant_content, text)
    M.update_current_message_display()
end

-- Handle tool use content
function M.handle_tool_use_content(tool_use)
    if not tool_use.name then
        return
    end
    
    message_tracker.current_tool_uses[tool_use.id] = tool_use
    
    -- Show tool usage indicator
    local tool_indicator = "🔧 Using tool: " .. tool_use.name
    if tool_use.input then
        local input_summary = ""
        for key, value in pairs(tool_use.input) do
            if type(value) == "string" and #value > 50 then
                input_summary = input_summary .. key .. ": " .. value:sub(1, 50) .. "... "
            else
                input_summary = input_summary .. key .. ": " .. tostring(value) .. " "
            end
        end
        if input_summary ~= "" then
            tool_indicator = tool_indicator .. " (" .. input_summary:sub(1, -2) .. ")"
        end
    end
    
    table.insert(message_tracker.current_assistant_content, tool_indicator)
    M.update_current_message_display()
end

-- Show tool result
function M.show_tool_result(tool_result)
    if tool_result.is_error then
        local error_msg = "❌ Tool error: " .. (tool_result.content or "Unknown error")
        table.insert(message_tracker.current_assistant_content, error_msg)
    else
        local result_msg = "✅ Tool completed"
        -- Don't show full result content as it can be very long
        table.insert(message_tracker.current_assistant_content, result_msg)
    end
    M.update_current_message_display()
end

-- Update the current message display in real-time
function M.update_current_message_display()
    if not chat_bufnr or not vim.api.nvim_buf_is_valid(chat_bufnr) then
        return
    end
    
    local lines = vim.api.nvim_buf_get_lines(chat_bufnr, 0, -1, false)
    
    -- Find the last assistant marker
    local assistant_marker_line = nil
    for i = #lines, 1, -1 do
        if lines[i] == assistant_marker then
            assistant_marker_line = i
            break
        end
    end
    
    if not assistant_marker_line then
        return
    end
    
    -- Remove old content after the marker
    local new_lines = {}
    for i = 1, assistant_marker_line + 1 do
        table.insert(new_lines, lines[i])
    end
    
    -- Add current content
    local content_text = table.concat(message_tracker.current_assistant_content, "\n")
    local content_lines = vim.split(content_text, "\n", { plain = true })
    for _, line in ipairs(content_lines) do
        table.insert(new_lines, line)
    end
    
    vim.api.nvim_buf_set_lines(chat_bufnr, 0, -1, false, new_lines)
    
    -- Scroll to bottom
    local win = vim.fn.bufwinnr(chat_bufnr)
    if win ~= -1 then
        local win_id = vim.fn.win_getid(win)
        vim.api.nvim_win_set_cursor(win_id, { vim.api.nvim_buf_line_count(chat_bufnr), 0 })
    end
end

-- Finalize current message and prepare for next
function M.finalize_current_message()
    if message_tracker.current_assistant_message_id then
        -- Add separator and prepare for next message
        if chat_bufnr and vim.api.nvim_buf_is_valid(chat_bufnr) then
            local lines = vim.api.nvim_buf_get_lines(chat_bufnr, 0, -1, false)
            table.insert(lines, "")
            table.insert(lines, separator)
            table.insert(lines, "")
            vim.api.nvim_buf_set_lines(chat_bufnr, 0, -1, false, lines)
        end
    end
    
    -- Reset tracker
    message_tracker.current_assistant_message_id = nil
    message_tracker.current_assistant_content = {}
    message_tracker.current_tool_uses = {}
end

-- Show session summary
function M.show_session_summary(result_message)
    if not chat_bufnr or not vim.api.nvim_buf_is_valid(chat_bufnr) then
        return
    end
    
    local lines = vim.api.nvim_buf_get_lines(chat_bufnr, 0, -1, false)
    
    local summary = string.format(
        "💰 Session complete - Cost: $%.4f | Duration: %.1fs | Tokens: %d",
        result_message.total_cost_usd or 0,
        (result_message.duration_ms or 0) / 1000,
        (result_message.usage and result_message.usage.input_tokens or 0) + 
        (result_message.usage and result_message.usage.output_tokens or 0)
    )
    
    table.insert(lines, summary)
    table.insert(lines, "")
    
    vim.api.nvim_buf_set_lines(chat_bufnr, 0, -1, false, lines)
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

    -- Reset message tracker for new conversation
    message_tracker.current_assistant_message_id = nil
    message_tracker.current_assistant_content = {}
    message_tracker.current_tool_uses = {}

    -- Add user message to chat
    M.append_to_chat(prompt, true)

    -- Prepare Claude command
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
    if current_session_id then
        table.insert(args, "--resume")
        table.insert(args, current_session_id)
    end

    table.insert(args, "-p")
    table.insert(args, prompt)

    -- Start the job
    job_id = vim.fn.jobstart({ cmd, unpack(args) }, {
        stdout_buffered = false,
        stderr_buffered = false,
        pty = true,
        on_stdout = function(_, data)
            if data then
                for _, line in ipairs(data) do
                    if line ~= "" and line ~= nil then
                        -- Each line should be a complete ND-JSON message
                        local message = M.parse_claude_streaming_message(line)
                        if message then
                            vim.schedule(function()
                                M.handle_streaming_message(message)
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
            vim.schedule(function()
                is_processing = false
                -- Finalize any remaining message and add prompt marker
                M.finalize_current_message()
                M.add_prompt_marker()
                
                if exit_code ~= 0 then
                    vim.notify("Claude command failed with exit code: " .. exit_code, vim.log.levels.ERROR)
                end
            end)
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
