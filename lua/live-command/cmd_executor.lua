local M = {}

local differ = require("live-command.differ")
local highlighter = require("live-command.highlighter")

local latest_cmd
local running = false

local execute_command = function(cmd, bufnr)
  local old_buf_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  vim.cmd(cmd)
  -- Emulate slow-running command
  for i = 1, 1000000000 do
    old_buf_lines = old_buf_lines
  end
  local new_buf_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  return old_buf_lines, new_buf_lines
end

---@param cmd string
---@param bufnr number
M.submit_command = function(cmd, bufnr, on_receive_highlights)
  if cmd == latest_cmd then
    return
  end
  latest_cmd = cmd
  if not running then
    running = true
    local old_buf_lines, new_buf_lines = execute_command(cmd, bufnr)
    local diff = differ.get_diff(old_buf_lines, new_buf_lines)
    local highlights = highlighter.get_highlights(diff)
    highlights = cmd
    on_receive_highlights(highlights, bufnr)
    running = false
  end
end

return M
