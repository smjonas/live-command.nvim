local M = {}

M.defaults = {
  enable_highlighting = true,
  hl_groups = {
    insertion = "DiffAdd",
    replacement = "DiffChanged",
    deletion = "DiffDelete",
  },
  max_highlights = 9999,
  max_line_highlights = { count = 20, disable_highlighting = true },
}

local scratch_buf, cached_lines, exit_early
local prev_cursorline, prev_lazyredraw

-- Strips the common prefix and suffix from the two strings
-- and returns the updated strings and start position.
local function strip_common(str_a, str_b)
  local len_a, len_b = #str_a, #str_b
  if str_a == str_b then
    return "", "", len_a, 0
  end

  local skipped_cols_start
  -- Strip common prefix
  for i = 1, math.min(len_a, len_b) do
    if str_a:sub(i, i) == str_b:sub(i, i) then
      skipped_cols_start = i
    else
      break
    end
  end

  if skipped_cols_start then
    str_a = str_a:sub(skipped_cols_start + 1)
    str_b = str_b:sub(skipped_cols_start + 1)
    len_a = len_a - skipped_cols_start
    len_b = len_b - skipped_cols_start
  end

  -- Strip common suffix
  local skipped_cols_end
  for i = 0, math.min(len_a, len_b) do
    if str_a:sub(len_a - i, len_a - i) == str_b:sub(len_b - i, len_b - i) then
      skipped_cols_end = i + 1
    else
      break
    end
  end

  if skipped_cols_end then
    str_a = str_a:sub(1, len_a - skipped_cols_end)
    str_b = str_b:sub(1, len_b - skipped_cols_end)
  end
  return str_a, str_b, skipped_cols_start or 0, skipped_cols_end or 0
end

local function strip_common_linewise(lines_a, lines_b)
  local len_a, len_b = #lines_a, #lines_b
  -- Remove common lines at beginning / end
  local start_lines_count = 0
  for i = 1, math.min(len_a, len_b) do
    if lines_a[i] == lines_b[i] then
      start_lines_count = i
    else
      break
    end
  end

  local end_lines_count = 0
  for i = 0, math.min(len_a - start_lines_count, len_b - start_lines_count) - 1 do
    if lines_a[len_a - i] == lines_b[len_b - i] then
      end_lines_count = i + 1
    else
      break
    end
  end

  local new_a, new_b = {}, {}
  for i = start_lines_count + 1, len_a - end_lines_count do
    table.insert(new_a, lines_a[i])
  end
  for i = start_lines_count + 1, len_b - end_lines_count do
    table.insert(new_b, lines_b[i])
  end
  return new_a, new_b, start_lines_count
end

local function update_edits(edit_type, cur_edit, cur_start_pos, edits)
  if cur_edit.type == edit_type and cur_edit.start_pos == cur_start_pos + 1 then
    -- Extend the edit
    cur_edit.start_pos = cur_start_pos
  else
    -- Create a new edit
    cur_edit = { type = edit_type, start_pos = cur_start_pos, end_pos = cur_start_pos }
    table.insert(edits, 1, cur_edit)
  end
  return cur_edit
end

-- Returns a list of insertion and replacement operations
-- that turn the first string into the second one.
local function get_levenshtein_edits(str_a, str_b)
  if str_a == str_b then
    return {}
  end

  local len_a, len_b = #str_a, #str_b
  if len_a == 0 then
    return { { type = "insertion", start_pos = 1, end_pos = len_b } }
  elseif len_b == 0 then
    return { { type = "deletion", start_pos = 1, end_pos = len_a, b_start_pos = 1 } }
  end

  local matrix = {}
  -- Initialize the base matrix values
  for row = 0, len_a do
    matrix[row] = {}
    matrix[row][0] = row
  end
  for col = 0, len_b do
    matrix[0][col] = col
  end

  local cost = 1
  local min = math.min
  -- Actual Levenshtein algorithm
  for row = 1, len_a do
    for col = 1, len_b do
      cost = str_a:sub(row, row) == str_b:sub(col, col) and 0 or 1
      matrix[row][col] = min(matrix[row - 1][col] + 1, matrix[row][col - 1] + 1, matrix[row - 1][col - 1] + cost)
    end
  end

  -- Start at the bottom right of the matrix
  local row, col = len_a, len_b
  local edits = {}
  local cur_edit = {}

  while row > 0 and col > 0 do
    if str_a:sub(row, row) ~= str_b:sub(col, col) then
      if matrix[row - 1][col] <= matrix[row][col - 1] and matrix[row - 1][col] <= matrix[row - 1][col - 1] then
        -- TODO: continue fine-tuning edits
        cur_edit = update_edits("deletion", cur_edit, row, edits)
        cur_edit.b_start_pos = col + 1
        row = row - 1
        col = col + 1
      elseif matrix[row][col - 1] <= matrix[row - 1][col] and matrix[row][col - 1] <= matrix[row - 1][col - 1] then
        cur_edit = update_edits("insertion", cur_edit, col, edits)
      else
        cur_edit = update_edits("replacement", cur_edit, col, edits)
        row = row - 1
      end
    else
      row = row - 1
    end
    col = col - 1
  end

  if col > 0 then
    table.insert(edits, 1, { type = "insertion", start_pos = 1, end_pos = col })
  elseif row > 0 then
    table.insert(edits, 1, { type = "deletion", start_pos = 1, end_pos = row, b_start_pos = col + 1 })
  end
  return edits, matrix
end

-- Given a string a that has been transformed into string b using a set of editing
-- operations, returns b without any deletion operations applied to it.
local undo_deletions = function(a, b, edits)
  local function string_insert(str_1, str_2, pos)
    return str_1:sub(1, pos - 1) .. str_2 .. str_1:sub(pos)
  end
  local updated_b = b
  local offset = 0

  for _, edit in ipairs(edits) do
    if edit.type == "deletion" then
      local deleted_chars = a:sub(edit.start_pos, edit.end_pos)
      updated_b = string_insert(updated_b, deleted_chars, edit.b_start_pos + offset)
      offset = offset + (edit.end_pos - edit.start_pos) + 1
    end
  end
  return updated_b
end

-- Returns the 0-indexed line and column numbers of the idx-th character of s in s.
-- A new line begins when a newline character is encountered.
local idx_to_text_pos = function(s, idx)
  local line = 0
  local cur_idx = 1
  for i = 2, idx do
    if s:sub(i - 1, i - 1) == "\n" then
      line = line + 1
      -- Line begins at the current character
      cur_idx = i
    end
  end
  return line, idx - cur_idx
end

local get_multiline_highlights = function(a, b, edits)
  -- TODO: only use 1-based indices
  b = undo_deletions(a, b, edits)
  local hls = {}
  for _, edit in ipairs(edits) do
    local start_line, start_col = idx_to_text_pos(b, edit.start_pos)
    -- Do not create a highlight for a single newline character at the end of a line,
    -- instead jump to the next line
    if b:sub(edit.start_pos, edit.start_pos) == "\n" then
      start_line = start_line + 1
      start_col = 0
    end
    if not hls[start_line] then
      hls[start_line] = {}
    end
    local end_line, end_col = idx_to_text_pos(b, edit.end_pos)

    if start_line == end_line then
      table.insert(hls[start_line], { start_col = start_col, end_col = end_col + 1 })
    else
      -- Highlight to the end of the first line
      table.insert(hls[start_line], { start_col = start_col, end_col = -1 })
      -- Highlight all lines inbetween
      for line = start_line + 1, end_line - 1 do
        if not hls[line] then
          hls[line] = {}
        end
        table.insert(hls[line], { start_col = 0, end_col = -1 })
      end
      if not hls[end_line] then
        hls[end_line] = {}
      end
      -- Highlight from the start of the last line
      table.insert(hls[end_line], { start_col = 0, end_col = end_col + 1 })
    end
  end
  return hls
end

local function preview_across_lines(cached_lines, updated_lines, set_lines, apply_highlight_cb)
  local a, b, skipped_lines_count = strip_common_linewise(cached_lines, updated_lines)
  a = table.concat(a, "\n")
  b = table.concat(b, "\n")
  local edits = get_levenshtein_edits(a, b)

  -- vim.v.errmsg = "Assert failed" .. (#vim.split(undo_deletions(a, b, edits), "\n") == #updated_lines - skipped_lines_count) and "true" or "")
  -- Undo deletion operations in all lines after the skipped ones
  for line_nr, line in ipairs(vim.split(undo_deletions(a, b, edits), "\n")) do
    updated_lines[skipped_lines_count + line_nr] = line
  end
  set_lines(updated_lines)

  for line_nr, hls_per_line in pairs(get_multiline_highlights(a, b, edits)) do
    for _, hl in ipairs(hls_per_line) do
      hl.line = line_nr
      apply_highlight_cb(hl, skipped_lines_count)
    end
  end
end

local function preview_per_line(cached_lines, updated_lines, hl_groups, set_line, set_lines, apply_highlight_cb)
  local keep_deletions = hl_groups["deletion"] == nil
  if keep_deletions then
    set_lines(updated_lines)
  end

  for line_nr = 1, #updated_lines do
    local a, b, skipped_columns_start, skipped_columns_end = strip_common(cached_lines[line_nr], updated_lines[line_nr])
    local edits = get_levenshtein_edits(a, b)

    if not keep_deletions then
      local line = cached_lines[line_nr]
      -- Add back the deleted substrings
      local suffix = skipped_columns_end > 0 and line:sub(#line - skipped_columns_end + 1) or ""
      set_line(line_nr, line:sub(1, skipped_columns_start) .. undo_deletions(a, b, edits) .. suffix)
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
M._strip_common = strip_common
M._strip_common_linewise = strip_common_linewise
M._get_levenshtein_edits = get_levenshtein_edits
M._undo_deletions = undo_deletions
M._idx_to_text_pos = idx_to_text_pos
M._get_multiline_highlights = get_multiline_highlights
M._preview_across_lines = preview_across_lines
M._preview_per_line = preview_per_line

local apply_highlight = function(hl, line, bufnr, preview_ns)
  vim.api.nvim_buf_add_highlight(
    bufnr,
    preview_ns,
    hl.hl_group,
    -- TODO: can't the line number change too?
    line,
    hl.start_col - 1,
    hl.end_col
    -- TODO: document that everything is 1-based
  )
end

-- Called when the user is still typing the command or the command arguments
local function command_preview(opts, preview_ns, preview_buf)
  -- TODO: handle preview_buf
  vim.v.errmsg = ""
  local args = opts.command.args or opts.args
  if args:find("^%s*$") then
    return
  end

  local bufnr = vim.api.nvim_get_current_buf()
  local range = { opts.line1 - 1, opts.line2 }
  if not range[1] then
    vim.v.errmsg = "No line1 range provided"
    return
  end

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

  -- Ignore any errors that occur while running the command
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

  local updated_lines = vim.api.nvim_buf_get_lines(scratch_buf, 0, -1, false) or {}
  vim.api.nvim_set_current_buf(bufnr)

  vim.v.errmsg = command.enable_highlighting and "true" or "false"
  if not command.enable_highlighting then
    vim.api.nvim_buf_set_lines(bufnr, range[1], range[2], false, updated_lines)
    return 2
  end

  local set_lines = function(lines)
    vim.v.errmsg = vim.inspect(lines)
    -- Update the original buffer
    -- vim.api.nvim_buf_set_lines(bufnr, range[1], range[2], false, lines)
  end

  -- New lines were inserted or lines were deleted.
  -- In this case, we need to compute the distance across all lines.
  if #updated_lines ~= #cached_lines then
    preview_across_lines(cached_lines, updated_lines, set_lines, function(hl, skipped_lines_count)
      hl.hl_group = command.hl_groups[hl.type]
      apply_highlight(hl, hl.line, range[1] + skipped_lines_count, 0, bufnr, preview_ns)
    end)
  else
    -- In the other case, it is more efficient to compute the distance per line
    preview_per_line(cached_lines, updated_lines, command.hl_groups, function(line_nr, line)
      vim.api.nvim_buf_set_lines(bufnr, line_nr - 1 + range[1], line_nr + range[1], false, { line })
    end, function(lines)
      vim.api.nvim_buf_set_lines(bufnr, range[1], range[2], false, lines)
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
      vim.lsp.log_levels.ERROR
    )
  end
  if not exit_early then
    vim.cmd(command)
    exit_early = false
  end
  restore_buffer_state()
end

local create_user_commands = function(commands)
  for name, command in pairs(commands) do
    vim.api.nvim_create_user_command(name, function(opts)
      -- TODO: correctly handle range
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
  local possible_opts = { "enable_highlighting", "hl_groups", "max_highlights", "max_line_highlights" }
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
      ["command.max_highlights"] = { command.max_highlights, "number", true },
      ["command.max_line_highlights"] = { command.max_line_highlights, { "table", "function" }, true },
    }
  end
end

M.setup = function(user_config)
  if vim.fn.has("nvim-0.8.0") ~= 1 then
    vim.notify(
      "[command-preview] This plugin requires Neovim nightly (0.8). Please upgrade your Neovim version.",
      vim.lsp.log_levels.ERROR
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
end

return M
