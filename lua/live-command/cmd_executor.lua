local M = {}

local differ = require("live-command.differ")
local highlighter = require("live-command.highlighter")

local latest_cmd
local running = false

local execute_command = function(cmd, bufnr)
  local old_buf_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local visible_line_range = { vim.fn.line("w0"), vim.fn.line("w$") }
  vim.cmd(cmd)
  visible_line_range = {
    math.max(visible_line_range[1], vim.fn.line("w0")),
    math.max(visible_line_range[2], vim.fn.line("w$")),
  }
  local new_buf_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  return old_buf_lines, new_buf_lines, visible_line_range
end

---@param cmd LiveCommand
---@param bufnr number
M.submit_command = function(cmd, bufnr, on_receive_highlights)
  if cmd == latest_cmd then
    return
  end
  latest_cmd = cmd
  if not running then
    running = true
    local old_buf_lines, new_buf_lines, visible_line_range = execute_command(cmd, bufnr)
    local diff = differ.get_diff(old_buf_lines, new_buf_lines)
    local highlights = highlighter.get_highlights(diff, old_buf_lines, new_buf_lines, p)
    highlights = cmd
    on_receive_highlights(highlights, bufnr)
    running = false
  end
end

return M
