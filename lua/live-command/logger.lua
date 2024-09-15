---@class Logger
local M = {}

local user_command = require("live-command.user_command")

---@type Log[]
local logs = {}

---@class Log
---@field msg string
---@field level number
---@field trace string | fun(): string
---@field error string | fun(): string

---@param msg string | fun(): string
M.trace = function(msg)
  table.insert(logs, { msg = msg, level = vim.log.levels.TRACE })
end

---@param msg string | fun(): string
M.error = function(msg)
  table.insert(logs, { msg = msg, level = vim.log.levels.ERROR })
end

local show_log = function()
  local msgs = {}
  for i, log in ipairs(logs) do
    local level = ""
    if log.level == vim.log.levels.TRACE then
      level = "[TRACE] "
    elseif log.level == vim.log.levels.ERROR then
      level = "[ERROR] "
    end
    msgs[i] = level .. (type(log.msg) == "function" and log.msg() or log.msg)
  end
  vim.notify(table.concat(msgs, "\n"))
end

user_command.register_argument_handler("log", show_log)

return M
