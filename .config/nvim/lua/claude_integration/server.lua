local M = {}

local mcp_job_id = nil
local mcp_log_buffer = {}
local pending_requests = {}
local message_buffer = ""

local log_mcp_data = function(data, source)
    local timestamp = os.date("%H:%M:%S")
    local log_entry = string.format("[%s] MCP %s: %s", timestamp, source, vim.inspect(data))
    table.insert(mcp_log_buffer, log_entry)
    print(log_entry)
end

-- Forward declarations
local show_permission_prompt
local send_permission_response

-- Helper functions for diff preview
local apply_edit_to_content = function(content, old_string, new_string)
    local start_pos, end_pos = string.find(content, old_string, 1, true)
    if not start_pos then
        return nil, "Could not find exact match for old_string"
    end
    return string.sub(content, 1, start_pos - 1) .. new_string .. string.sub(content, end_pos + 1)
end

local setup_diff_preview = function(buf, original_content)
    vim.b[buf].minidiff_config = {
        source = require("mini.diff").gen_source.none(),
    }
    require("mini.diff").enable(buf)
    require("mini.diff").set_ref_text(buf, original_content)
    require("mini.diff").toggle_overlay(buf)
end

local cleanup_diff_view = function(buf, file_path)
    require("mini.diff").toggle_overlay(buf)
    require("mini.diff").disable(buf)

    if vim.fn.filereadable(file_path) == 1 then
        vim.cmd("edit! " .. vim.fn.fnameescape(file_path))
    else
        vim.cmd("tabclose")
    end
end

local setup_diff_keymaps = function(buf, request_id, file_path)
    local opts = { buffer = buf, silent = true }

    vim.keymap.set("n", "<leader>a", function()
        send_permission_response(request_id, true)
        cleanup_diff_view(buf, file_path)
    end, opts)

    vim.keymap.set("n", "<leader>r", function()
        send_permission_response(request_id, false)
        cleanup_diff_view(buf, file_path)
    end, opts)

    vim.keymap.set("n", "<leader>?", function()
        print("MiniDiff view: <leader>a = Accept, <leader>r = Reject, <leader>? = Help")
    end, opts)
end

local handle_existing_file_diff = function(file_path, old_string, new_string)
    vim.cmd("edit " .. vim.fn.fnameescape(file_path))
    local buf = vim.api.nvim_get_current_buf()

    local current_content = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
    local modified_content, error_msg = apply_edit_to_content(current_content, old_string, new_string)

    if not modified_content then
        print("Warning: " .. error_msg)
        return nil
    end

    local modified_lines = vim.split(modified_content, "\n", { plain = true })
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, modified_lines)

    setup_diff_preview(buf, current_content)
    return buf
end

local handle_new_file_diff = function(file_path, new_string)
    vim.cmd("tabnew")
    local buf = vim.api.nvim_get_current_buf()

    local new_lines = vim.split(new_string, "\n", { plain = true })
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, new_lines)

    local filename = vim.fn.fnamemodify(file_path, ":t")
    vim.api.nvim_buf_set_name(buf, "NEW: " .. filename)
    vim.bo[buf].filetype = vim.fn.fnamemodify(file_path, ":e")

    setup_diff_preview(buf, "")
    return buf
end

local show_edit_diff_preview = function(request)
    local file_path = request.input.file_path or "unknown file"
    local old_string = request.input.old_string or ""
    local new_string = request.input.new_string or ""

    local buf
    if vim.fn.filereadable(file_path) == 1 then
        buf = handle_existing_file_diff(file_path, old_string, new_string)
    else
        buf = handle_new_file_diff(file_path, new_string)
    end

    if not buf then
        return
    end

    setup_diff_keymaps(buf, request.id, file_path)

    print("MCP Edit Request for: " .. file_path)
    print("MiniDiff overlay enabled - Press <leader>a to Accept, <leader>r to Reject, <leader>? for help")
end

send_permission_response = function(request_id, allowed)
    if not mcp_job_id then
        log_mcp_data("No MCP server running to send response", "ERROR")
        return
    end

    local response = {
        type = "permission_response",
        id = request_id,
        allowed = allowed,
    }

    local response_json = vim.json.encode(response)
    local data_to_send = response_json .. "\n"

    vim.fn.chansend(mcp_job_id, data_to_send)
    log_mcp_data("Sent response: " .. response_json, "RESPONSE")

    pending_requests[request_id] = nil
end

show_permission_prompt = function(request)
    local message

    if request.tool == "Edit" and request.input then
        vim.schedule(function()
            show_edit_diff_preview(request)
        end)
        return
    else
        local input_str = vim.json.encode(request.input or {})
        message = string.format(
            "MCP Permission Request\n\nTool: %s\nInput: %s\n\nAllow this operation?",
            request.tool or "unknown",
            input_str
        )
    end

    vim.schedule(function()
        local choice
        local success, result = pcall(vim.fn.confirm, message, "&Allow\n&Deny\n&Details", 2)
        if success then
            choice = result
        else
            log_mcp_data("vim.fn.confirm failed, using input fallback", "UI")
            local response = vim.fn.input("Allow (y/n)? ")
            choice = (response:lower():match("^y") and 1) or 2
        end

        local allowed = (choice == 1)
        log_mcp_data("User " .. (allowed and "ALLOWED" or "DENIED") .. " " .. request.tool .. " request", "DECISION")

        if choice == 3 then
            local buf = vim.api.nvim_create_buf(false, true)
            local lines = {
                "=== MCP Permission Request Details ===",
                "",
                "Request ID: " .. (request.id or "unknown"),
                "Tool Name: " .. (request.tool or "unknown"),
                "Type: " .. (request.type or "unknown"),
                "",
                "Input (formatted):",
            }

            local formatted_input = vim.split(vim.inspect(request.input), "\n")
            vim.list_extend(lines, formatted_input)

            vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
            vim.bo[buf].modifiable = false
            vim.bo[buf].filetype = "json"

            vim.cmd("split")
            vim.api.nvim_win_set_buf(0, buf)

            vim.defer_fn(function()
                local final_choice = vim.fn.confirm("Allow this operation?", "&Allow\n&Deny", 2)
                allowed = (final_choice == 1)
                send_permission_response(request.id, allowed)
            end, 100)
        else
            send_permission_response(request.id, allowed)
        end
    end)
end

local handle_mcp_request = function(json_line)
    if not json_line or json_line == "" then
        return
    end

    local success, request = pcall(vim.json.decode, json_line)
    if not success then
        if string.match(json_line, "^%s*{") then
            log_mcp_data("Failed to parse JSON: " .. json_line, "ERROR")
        end
        return
    end

    if type(request) == "table" and request.type == "permission_request" then
        log_mcp_data("Permission request for " .. (request.tool or "unknown") .. " tool", "REQUEST")
        pending_requests[request.id] = request
        show_permission_prompt(request)
    end
end

local process_stdout_data = function(data)
    for _, chunk in ipairs(data) do
        if chunk and chunk ~= "" then
            message_buffer = message_buffer .. chunk
        end
    end

    while true do
        local start_pos = message_buffer:find("{")
        if not start_pos then
            break
        end

        local brace_count = 0
        local end_pos = nil

        for i = start_pos, #message_buffer do
            local char = message_buffer:sub(i, i)
            if char == "{" then
                brace_count = brace_count + 1
            elseif char == "}" then
                brace_count = brace_count - 1
                if brace_count == 0 then
                    end_pos = i
                    break
                end
            end
        end

        if end_pos then
            local json_str = message_buffer:sub(start_pos, end_pos)
            handle_mcp_request(json_str)
            message_buffer = message_buffer:sub(end_pos + 1)
        else
            break
        end
    end
end

local mcp_server_start = function()
    if mcp_job_id then
        print("MCP server already running with job ID: " .. mcp_job_id)
        return
    end

    local cmd = "agent"
    local args = { "--port", ":8080", "--strategy", "stdio" }

    local job_opts = {
        on_stdout = function(_, data, _)
            if data and #data > 0 then
                process_stdout_data(data)
            end
        end,
        on_stderr = function(_, data, _)
            if data and #data > 0 then
                for _, line in ipairs(data) do
                    if line ~= "" then
                        log_mcp_data(line, "STDERR")
                    end
                end
            end
        end,
        on_exit = function(_, exit_code, _)
            log_mcp_data("Server exited with code: " .. exit_code, "EXIT")
            mcp_job_id = nil
        end,
        stdout_buffered = false,
        stderr_buffered = false,
    }

    mcp_job_id = vim.fn.jobstart({ cmd, unpack(args) }, job_opts)

    if mcp_job_id > 0 then
        log_mcp_data("MCP server started with job ID: " .. mcp_job_id, "START")
    else
        log_mcp_data("Failed to start MCP server. Error code: " .. mcp_job_id, "ERROR")
        mcp_job_id = nil
    end
end

local mcp_server_stop = function()
    if mcp_job_id then
        vim.fn.jobstop(mcp_job_id)
        log_mcp_data("Stopping MCP server with job ID: " .. mcp_job_id, "STOP")
        mcp_job_id = nil
    else
        print("No MCP server running")
    end
end

local get_mcp_logs = function()
    return mcp_log_buffer
end

local clear_mcp_logs = function()
    mcp_log_buffer = {}
    print("MCP logs cleared")
end

M.start = mcp_server_start
M.stop = mcp_server_stop
M.get_logs = get_mcp_logs
M.clear_logs = clear_mcp_logs
M.is_running = function()
    return mcp_job_id ~= nil
end

M.get_pending_requests = function()
    return pending_requests
end

M.respond_to_request = function(request_id, allowed)
    if pending_requests[request_id] then
        send_permission_response(request_id, allowed)
        return true
    end
    return false
end

return M
