---@class Logger
local M = {}

---@type Log[]
local logs = {}

---@class Log
---@field msg string
---@field level number

---@param msg string|fun():string
M.trace = function(msg)
  msg = type(msg) == "function" and msg() or msg
  table.insert(logs, { msg = msg, level = vim.log.levels.TRACE })
end

---@param msg string|fun():string
M.error = function(msg)
  msg = type(msg) == "function" and msg() or msg
  table.insert(logs, { msg = msg, level = vim.log.levels.ERROR })
end

vim.api.nvim_create_user_command("LiveCommandLog", function()
  local msgs = {}
  for i, log in ipairs(logs) do
    local level = ""
    if log.level == vim.log.levels.TRACE then
      level = "[TRACE] "
    elseif log.level == vim.log.levels.ERROR then
      level = "[ERROR] "
    end
    msgs[i] = level .. log.msg
  end

  vim.notify(table.concat(msgs, "\n"))
end, { nargs = 0 })

return M
