-- Constants and configuration for Claude integration
local M = {}

-- Server configuration
M.SERVER = {
    MAX_LOG_ENTRIES = 1000,
    PORT = ":8080",
    STRATEGY = "stdio",
    COMMAND = "agent",
}

-- UI configuration  
M.UI = {
    SEPARATOR = " ",
    ASSISTANT_MARKER = "## Claude",
    USER_MARKER = "## User",
    PROMPT_MARKER = "> ",
    PROMPT_SEARCH_RANGE = 5,
    TRUNCATE_LENGTH = 50,
    WELCOME_TITLE = "# Claude Chat",
}

-- Buffer configuration
M.BUFFER = {
    NAME = "Claude Chat",
    TYPE = "nofile",
    HIDDEN = "hide",
    FILETYPE = "markdown",
}

-- Command configuration
M.COMMAND = {
    CLAUDE_BINARY = "claude",
    OUTPUT_FORMAT = "stream-json",
    MCP_CONFIG_PATH = "/Users/danielr/dotfiles/.config/nvim/config.json",
    DEFAULT_TIMEOUT = 120000, -- 2 minutes
}

-- Message types
M.MESSAGE_TYPES = {
    SYSTEM = "system",
    ASSISTANT = "assistant",
    USER = "user",
    RESULT = "result",
    PERMISSION_REQUEST = "permission_request",
    PERMISSION_RESPONSE = "permission_response",
}

-- Message subtypes
M.MESSAGE_SUBTYPES = {
    INIT = "init",
}

-- Content types
M.CONTENT_TYPES = {
    TEXT = "text",
    TOOL_USE = "tool_use",
    TOOL_RESULT = "tool_result",
}

-- Log levels for consistency with vim.log.levels
M.LOG_LEVELS = {
    DEBUG = vim.log.levels.DEBUG,
    INFO = vim.log.levels.INFO,
    WARN = vim.log.levels.WARN,
    ERROR = vim.log.levels.ERROR,
}

-- Tool names
M.TOOLS = {
    EDIT = "Edit",
}

-- Icons/indicators
M.ICONS = {
    TOOL = "🔧",
    ERROR = "❌",
    SUCCESS = "✅",
    MONEY = "💰",
}

return M