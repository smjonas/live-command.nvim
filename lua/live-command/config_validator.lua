local M = {}

local user_command = require("live-command.user_command")

---@class livecmd.Config.HlGroups
---@field insertion string|false
---@field deletion string|false
---@field change string|false

---@class livecmd.Config
---@field command_name string?
---@field enable_highlighting boolean?
---@field inline_highlighting boolean?
---@field hl_groups livecmd.Config.HlGroups?

---@param config livecmd.Config
M.validate_config = function(config)
  vim.validate {
    command_name = { config.command_name, "string" },
    enable_highlighting = { config.enable_highlighting, "boolean" },
    inline_highlighting = { config.inline_highlighting, "boolean" },
    hl_groups = { config.hl_groups, "table" },
  }
  user_command.register_argument_handler("help", function()
    print("Help")
  end)
end

return M
