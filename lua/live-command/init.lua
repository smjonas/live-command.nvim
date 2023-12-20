local M = {}

---@type livecmd.Config
M.default_config = {
  command_name = "Preview",
  enable_highlighting = true,
  inline_highlighting = true,
  hl_groups = {
    insertion = "DiffAdd",
    deletion = "DiffDelete",
    change = "DiffChange",
  },
}

local cmd_executor
local api = vim.api

---@type livecmd.Config
local merged_config

---@type string[]?
local received_lines

---@type livecmd.Highlight[]?
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

local refresh_cmd_preview = function()
  local backspace = api.nvim_replace_termcodes("<bs>", true, false, true)
  -- Hack to trigger command preview again after new buffer contents have been computed
  if api.nvim_get_mode().mode == "c" then
    api.nvim_feedkeys("a" .. backspace, "n", false)
  end
end

local on_receive_buffer = function(bufnr, lines, highlights)
  received_lines = lines
  received_highlights = highlights
  refresh_cmd_preview()
end

local preview_callback = function(opts, preview_ns, preview_buf)
  local cmd = opts.args
  if received_lines then
    api.nvim_buf_set_lines(0, 0, -1, false, received_lines)
    received_lines = nil
  end
  if received_highlights then
    apply_highlights(0, preview_ns, received_highlights, merged_config.hl_groups)
    received_highlights = nil
  end
  cmd_executor.submit_command(cmd, merged_config, 0, on_receive_buffer)
  return 2
end

M._test_mode = false

local get_command_string = function(cmd_to_run, cmd_dict)
  vim.validate {
    cmd_to_run = { cmd_to_run, { "string", "function" } },
  }
  if type(cmd_to_run) == "string" then
    return cmd_to_run
  end
  return cmd_to_run(cmd_dict)
end

---@param cmd_name string
---@param cmd_to_run string|fun():string
M.create_preview_command = function(cmd_name, cmd_to_run)
  vim.validate {
    cmd_name = { cmd_name, "string" },
  }
  api.nvim_create_user_command(cmd_name, function(cmd_dict)
    vim.cmd(get_command_string(cmd_to_run, cmd_dict))
  end, {
    nargs = "*",
    preview = function(opts, preview_ns, preview_buf)
      local cmd_string = get_command_string(cmd_to_run, opts)
      return preview_callback(cmd_string, preview_ns, preview_buf)
    end,
  })
end

local create_autocmds = function()
  local id = api.nvim_create_augroup("command_preview.nvim", { clear = true })
  -- We need to be able to tell when the command was cancelled so the buffer lines are refetched next time.
  api.nvim_create_autocmd({ "CmdLineLeave" }, {
    group = id,
    -- Schedule wrap to run after a potential command execution
    callback = vim.schedule_wrap(function()
      cmd_executor.teardown(true)
    end),
  })
end

---@param user_config livecmd.Config?
M.setup = function(user_config)
  if vim.fn.has("nvim-0.8.0") ~= 1 then
    vim.notify(
      "[live-command] This plugin requires at least Neovim 0.8. Please upgrade to a more recent vers1ion of Neovim.",
      vim.log.levels.ERROR
    )
    return
  end
  cmd_executor = require("live-command.cmd_executor")
  merged_config = vim.tbl_deep_extend("force", M.default_config, user_config or {})
  require("live-command.config_validator").validate_config(merged_config)
  -- Creates a :Preview command that simply executes its arguments as a command
  M.create_preview_command(merged_config.command_name, function(cmd_dict)
    return cmd_dict.args
  end)
  create_autocmds()
end

M.version = "2.0.0"

return M
