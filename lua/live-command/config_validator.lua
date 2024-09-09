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
---@field commands table<string, livecmd.CommandSpec>

local show_diagnostics_message = function(config)
  local message = [[
Version 2.0 of live-command.nvim has dropped support for the "args" and "range" keys in the command specification.
The following commands in your configuration are affected: %s. Please remove or modify them.
See the migration guide for more information: https://github.com/smjonas/live-command.nvim/blob/main/migrate_to_v2.md
  ]]
  local affected_cmds = {}
  for cmd_name, cmd_spec in pairs(config.commands) do
    if cmd_spec.args ~= nil or cmd_spec.range ~= nil then
      table.insert(affected_cmds, '"' .. cmd_name .. '"')
    end
  end
  local cmd_names = table.concat(affected_cmds, ", ")
  local formatted_message = string.format(message, cmd_names)
  vim.notify(formatted_message, vim.log.levels.INFO)
end

---@param config livecmd.Config
M.validate_config = function(config)
  vim.validate {
    command_name = { config.command_name, "string" },
    enable_highlighting = { config.enable_highlighting, "boolean" },
    inline_highlighting = { config.inline_highlighting, "boolean" },
    hl_groups = { config.hl_groups, "table" },
    commands = { config.commands, "table" },
  }
  for cmd_name, cmd_spec in pairs(config.commands) do
    if cmd_spec.args ~= nil or cmd_spec.range ~= nil then
      vim.notify(
        '[live-command.nvim] Some unsupported features are used in your config. Please run ":LiveCommand diagnose" for details.',
        vim.log.levels.WARN
      )
      user_command.register_argument_handler("diagnose", function()
        show_diagnostics_message(config)
      end)
    end
  end
end

return M
