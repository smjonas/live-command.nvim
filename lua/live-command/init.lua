local M = {}

local cmd_executor = require("live-command.cmd_executor")
local api = vim.api

local received_highlights

local create_preview_command = function()
  api.nvim_create_user_command("Preview", function() end, {
    nargs = "*",
    preview = function(opts, preview_ns, preview_buf)
      local cmd = opts.args
      vim.v.errmsg = cmd
      if received_highlights then
        api.nvim_set_current_line(received_highlights)
      end
      cmd_executor.submit_command(cmd, preview_buf or 0, M.receive_highlights)
      return 2
    end
  })
end

local refresh_cmd_preview = function()
  local backspace = api.nvim_replace_termcodes("<bs>", true, false, true)
  -- Hack to trigger command preview again after new buffer contents have been computed
  if api.nvim_get_mode().mode == "c" then
    api.nvim_feedkeys("a" .. backspace, "n", false)
  end
end

M.receive_highlights = function(highlights, bufnr)
  received_highlights = highlights
  refresh_cmd_preview()
end

M.setup = function()
  create_preview_command()
end

M.version = "2.0.0"

return M
