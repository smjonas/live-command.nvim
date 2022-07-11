local M = {}

M.default_config = {
  cmd_name = "Norm",
  hl_group = "Substitute",
}

local scratch_buf = nil
local cached_lines = nil
local err = nil

local function set_error(msg, level)
  err = { msg = msg, level = level }
end

-- Returns a list of insertion and replacement operations
-- that turn the first string into the second one.
local function levenshtein_edits(str_a, str_b)
  local len_a = #str_a
  local len_b = #str_b

  -- quick cut-offs to save time
  if len_a == 0 then
    return len_b
  elseif len_b == 0 then
    return len_a
  elseif str_a == str_b then
    return 0
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
      matrix[row][col] =
        min(matrix[row - 1][col] + 1, matrix[row][col - 1] + 1, matrix[row - 1][col - 1] + cost)
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
      if
        matrix[row][col - 1] <= matrix[row - 1][col]
        and matrix[row][col - 1] <= matrix[row - 1][col - 1]
      then
          -- Prioritize insertions and replacements
        edit_type = "insertion"
      elseif
        matrix[row - 1][col - 1] <= matrix[row][col]
        and matrix[row - 1][col - 1] <= matrix[row - 1][col]
      then
        edit_type = "replacement"
        row = row - 1
      else
        print("Deletion", str_a:sub(row, row), str_b:sub(col, col))
      end

      if cur_edit.type == edit_type then
        -- Extend the start index of the edit
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

  print(vim.inspect(matrix))
  print(vim.inspect(edits))
  return matrix
end

-- Called when the user is still typing the command or the command arguments
local function incremental_norm_preview(opts, preview_ns, preview_buf)
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
    cached_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  else
    -- Clear the scratch buffer
    vim.api.nvim_buf_set_lines(scratch_buf, 0, -1, false, cached_lines)
  end

  local cmd = {
    cmd = "bufdo",
    -- args = { ("%d,%dnorm %s"):format(opts.line1, opts.line2, opts.args) },
    args = { ("%d,%dnorm"):format(opts.line1, opts.line2), opts.args },
    range = { scratch_buf },
  }
  -- Run the normal mode command and get the updated buffer contents
  vim.api.nvim_cmd(cmd, {})
  local updated_lines = vim.api.nvim_buf_get_lines(scratch_buf, 0, -1, false) or {}
  local a = table.concat(cached_lines, "\n")
  local b = table.concat(updated_lines, "\n")

  -- Update the original buffer
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, updated_lines)
  vim.api.nvim_set_current_buf(bufnr)
  set_error(vim.diff(a, b, { algorithm = "minimal" }))
  return 2
end

-- Called when the command is executed (user pressed enter)
local function incremental_norm_execute(new_name)
  local cmd = {
    cmd = "normal",
    args = { "akek" },
  }
  -- set_error(vim.inspect(cmd))
  cmd.count = nil
  cmd.reg = nil
  -- vim.api.nvim_cmd(cmd, {})
  -- vim.api.nvim_cmd(cmd, {})
  -- Schedule wrapping here avoids an (uncommon) issue where buffer contents were
  -- changed by the highlight function after the rename request had already been executed.
  -- (Probably because synchronous LSP requests are not queued like Nvim API calls?)
  vim.schedule(function()
    -- Any errors that occur in the preview function are not directly shown to the user but are stored in vim.v.errmsg.
    -- For more info, see https://github.com/neovim/neovim/issues/18910.
    if vim.v.errmsg ~= "" then
      vim.notify(
        "[inc-rename] An error occurred in the preview function. Please report this error here: https://github.com/smjonas/inc-rename.nvim/issues:\n"
          .. vim.v.errmsg,
        vim.lsp.log_levels.ERROR
      )
    elseif err then
      vim.notify(err.msg, err.level)
    else
      -- perform_lsp_rename(new_name)
    end
  end)
end

local create_user_command = function(cmd_name)
  vim.api.nvim_create_user_command(cmd_name, function(opts)
    incremental_norm_execute(opts.args)
    -- TODO: range = true?
  end, {
    nargs = "+",
    range = true,
    addr = "lines",
    preview = incremental_norm_preview,
  })
end

M.setup = function(user_config)
  if vim.fn.has("nvim-0.8.0") ~= 1 then
    vim.notify(
      "[inc-norm] This plugin requires Neovim nightly (0.8). Please upgrade your Neovim version.",
      vim.lsp.log_levels.ERROR
    )
    return
  end

  M.config = vim.tbl_deep_extend("force", M.default_config, user_config or {})
  create_user_command(M.config.cmd_name)
end

return M
