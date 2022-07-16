local M = {}

M.defaults = {
  hl_group = "IncSearch",
  max_highlights = 9999,
  max_line_highlights = { count = 20, disable_highlighting = true },
}

local scratch_buf, cached_lines,  exit_early
local prev_cursorline, prev_lazyredraw

-- Strips the common prefix and suffix from the two strings
-- and returns the updated strings and start position.
local function strip_common(str_a, str_b)
  local len_a, len_b = #str_a, #str_b
  local skipped_lines_count = 0
  local last_newline_pos = 0

  local new_start
  -- Strip common prefix
  -- TODO: change to MIN
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

-- Returns a list of insertion and replacement operations
-- that turn the first string into the second one.
local function get_levenshtein_edits(str_a, str_b, max_edits)
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
        -- Deletion, don't need to store this edit
        row = row - 1
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
          if #edits == max_edits.count - 1 then
            if max_edits.disable_highlighting then
              return {}
            else
              -- Return a single insertion edit when a maximum number of edits is reached
              return { { type = "insertion", start_pos = 1, end_pos = len_b } }
            end
          end
          cur_edit = { type = edit_type, start_pos = col, end_pos = col }
          table.insert(edits, 1, cur_edit)
        end
      end
    else
      row = row - 1
    end
    col = col - 1
  end

  if col > 0 then
    table.insert(edits, 1, { type = "insertion", start_pos = 1, end_pos = col })
  end
  return edits, matrix
end

-- Returns the 0-indexed line and column numbers of the idx-th character of s in s.
-- A new line begins when a newline character is encountered.
local idx_to_text_pos = function(s, idx)
  local line = 0
  local cur_idx = 1
  for i = 1, idx do
    if s:sub(i, i) == "\n" then
      line = line + 1
      -- Line begins at the next character
      cur_idx = i + 1
    end
  end
  return line, idx - cur_idx
end

local get_multiline_highlights = function(new_text, edits, max_line_highlights)
  local hl_positions = {}
  local skip_line = {}

  for _, edit in ipairs(edits) do
    local start_line, start_col = idx_to_text_pos(new_text, edit.start_pos)
    if not skip_line[start_line] then
      if not hl_positions[start_line] then
        hl_positions[start_line] = {}
      end
      if #hl_positions[start_line] >= max_line_highlights.count - 1 then
        if max_line_highlights.disable_highlighting then
          hl_positions[start_line] = {}
        else
          hl_positions[start_line] = { { start_col = 0, end_col = -1 } }
        end
        skip_line[start_line] = true
      else
        local end_line, end_col = idx_to_text_pos(new_text, edit.end_pos)
        if start_line == end_line then
          table.insert(hl_positions[start_line], { start_col = start_col, end_col = end_col + 1 })
        else
          -- Highlight to the end of the first line
          table.insert(hl_positions[start_line], { start_col = start_col, end_col = -1 })
          -- Highlight all lines inbetween
          for line = start_line + 1, end_line - 1 do
            if not hl_positions[line] then
              hl_positions[line] = {}
            end
            table.insert(hl_positions[line], { start_col = 0, end_col = -1 })
          end
          if not hl_positions[end_line] then
            hl_positions[end_line] = {}
          end
          -- Highlight from the start of the last line
          table.insert(hl_positions[end_line], { start_col = 0, end_col = end_col + 1 })
        end
      end
    end
  end
  return hl_positions
end

local apply_highlight = function(hl, line, line_offset, col_offset, bufnr, preview_ns)
  vim.api.nvim_buf_add_highlight(
    bufnr,
    preview_ns,
    hl.hl_group,
    -- TODO: can't the line number change too?
    line + line_offset,
    hl.start_col + col_offset,
    hl.end_col + col_offset
  )
end

-- Expose functions to tests
M._strip_common = strip_common
M._strip_common_linewise = strip_common_linewise
M._get_levenshtein_edits = get_levenshtein_edits
M._idx_to_text_pos = idx_to_text_pos
M._get_multiline_highlights = get_multiline_highlights

local function get_max_line_highlights(max_line_highlights, b)
  local result = type(max_line_highlights) == "table" and max_line_highlights or max_line_highlights(b)
  -- Do not run the command when vim.validate fails
  exit_early = true
  vim.validate {
    ["max_line_highlights.count"] = { result.count, "number" },
    ["max_line_highlights.disable_highlighting"] = { result.disable_highlighting, "boolean" },
  }
  exit_early = false
  return result
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
    prev_cursorline = vim.wo.cursorline
    vim.o.lazyredraw = true
    vim.wo.cursorline = false
    scratch_buf = vim.api.nvim_create_buf(true, true)
    cached_lines = vim.api.nvim_buf_get_lines(bufnr, range[1], range[2], false)
  end
  -- Clear the scratch buffer
  vim.api.nvim_buf_set_lines(scratch_buf, 0, -1, false, cached_lines)

  local command = opts.command
  -- Run the normal mode command and get the updated buffer contents
  vim.api.nvim_cmd({
    cmd = "bufdo",
    -- Use 1,$ as a range to apply the command to the entire scratch buffer
    args = { ("1,$%s %s"):format(command.cmd, args) },
    range = { scratch_buf },
  }, {})

  local updated_lines = vim.api.nvim_buf_get_lines(scratch_buf, 0, -1, false) or {}

  -- Update the original buffer
  vim.api.nvim_set_current_buf(bufnr)
  vim.api.nvim_buf_set_lines(bufnr, range[1], range[2], false, updated_lines)

  -- New lines were inserted or lines were deleted.
  -- In this case, we need to compute the distance across all lines.
  if #updated_lines ~= #cached_lines then
    local a, b, skipped_lines_count = strip_common_linewise(cached_lines, updated_lines)
    a = table.concat(cached_lines, "\n")
    b = table.concat(updated_lines, "\n")
    local edits = get_levenshtein_edits(a, b, { count = -1 })
    for line_nr, hls_per_line in
      pairs(get_multiline_highlights(b, edits, { count = command.max_highlights, disable_highlighting = true }))
    do
      for _, hl in ipairs(hls_per_line) do
        hl.hl_group = command.hl_group
        apply_highlight(hl, line_nr, range[1] + skipped_lines_count, 0, bufnr, preview_ns)
      end
    end
  else
    local total_highlights_count = 0
    -- In the other case, it is more efficient to compute the distance per line
    for i = 1, #updated_lines do
      if total_highlights_count >= command.max_highlights then
        break
      end
      local a, b, new_start, _ = strip_common(cached_lines[i], updated_lines[i])
      local max_line_highlights = get_max_line_highlights(command.max_line_highlights, b)
      max_line_highlights.count = math.min(command.max_highlights - total_highlights_count, max_line_highlights.count)
      local edits = get_levenshtein_edits(a, b, max_line_highlights)
      for _, edit in ipairs(edits) do
        local hl = { line = i - 1, start_col = edit.start_pos - 1, end_col = edit.end_pos, hl_group = command.hl_group }
        apply_highlight(hl, i - 1, range[1], new_start, bufnr, preview_ns)
      end
      total_highlights_count = total_highlights_count + #edits
    end
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
      -- TODO: correctly handle command
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
  if defaults then
    for opt, _ in ipairs(defaults) do
      vim.validate {
        ["defaults.hl_group"] = { opt, "string", true },
        ["defaults.max_highlights"] = { opt, "number", true },
        ["defaults.max_line_highlights"] = { opt, { "table", "function" }, true },
      }
    end
  end
  local possible_opts = { "hl_group", "max_highlights", "max_line_highlights" }
  for _, command in pairs(config.commands) do
    for _, opt in ipairs(possible_opts) do
      command[opt] = command[opt] or (defaults and defaults[opt]) or M.defaults[opt]
    end
    vim.validate {
      cmd = { command.cmd, "string" },
      args = { command.args, "string", true },
      ["command.hl_group"] = { command.hl_group, "string", true },
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
