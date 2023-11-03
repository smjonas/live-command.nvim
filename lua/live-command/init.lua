local M = {}

---@class livecmd.Config.HlGroups
---@field insertion string|false
---@field deletion string|false
---@field change string|false

---@class livecmd.Config
---@field enable_highlighting boolean
---@field inline_highlighting boolean
---@field hl_groups livecmd.Config.HlGroups

---@type livecmd.Config
M.defaults = {
  enable_highlighting = true,
  inline_highlighting = true,
  hl_groups = {
    insertion = "DiffAdd",
    deletion = "DiffDelete",
    change = "DiffChange",
  },
}

local cmd_executor = require("live-command.cmd_executor")
local api = vim.api

local prev_lazyredraw

---@type string[]
local received_lines

---@type livecmd.Highlight[]
local received_highlights

---@param bufnr number
---@param preview_ns number
---@param highlights livecmd.Highlight[]
---@param hl_groups table<string, string>
local apply_highlights = function(bufnr, preview_ns, highlights, hl_groups)
  for _, hl in ipairs(highlights) do
    local hl_group = hl_groups[hl.kind]
    if hl_group ~= false then
      api.nvim_buf_add_highlight(
        bufnr,
        preview_ns,
        hl_group,
        hl.line - 1,
        hl.column - 1,
        hl.length == -1 and -1 or hl.column + hl.length - 1
      )
    end
  end
end

local setup = function()
  prev_lazyredraw = vim.o.lazyredraw
  vim.o.lazyredraw = true
end

local teardown = function()
  vim.o.lazyredraw = prev_lazyredraw
end

local create_preview_command = function()
  api.nvim_create_user_command("Preview", function() end, {
    nargs = "*",
    preview = function(opts, preview_ns, preview_buf)
      setup()
      local cmd = opts.args
      if received_lines then
        api.nvim_buf_set_lines(0, 0, -1, false, received_lines)
        -- vim.g.kek = "received:" .. received_lines[1] .. ", new:" .. vim.g.lel
        -- require("live-command.logger").trace(function()
        --   return "rcv hls" .. vim.inspect(received_highlights) .. (vim.v.errmsg or "")
        -- end)
      end
      if received_highlights then
        apply_highlights(0, preview_ns, received_highlights, M.defaults.hl_groups)
      end
      cmd_executor.submit_command(cmd, M.defaults, 0, M.receive_buffer)
      return 2
    end,
  })
end

local refresh_cmd_preview = function()
  local backspace = api.nvim_replace_termcodes("<bs>", true, false, true)
  -- Hack to trigger command preview again after new buffer contents have been computed
  if api.nvim_get_mode().mode == "c" then
    api.nvim_feedkeys("a" .. backspace, "n", false)
  end
end

M.receive_buffer = function(bufnr, lines, highlights)
  received_lines = lines
  received_highlights = highlights
  -- refresh_cmd_preview()
end

local create_autocmds = function()
  local id = api.nvim_create_augroup("command_preview.nvim", { clear = true })
  -- We need to be able to tell when the command was cancelled so the buffer lines are refetched next time.
  api.nvim_create_autocmd({ "CmdLineLeave" }, {
    group = id,
    -- Schedule wrap to run after a potential command execution
    callback = vim.schedule_wrap(function()
      cmd_executor.teardown()
    end),
  })
end

M.setup = function()
  if vim.fn.has("nvim-0.8.0") ~= 1 then
    vim.notify(
      "[live-command] This plugin requires at least Neovim 0.8. Please upgrade to a more recent vers1ion of Neovim.",
      vim.log.levels.ERROR
    )
    return
  end
  create_preview_command()
  create_autocmds()
end

M.version = "2.0.0"

return M
