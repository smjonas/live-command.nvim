local M = {}

local differ = require("live-command.differ")
local highlighter = require("live-command.highlighter")
local logger = require("live-command.logger")

---@type string
local latest_cmd

local running = false

local refetch_lines = true

---@tyle string[]
local cached_lines

---@type boolean
local prev_lazyredraw

local setup = function(bufnr)
  prev_lazyredraw = vim.o.lazyredraw
  vim.o.lazyredraw = true
  if refetch_lines then
    cached_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    refetch_lines = false
  else
    logger.trace("did not refetch for cmd " .. latest_cmd)
  end
  return cached_lines
end

M.teardown = function(do_refetch_lines)
  vim.o.lazyredraw = prev_lazyredraw
  refetch_lines = do_refetch_lines
  if vim.v.errmsg ~= "" then
    logger.error(("An error occurred in the preview function:\n%s"):format(vim.inspect(vim.v.errmsg)))
  end
end

local execute_command = function(cmd, bufnr)
  local old_buf_lines = setup(bufnr)
  local visible_line_range = { vim.fn.line("w0"), vim.fn.line("w$") }
  vim.api.nvim_buf_call(bufnr, function()
    vim.cmd(cmd)
  end)
  -- M.teardown(false)
  visible_line_range = {
    math.max(visible_line_range[1], vim.fn.line("w0")),
    math.max(visible_line_range[2], vim.fn.line("w$")),
  }
  local new_buf_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  return old_buf_lines, new_buf_lines, visible_line_range
end

---@param cmd string
---@param opts livecmd.Config
---@param bufnr number
---@param update_buffer_cb fun(bufnr:number,updated_buffer_lines:string[],highlights:livecmd.Highlight[]?)
M.submit_command = function(cmd, opts, bufnr, update_buffer_cb)
  if cmd == latest_cmd then
    return
  end
  latest_cmd = cmd
  if not running then
    running = true
    local old_buf_lines, new_buf_lines, line_range = execute_command(cmd, bufnr)
    if not opts.enable_highlighting then
      update_buffer_cb(bufnr, new_buf_lines, nil)
      running = false
      return
    end
    local diff = differ.get_diff(old_buf_lines, new_buf_lines)
    local highlights, updated_buf_lines = highlighter.get_highlights(
      diff,
      old_buf_lines,
      new_buf_lines,
      line_range,
      opts.inline_highlighting,
      opts.hl_groups.deletion ~= false
    )
    update_buffer_cb(bufnr, updated_buf_lines, highlights)
    running = false
  end
end

return M
