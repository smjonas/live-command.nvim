local M = {
  utils = nil,
  provider = nil,
}

M.defaults = {
  enable_highlighting = true,
  hl_groups = {
    insertion = "DiffAdd",
    replacement = "DiffChanged",
    deletion = "DiffDelete",
  },
}

local scratch_buf, cached_lines
local prev_cursorline, prev_lazyredraw

local function preview_across_lines(cached_lns, updated_lines, hl_groups, set_lines, apply_highlight_cb)
  local keep_deletions = hl_groups["deletion"] == nil
  if keep_deletions then
    set_lines(updated_lines)
  end

  local a, b, skipped_lines_count = M.utils.strip_common_linewise(cached_lns, updated_lines)
  a = table.concat(a, "\n")
  b = table.concat(b, "\n")
  local edits = M.provider.get_edits(a, b)
  b = M.utils.undo_deletions(a, b, edits)

  if not keep_deletions then
    -- Undo deletion operations in all lines after the skipped ones
    for line_nr, line in ipairs(vim.split(b, "\n")) do
      updated_lines[skipped_lines_count + line_nr] = line
    end
    set_lines(updated_lines)
  end

  for line_nr, hls_per_line in pairs(M.utils.get_multiline_highlights(b, edits, hl_groups)) do
    for _, hl in ipairs(hls_per_line) do
      hl.line = line_nr + skipped_lines_count
      apply_highlight_cb(hl)
    end
  end
end

local function preview_per_line(cached_lns, updated_lns, hl_groups, set_lines, set_line, apply_highlight_cb)
  local keep_deletions = hl_groups["deletion"] == nil
  if keep_deletions then
    set_lines(updated_lns)
  end

  for line_nr = 1, #updated_lns do
    local a, b, skipped_columns_start, skipped_columns_end =
      M.utils.strip_common(cached_lns[line_nr], updated_lns[line_nr])
    local edits = M.provider.get_edits(a, b)

    if not keep_deletions then
      local line = cached_lns[line_nr]
      -- Add back the deleted substrings
      local suffix = skipped_columns_end > 0 and line:sub(#line - skipped_columns_end + 1) or ""
      set_line(line_nr, line:sub(1, skipped_columns_start) .. M.utils.undo_deletions(a, b, edits) .. suffix)
    end

    for _, edit in ipairs(edits) do
      if hl_groups[edit.type] ~= nil then
        local start_col = edit.b_start_pos or edit.start_pos
        local end_col = edit.b_start_pos and edit.b_start_pos + (edit.end_pos - edit.start_pos) or edit.end_pos
        start_col = start_col + skipped_columns_start
        end_col = end_col + skipped_columns_start

        local hl = {
          line = line_nr,
          start_col = start_col,
          end_col = end_col,
          hl_group = hl_groups[edit.type],
        }
        apply_highlight_cb(hl)
      end
    end
  end
end

-- Expose functions to tests
M._preview_per_line = preview_per_line
M._preview_across_lines = preview_across_lines

local function apply_highlight(hl, line, bufnr, preview_ns)
  vim.api.nvim_buf_add_highlight(bufnr, preview_ns, hl.hl_group, line, hl.start_col - 1, hl.end_col)
end

-- Called when the user is still typing the command or the command arguments
local function command_preview(opts, preview_ns, preview_buf)
  vim.v.errmsg = ""
  local args = opts.command.args or opts.args
  if args:find("^%s*$") then
    return
  end

  local bufnr = vim.api.nvim_get_current_buf()
  local range = { opts.line1 - 1, opts.line2 }

  if not scratch_buf then
    prev_lazyredraw = vim.o.lazyredraw
    -- TODO: fix cursorline restoration
    prev_cursorline = vim.wo.cursorline
    vim.o.lazyredraw = true
    vim.wo.cursorline = false
    scratch_buf = vim.api.nvim_create_buf(true, true)
    cached_lines = vim.api.nvim_buf_get_lines(bufnr, range[1], range[2], false)
  end
  -- Clear the scratch buffer
  vim.api.nvim_buf_set_lines(scratch_buf, 0, -1, false, cached_lines)

  -- Ignore any errors that occur while running the command.
  -- This reduces noise when a plugin modifies vim.v.errmsg (whether accidentally or not).
  local prev_errmsg = vim.v.errmsg

  local command = opts.command
  -- Run the normal mode command and get the updated buffer contents
  vim.api.nvim_cmd({
    cmd = "bufdo",
    -- Use 1,$ as a range to apply the command to the entire scratch buffer
    args = { ("1,$%s %s"):format(command.cmd, args) },
    range = { scratch_buf },
  }, {})
  vim.v.errmsg = prev_errmsg

  local updated_lines = vim.api.nvim_buf_get_lines(scratch_buf, 0, -1, false)
  vim.api.nvim_set_current_buf(bufnr)

  local set_lines = function(lines)
    vim.api.nvim_buf_set_lines(bufnr, range[1], range[2], false, lines)
    if preview_buf then
      vim.api.nvim_buf_set_lines(preview_buf, range[1], range[2], false, lines)
    end
  end

  if not range[1] or not command.enable_highlighting then
    set_lines(updated_lines)
    if not range[1] then
      -- This should not happen
      vim.v.errmsg = "No line1 range provided"
    end
    return 2
  end

  -- New lines were inserted or lines were deleted.
  -- In this case, we need to compute the distance across all lines.
  if #updated_lines ~= #cached_lines then
    preview_across_lines(cached_lines, updated_lines, command.hl_groups, set_lines, function(hl)
      hl.line = hl.line + range[1]
      apply_highlight(hl, hl.line - 1, bufnr, preview_ns)
    end)
  else
    -- In the other case, it is more efficient to compute the distance per line
    preview_per_line(cached_lines, updated_lines, command.hl_groups, set_lines, function(line_nr, line)
      vim.api.nvim_buf_set_lines(bufnr, line_nr - 1 + range[1], line_nr + range[1], false, { line })
    end, function(hl)
      hl.line = hl.line + range[1]
      apply_highlight(hl, hl.line - 1, bufnr, preview_ns)
    end)
  end
  return 2
end

local function restore_buffer_state()
  if scratch_buf then
    vim.api.nvim_buf_delete(scratch_buf, {})
    vim.wo.cursorline = prev_cursorline
    vim.o.lazyredraw = prev_lazyredraw
    scratch_buf = nil
  end
end

local function execute_command(command)
  -- Any errors that occur in the preview function are not directly shown to the user but stored in vim.v.errmsg.
  -- Related: https://github.com/neovim/neovim/issues/18910.
  if vim.v.errmsg ~= "" then
    vim.notify(
      "[command-preview] An error occurred in the preview function. Please report this error here: https://github.com/smjonas/command-preview.nvim/issues:\n"
        .. vim.v.errmsg,
      vim.log.levels.ERROR
    )
  end
  vim.cmd(command)
  restore_buffer_state()
end

local create_user_commands = function(commands)
  for name, command in pairs(commands) do
    vim.api.nvim_create_user_command(name, function(opts)
      local range = opts.range == 2 and ("%s,%s"):format(opts.line1, opts.line2)
        or opts.range == 1 and tostring(opts.line1)
        or ""
      execute_command(("%s%s %s"):format(range, command.cmd, command.args or opts.args))
    end, {
      nargs = "*",
      range = true,
      preview = function(opts, preview_ns, preview_buf)
        opts.command = command
        return command_preview(opts, preview_ns, preview_buf)
      end,
    })
  end
end

local validate_config = function(config)
  local defaults = config.defaults
  vim.validate {
    defaults = { defaults, "table", true },
    commands = { config.commands, "table" },
  }
  local possible_opts = { "enable_highlighting", "hl_groups" }
  for _, command in pairs(config.commands) do
    for _, opt in ipairs(possible_opts) do
      if command[opt] == nil and defaults and defaults[opt] ~= nil then
        command[opt] = defaults[opt]
      else
        command[opt] = M.defaults[opt]
      end
    end
    vim.validate {
      cmd = { command.cmd, "string" },
      args = { command.args, "string", true },
      ["command.enable_highlighting"] = { command.enable_highlighting, "boolean", true },
      ["command.hl_groups"] = { command.hl_groups, "table", true },
    }
  end
end

M.setup = function(user_config)
  if vim.fn.has("nvim-0.8.0") ~= 1 then
    vim.notify(
      "[command-preview] This plugin requires Neovim nightly (0.8). Please upgrade your Neovim version.",
      vim.log.levels.ERROR
    )
    return
  end

  local config = vim.tbl_deep_extend("force", M.defaults, user_config or {})
  validate_config(config)
  create_user_commands(config.commands)

  local id = vim.api.nvim_create_augroup("command_preview.nvim", { clear = true })
  -- We need to be able to tell when the command was cancelled so the buffer lines are refetched next time.
  vim.api.nvim_create_autocmd({ "CmdLineLeave" }, {
    group = id,
    -- Schedule wrap to run after a potential command execution
    callback = vim.schedule_wrap(function()
      restore_buffer_state()
    end),
  })
  M.utils = require("live_command.edit_utils")
  M.provider = require("live_command.levenshtein_edits_provider")
end

return M
