local version = require("version")

local function setup()
    if not version.check() then
        return
    end

    require("core")
    local claude = require("claude_integration")
    claude.setup()
end

setup()
