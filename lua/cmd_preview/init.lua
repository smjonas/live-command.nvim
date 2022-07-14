local M = {}

local config
M.default_config = {
  cmd_name = "Norm",
  hl_group = "Substitute",
}

local scratch_buf, cached_lines

-- Strips the common prefix and suffix from the two strings
-- and returns the updated strings and start position.
local function strip_common(str_a, str_b)
  local len_a, len_b = #str_a, #str_b
  local skipped_lines_count = 0
  local last_newline_pos = 0

  local new_start
  -- Strip common prefix
  for i = 1, math.max(len_a, len_b) do
    local char_a = str_a:sub(i, i)
    if char_a == "\n" then
      skipped_lines_count = skipped_lines_count + 1
      -- Reset offset
      last_newline_pos = i
    end
    if char_a == str_b:sub(i, i) then
      new_start = i
    else
      break
    end
  end

  if new_start then
    str_a = str_a:sub(new_start + 1)
    str_b = str_b:sub(new_start + 1)
    len_a = len_a - new_start
    len_b = len_b - new_start
  end

  -- Strip common suffix
  local end_offset
  for i = 0, math.min(len_a, len_b) do
    if str_a:sub(len_a - i, len_a - i) == str_b:sub(len_b - i, len_b - i) then
      end_offset = i + 1
    else
      break
    end
  end

  if end_offset then
    str_a = str_a:sub(1, len_a - end_offset)
    str_b = str_b:sub(1, len_b - end_offset)
  end
  return str_a, str_b, new_start and (new_start - last_newline_pos) or 0, skipped_lines_count
end

-- Returns a list of insertion and replacement operations
-- that turn the first string into the second one.
local function get_levenshtein_edits(str_a, str_b)
  local len_a, len_b = #str_a, #str_b
  if len_a == 0 then
    return { { type = "insertion", start_pos = 1, end_pos = len_b } }
  elseif len_b == 0 then
    return {}
  elseif str_a == str_b then
    return {}
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
    local edit_type
    if str_a:sub(row, row) ~= str_b:sub(col, col) then
      if matrix[row - 1][col] <= matrix[row][col - 1] and matrix[row - 1][col] <= matrix[row - 1][col - 1] then
        edit_type = "deletion"
        if cur_edit.type == edit_type and cur_edit.start_pos == row + 1 then
          -- Extend the edit
          cur_edit.start_pos = row
        else
          cur_edit = { type = edit_type, start_pos = row, end_pos = row }
          table.insert(edits, 1, cur_edit)
        end
        row = row - 1
        -- TODO: refactor
        col = col + 1
      else
        if matrix[row][col - 1] <= matrix[row - 1][col] and matrix[row][col - 1] <= matrix[row - 1][col - 1] then
          edit_type = "insertion"
        else
          edit_type = "replacement"
          row = row - 1
        end
        if cur_edit.type == edit_type and cur_edit.start_pos == col + 1 then
          -- Extend the edit
          cur_edit.start_pos = col
        else
          cur_edit = { type = edit_type, start_pos = col, end_pos = col }
          table.insert(edits, 1, cur_edit)
        end
      end
    else
      row = row - 1
    end
    col = col - 1
  end

  return edits, matrix
end

-- Returns the 0-indexed line and column numbers of the idx-th character of s in s.
-- A new line begins when a newline character is encountered.
local idx_to_text_pos = function(s, idx)
  local line = 1
  local cur_idx = 0
  for i = 1, idx do
    if s:sub(i, i) == "\n" then
      line = line + 1
      cur_idx = i
    end
  end
  return line - 1, idx - cur_idx
end

local get_multiline_highlights = function(new_text, edits)
  local hl_positions = {}
  for _, edit in ipairs(edits) do
    if edit.type ~= "deletion" then
      local start_line, start_col = idx_to_text_pos(new_text, edit.start_pos)
      local end_line, end_col = idx_to_text_pos(new_text, edit.end_pos)
      local highlight
      if start_line == end_line then
        highlight = { line = start_line, start_col = start_col - 1, end_col = end_col }
      else
        -- Highlight to the end of the first line
        highlight = { line = start_line, start_col = start_col, end_col = -1 }
        -- Highlight all lines inbetween
        for line = start_line + 1, end_line - 1 do
          highlight = { line = line, start_col = 0, end_col = -1 }
        end
        -- Highlight from the start of the last line
        highlight = { line = end_line, start_col = 0, end_col = start_col }
      end
      hl_positions[#hl_positions + 1] = highlight
    end
  end
  return hl_positions
end

local apply_highlight = function(hl, line_offset, col_offset, bufnr, preview_ns)
  -- for _, hl in ipairs(edits_to_hl_positions(new_text, edits)) do
  -- vim.v.errmsg = "TEST" .. new_start .. " pos " .. hl.start_col + new_start .. hl.end_col + new_start
  vim.api.nvim_buf_add_highlight(
    bufnr,
    preview_ns,
    "Substitute",
    -- TODO: can't the line number change too?
    hl.line + line_offset,
    hl.start_col + col_offset,
    hl.end_col + col_offset
  )
end

-- Expose functions to tests
M._strip_common = strip_common
M._get_levenshtein_edits = get_levenshtein_edits
M._idx_to_text_pos = idx_to_text_pos
M._get_multiline_highlights = get_multiline_highlights

-- Called when the user is still typing the command or the command arguments
local function command_preview(opts, preview_ns, preview_buf)
  -- TODO: don't ignore preview_buf
  vim.v.errmsg = ""
  if opts.args:find("^%s*$") then
    return
  end

  local bufnr = vim.api.nvim_get_current_buf()
  local range = { opts.line1 - 1, opts.line2 }
  if not range[1] then
    vim.v.errmsg = "No line1 range provided"
    return
  end

  if not scratch_buf then
    scratch_buf = vim.api.nvim_create_buf(true, true)
    cached_lines = vim.api.nvim_buf_get_lines(bufnr, range[1], range[2], false)
  end
  -- Clear the scratch buffer
  vim.api.nvim_buf_set_lines(scratch_buf, 0, -1, false, cached_lines)

  local cmd = {
    cmd = "bufdo",
    -- Use 1,$ as a range to apply the command to the entire scratch buffer
    args = { ("1,$%s %s"):format(opts.cmd, opts.args) },
    range = { scratch_buf },
  }
  -- Run the normal mode command and get the updated buffer contents
  vim.api.nvim_cmd(cmd, {})
  local updated_lines = vim.api.nvim_buf_get_lines(scratch_buf, 0, -1, false) or {}

  -- Update the original buffer
  vim.api.nvim_set_current_buf(bufnr)
  vim.api.nvim_buf_set_lines(bufnr, range[1], range[2], false, updated_lines)

  local function set_error(msg)
    vim.v.errmsg = msg
  end

  -- New lines were inserted or lines were deleted.
  -- In this case, we need to compute the distance across all lines.
  if #updated_lines ~= #cached_lines then
    local a = table.concat(cached_lines, "\n")
    local b = table.concat(updated_lines, "\n")
    local new_start, skipped_lines_count
    a, b, new_start, skipped_lines_count = strip_common(a, b)

    local edits = get_levenshtein_edits(a, b)

    local xs = {}
    for _, hl in ipairs(get_multiline_highlights(b, edits)) do
      -- set_error(
      --   vim.v.errmsg
      --     .. "\n\n"
      --     .. hl.line
      --     .. ", r="
      --     .. range[1]
      --     .. ", lines="
      --     .. skipped_lines_count
      --     .. hl.start_col
      --     .. ", "
      --     .. hl.end_col
      -- )
      local x =
        { line = hl.line, range = range[1], skipped_lines_count = skipped_lines_count, col = hl.start_col + new_start }
      table.insert(xs, x)
      apply_highlight(hl, range[1] + skipped_lines_count, new_start, bufnr, preview_ns)
    end
    set_error(vim.inspect(xs))
  else
    -- In the other case, it is more efficient to compute the distance per line
    for i = 1, #updated_lines do
      local a, b, new_start, _ = strip_common(cached_lines[i], updated_lines[i])
      -- set_error(a .. "|" .. b)
      local edits = get_levenshtein_edits(a, b)
      for _, edit in ipairs(edits) do
        local hl = { line = i - 1, start_col = edit.start_pos - 1, end_col = edit.end_pos }
        -- set_error(hl.line .. ", " .. hl.start_col .. ", " .. hl.end_col)
        apply_highlight(hl, range[1], new_start, bufnr, preview_ns)
      end
    end
  end

  -- local a = table.concat(cached_lines, "\n")
  -- local b = table.concat(updated_lines, "\n")
  -- local new_start
  -- a, b, new_start = strip_common(a, b)
  -- local edits = get_levenshtein_edits(a, b)
  -- -- new_start = 0

  -- for _, hl in ipairs(get_multiline_highlights(b, edits)) do
  --   vim.v.errmsg = "TEST" .. new_start .. " pos " .. hl.start_col + new_start .. hl.end_col + new_start
  --   vim.api.nvim_buf_add_highlight(
  --     bufnr,
  --     preview_ns,
  --     "Substitute",
  --     -- TODO: should do line-wise prefix / suffix computation
  --     -- TODO: can't the line number change too?
  --     hl.line + range[1],
  --     hl.start_col + new_start,
  --     hl.end_col + new_start
  --   )
  -- end
  return 2
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
  if scratch_buf then
    vim.cmd(command)
    vim.api.nvim_buf_delete(scratch_buf, {})
    scratch_buf = nil
  end
end

local create_user_commands = function(commands)
  for name, command in pairs(commands) do
    vim.api.nvim_create_user_command(name, function(opts)
      local range = opts.range == 2 and ("%s,%s"):format(opts.line1, opts.line2)
        or opts.range == 1 and string(opts.line1)
        or ""
      execute_command(("%s%s %s"):format(range, command.cmd, opts.args))
    end, {
      nargs = "*",
      range = true,
      preview = function(opts, preview_ns, preview_buf)
        opts.cmd = command.cmd
        return command_preview(opts, preview_ns, preview_buf)
      end,
    })
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

  config = vim.tbl_deep_extend("force", M.default_config, user_config or {})
  create_user_commands(config.commands)

  local id = vim.api.nvim_create_augroup("command_preview.nvim", { clear = true })
  -- We need to be able to tell when the command was cancelled so the buffer lines are refetched next time.
  vim.api.nvim_create_autocmd({ "CmdLineLeave" }, {
    group = id,
    -- Schedule wrap to run after a potential command execution
    callback = vim.schedule_wrap(function()
      if scratch_buf then
        vim.api.nvim_buf_delete(scratch_buf, {})
        scratch_buf = nil
      end
    end),
  })
end

return M
