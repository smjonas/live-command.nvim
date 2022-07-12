local M = {}

local config
M.default_config = {
  cmd_name = "Norm",
  hl_group = "Substitute",
}

local scratch_buf, cached_lines, err

local function set_error(msg, level)
  err = { msg = msg, level = level }
end

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
    print(row, col)
    local edit_type
    if str_a:sub(row, row) ~= str_b:sub(col, col) then
      -- TODO: check for deletion first
      if matrix[row][col - 1] <= matrix[row - 1][col] and matrix[row][col - 1] <= matrix[row - 1][col - 1] then
        edit_type = "insertion"
      elseif matrix[row - 1][col - 1] <= matrix[row][col] and matrix[row - 1][col - 1] <= matrix[row - 1][col] then
        edit_type = "replacement"
        row = row - 1
      else
        print("Deletion", str_a:sub(row, row), str_b:sub(col, col))
      end

      if cur_edit.type == edit_type and cur_edit.start_idx == col + 1 then
        -- Extend the edit
        cur_edit.start_idx = col
      else
        cur_edit = { type = edit_type, start_idx = col, end_idx = col }
        table.insert(edits, 1, cur_edit)
      end
    else
      row = row - 1
    end
    col = col - 1
  end

  -- print(vim.inspect(matrix))
  -- print(vim.inspect(edits))
  return edits
end

-- Called when the user is still typing the command or the command arguments
local function command_preview(opts, preview_ns, preview_buf)
  vim.v.errmsg = ""
  -- set_error("args:" .. opts.args .. " range start:" .. opts.line1 .. " range end:" .. opts.line2)
  -- set_error(("%d,%dnorm %s"):format(opts.line1, opts.line2, opts.args))
  -- local cmd = ("%d,%dnorm %s"):format(opts.line1, opts.line2, opts.args)
  if opts.args:find("^%s*$") then
    return
  end

  local bufnr = vim.api.nvim_get_current_buf()
  if not scratch_buf then
    scratch_buf = vim.api.nvim_create_buf(true, true)
    cached_lines = vim.api.nvim_buf_get_lines(bufnr, opts.line1 - 1, opts.line2, false)
  else
    -- Clear the scratch buffer
    vim.api.nvim_buf_set_lines(scratch_buf, 0, -1, false, cached_lines)
  end

  local range = opts.range == 2 and ("%s,%s"):format(opts.line1, opts.line2)
    or opts.range == 1 and string(opts.line1)
    or ""

  local cmd = {
    cmd = "bufdo",
    args = { ("%s%s %s"):format(range, opts.cmd, opts.args) },
    range = { scratch_buf },
  }
  -- Run the normal mode command and get the updated buffer contents
  vim.api.nvim_cmd(cmd, {})
  local updated_lines = vim.api.nvim_buf_get_lines(scratch_buf, opts.line1 - 1, opts.line2, false) or {}

  -- Return the 0-indexed line numbers
  local string_idx_to_pos = function(s, idx)
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

  local a = table.concat(cached_lines, "\n")
  local b = table.concat(updated_lines, "\n")
  local edits = get_levenshtein_edits(a, b)
  set_error(vim.inspect(edits))

  -- Update the original buffer
  vim.api.nvim_set_current_buf(bufnr)
  vim.api.nvim_buf_set_lines(bufnr, opts.line1 - 1, opts.line2, false, updated_lines)

  for _, edit in ipairs(edits) do
    local start_line, start_col = string_idx_to_pos(b, edit.start_idx)
    local end_line, end_col = string_idx_to_pos(b, edit.end_idx)
    if start_line ~= end_line then
      for line = start_line, end_line do
        if line == start_line then
          -- Highlight to the end of the line
          vim.api.nvim_buf_add_highlight(bufnr, preview_ns, "Substitute", line, start_col - 1, -1)
        elseif line == end_line then
          -- Highlight from the start of the line
          vim.api.nvim_buf_add_highlight(bufnr, preview_ns, "Substitute", line, 0, start_col)
        else
          -- Highlight the whole line
          vim.api.nvim_buf_add_highlight(bufnr, preview_ns, "Substitute", line, 0, -1)
        end
      end
    else
      vim.api.nvim_buf_add_highlight(bufnr, preview_ns, "Substitute", start_line, start_col - 1, end_col)
    end
  end
  return 2
end

local function execute_command(command)
  -- vim.schedule(function()
  -- Any errors that occur in the preview function are not directly shown to the user but stored in vim.v.errmsg.
  -- For more info, see https://github.com/neovim/neovim/issues/18910.
  if vim.v.errmsg ~= "" then
    vim.notify(
      "[command-preview] An error occurred in the preview function. Please report this error here: https://github.com/smjonas/command-preview.nvim/issues:\n"
        .. vim.v.errmsg,
      vim.lsp.log_levels.ERROR
    )
  elseif err then
    vim.notify(err.msg, err.level)
  else
    print(command)
    vim.cmd(command)
    vim.api.nvim_buf_delete(scratch_buf, {})
    scratch_buf = nil
  end
  -- end)
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
end

return M
