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

local get_affected_cmd_names = function(config, is_affected_cmd_fn)
  local affected_cmds = {}
  for cmd_name, cmd_spec in pairs(config.commands) do
    if is_affected_cmd_fn(cmd_spec) then
      table.insert(affected_cmds, '"' .. cmd_name .. '"')
    end
  end
  return table.concat(affected_cmds, ", "), #affected_cmds
end

local get_args_range_diagnostics_message = function(config)
  local message = [[
- Dropped support for the "args" and "range" keys in the command specification:
The following commands in your configuration are affected: %s. Please remove or modify them.

]]
  local cmd_names, cmd_count = get_affected_cmd_names(config, function(cmd_spec)
    return cmd_spec.args ~= nil or cmd_spec.range ~= nil
  end)
  if cmd_count == 0 then
    return ""
  end
  return string.format(message, cmd_names)
end

local get_per_command_diagnostics_message = function(config)
  local message = [[
- Dropped support for per-command options:
You can no longer set any of the options "enable_highlighting", "inline_highlighting" or "hl_groups" for individual commands.
The following commands are affected: %s.
Please just set the options for all commands like this:
require("live-command").setup {
  enable_highlighting = ...,
  inline_highlighting = ...,
  hl_groups = {
    ...
  },
}

]]
  local cmd_names, cmd_count = get_affected_cmd_names(config, function(cmd_spec)
    return cmd_spec.enable_highlighting ~= nil or cmd_spec.inline_highlighting ~= nil or cmd_spec.hl_groups ~= nil
  end)
  if cmd_count == 0 then
    return ""
  end
  return string.format(message, cmd_names)
end

local get_defaults_diagnostics_message = function(config)
  if config.defaults == nil then
    return ""
  end
  return [[
- Inlined the "defaults" option:
To set any of the options "enable_highlighting", "inline_highlighting" or "hl_groups", you should no longer use the "defaults" table.
Instead, just set the options like this:
require("live-command").setup {
  enable_highlighting = ...,
  inline_highlighting = ...,
  hl_groups = {
    ...
  },
}

]]
end

local show_diagnostics_message = function(config)
  local message = [[
Version 2.x of live-command.nvim has introduced some changes to the configuration:
%s%s%sSee the migration guide for more information: https://github.com/smjonas/live-command.nvim/blob/main/migrate_to_v2.md
]]
  local warning_msg_1 = get_args_range_diagnostics_message(config)
  local warning_msg_2 = get_per_command_diagnostics_message(config)
  local warning_msg_3 = get_defaults_diagnostics_message(config)
  local formatted_message = message:format(warning_msg_1, warning_msg_2, warning_msg_3)
  vim.notify(formatted_message, vim.log.levels.INFO)
end

local are_unsupported_features_used = function(config)
  if config.defaults ~= nil then
    return true
  end
  for _, cmd_spec in pairs(config.commands) do
    if
      cmd_spec.args ~= nil
      or cmd_spec.range ~= nil
      or cmd_spec.enable_highlighting ~= nil
      or cmd_spec.inline_highlighting ~= nil
      or cmd_spec.hl_groups ~= nil
    then
      return true
    end
  end
end

---@param config livecmd.Config
M.validate_config = function(config)
  vim.validate("command_name", config.command_name, "string")
  vim.validate("enable_highlighting", config.enable_highlighting, "boolean")
  vim.validate("inline_highlighting", config.inline_highlighting, "boolean")
  vim.validate("hl_groups", config.hl_groups, "table")
  vim.validate("commands", config.commands, "table")
  if are_unsupported_features_used(config) then
    vim.notify(
      '[live-command.nvim] Some unsupported features are used in your config. Please run ":LiveCommand diagnose" for details.',
      vim.log.levels.WARN
    )
    user_command.register_argument_handler("diagnose", function()
      show_diagnostics_message(config)
    end)
  end
end

return M
