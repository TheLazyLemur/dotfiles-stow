local M = {}

local REQUIRED_NVIM_VERSION = "nvim-0.11"
local REQUIRED_VERSION_MESSAGE = "Neovim version 0.11 or higher is required"

function M.check()
    if not vim.fn.has(REQUIRED_NVIM_VERSION) then
        vim.notify(REQUIRED_VERSION_MESSAGE)
        return false
    end
    return true
end

return M

