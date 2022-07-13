local M = {}

local config
M.default_config = {
  cmd_name = "Norm",
  hl_group = "Substitute",
}

local scratch_buf, cached_lines

-- Returns a list of insertion and replacement operations
-- that turn the first string into the second one.
local function get_levenshtein_edits(str_a, str_b)
  local len_a = #str_a
  local len_b = #str_b

  -- quick cut-offs to save time
  if len_a == 0 then
    return {}
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

local edits_to_hl_positions = function(updated_lines, edits)
  local hl_positions = {}
  for _, edit in ipairs(edits) do
    if edit.type ~= "deletion" then
      local start_line, start_col = idx_to_text_pos(updated_lines, edit.start_pos)
      local end_line, end_col = idx_to_text_pos(updated_lines, edit.end_pos)
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

-- Expose functions to tests
M._get_levenshtein_edits = get_levenshtein_edits
M._idx_to_text_pos = idx_to_text_pos
M._edits_to_hl_positions = edits_to_hl_positions

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

  local a = table.concat(cached_lines, "\n")
  local b = table.concat(updated_lines, "\n")
  local edits = get_levenshtein_edits(a, b)

  for _, hl in ipairs(edits_to_hl_positions(b, edits)) do
    vim.api.nvim_buf_add_highlight(bufnr, preview_ns, "Substitute", hl.line + range[1], hl.start_col, hl.end_col)
  end
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
