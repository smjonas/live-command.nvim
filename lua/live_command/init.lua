local M = {}

M.setup = function(user_config)
  vim.notify(
    "[live-command]: The Lua module live_command has been renamed to live-command to match the repo name.\n"
      .. 'Please change require("live_command") to require("live-command").',
    vim.log.levels.WARN
  )
  require("live-command").setup(user_config)
end

return M
