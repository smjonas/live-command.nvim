local M = {}

local should_cache_lines = true
local cached_lines, updated_lines

local function get_highlights(line_range)
  local highlights = {}
  -- Using the on_hunk callback and returning -1 to cancel causes an error so don't use that
  local hunks = vim.diff(table.concat(cached_lines, "\n"), table.concat(updated_lines, "\n"), {
    result_type = "indices",
  })
  log(("Visible line range: %d-%d"):format(line_range[1], line_range[2]))

  for i, hunk in ipairs(hunks) do
    log(function()
      return ("Hunk %d/%d: %s"):format(i, #hunks, vim.inspect(hunk))
    end)

    local start_a, count_a, start_b, count_b = hunk[1], hunk[2], hunk[3], hunk[4]
    local hunk_kind = (count_a < count_b and "insertion") or (count_a > count_b and "deletion")
    if hunk_kind then
      local start_line, end_line
      if hunk_kind == "insertion" then
        start_line = start_b + count_a
        end_line = start_a + (count_b - count_a)
      else
        start_line = start_a + count_b
        end_line = start_line + (count_a - count_b) - 1
      end

      log(function()
        return ("Lines %d-%d:\nOriginal: %s\nUpdated: %s"):format(
          start_line,
          end_line,
          vim.inspect(vim.list_slice(cached_lines, start_line, end_line)),
          vim.inspect(vim.list_slice(updated_lines, start_line, end_line))
        )
      end)

      for line = start_line, end_line do
        -- Outside of visible area, skip current or all hunks
        if line > line_range[2] then
          return highlights
        end

        if line >= line_range[1] then
          if updated_lines[line] == "" then
            -- Make empty lines visible
            updated_lines[line] = " "
          end
          table.insert(highlights, { kind = hunk_kind, line = line, column = 1, length = -1 })
        end
      end
    else
      -- Change edit
      for line = start_b, start_b + count_b - 1 do
        -- Outside of visible area, skip current or all hunks
        if line > line_range[2] then
          return highlights
        end

        if line >= line_range[1] then
          if opts.inline_highlighting then
            -- Get diff for each line in the hunk
            add_inline_highlights(line, cached_lines, updated_lines, opts.undo_deletions, highlights)
          else
            -- Use a single highlight for the whole line
            table.insert(highlights, { kind = "change", line = line, column = 1, length = -1 })
          end
        end
      end
    end
  end
  return highlights
end

local function command_preview(command, opts, preview_ns, preview_buf)
  local bufnr = vim.api.nvim_get_current_buf()
  if should_cache_lines then
    cached_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    should_cache_lines = false
  end
  local visible_line_range = { vim.fn.line("w0"), vim.fn.line("w$") }
  command(opts)
  updated_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  -- Adjust range to account for potentially inserted lines
  visible_line_range = {
    math.max(visible_line_range[1], vim.fn.line("w0")),
    math.max(visible_line_range[2], vim.fn.line("w$")),
  }

  -- An empty buffer is represented as { "" }, change it to {}
  if not updated_lines[2] and updated_lines[1] == "" then
    updated_lines = {}
  end

  local highlights = get_highlights(visible_line_range)
  log(function()
    return "Highlights: " .. vim.inspect(highlights)
  end)

  for _, hl in ipairs(highlights) do
    local hl_group = command.hl_groups[hl.kind]
    if hl_group ~= false then
      -- Convert 1-based to 0-based
      vim.api.nvim_buf_add_highlight(
        bufnr,
        preview_ns,
        hl_group,
        hl.line - 1,
        hl.column - 1,
        hl.length == -1 and -1 or hl.column + hl.length - 1
      )
    end
  end
  return 2
end

local command = function(opts)
  vim.cmd("norm Ikek")
end

vim.api.nvim_create_user_command("Test", command, {
  preview = function(opts, preview_ns, preview_buf)
    return command_preview(command, opts, preview_ns, preview_buf)
  end,
  nargs = 0,
})

-- If preview is a boolean, use command_preview function and pass callback to preview function

local logs = {}
local function log(msg, level)
  level = level or "TRACE"
  if M.debug or level ~= "TRACE" then
    msg = type(msg) == "function" and msg() or msg
    logs[level] = logs[level] or {}
    for _, line in ipairs(vim.split(msg .. "\n", "\n")) do
      table.insert(logs[level], line)
    end
  end
end

-- Inserts a newline character after each character of s and returns the table of characters.
local function splice(s)
  local chars = {}
  for i = 1, #s do
    chars[2 * i - 1] = s:sub(i, i)
    chars[2 * i] = "\n"
  end
  return table.concat(chars)
end

local unpack = table.unpack or unpack

local function add_inline_highlights(line, cached_lns, updated_lines, undo_deletions, highlights)
  local line_a = splice(cached_lns[line])
  local line_b = splice(updated_lines[line])
  local line_diff = vim.diff(line_a, line_b, { result_type = "indices" })
  log(function()
    return ("Changed lines (line %d):\nOriginal: '%s' (len=%d)\nUpdated:  '%s' (len=%d)\n\nInline hunks: %s"):format(
      line,
      cached_lns[line],
      #cached_lns[line],
      updated_lines[line],
      #updated_lines[line],
      vim.inspect(line_diff)
    )
  end)
  local cached_line = cached_lns[line]
  local updated_line = {}

  local col_offset = 0
  local last_hunk = { end_a = 0 }

  for i, line_hunk in ipairs(line_diff) do
    local start_a, count_a, start_b, count_b = unpack(line_hunk)
    local end_a, end_b = start_a + count_a - 1, start_b + count_b - 1
    local hunk_kind = (count_a == 0 and "insertion") or (count_b == 0 and "deletion") or "change"

    local col_delta = 0
    if hunk_kind == "insertion" then
      table.insert(updated_line, updated_lines[line]:sub(start_b, end_b))
    else
      if undo_deletions and hunk_kind == "deletion" then
        -- Restore deleted characters
        table.insert(updated_line, cached_lns[line]:sub(start_a, end_a))
        -- col_delta = count_a
      elseif hunk_kind == "change" then
        -- Restore characters removed by change
        table.insert(updated_line, updated_lines[line]:sub(start_b, end_b))
        col_delta = -(count_a - count_b)
      end
    end

    if hunk_kind ~= "deletion" or undo_deletions then
      local highlight = {
        kind = hunk_kind,
        line = line,
        column = col_offset + ((hunk_kind == "deletion") and start_a or start_b),
        length = (hunk_kind == "deletion") and count_a or count_b,
      }
      if start_a > last_hunk.end_a + 1 then
        -- There is a gap between the last hunk and the current one, add the text inbetween
        local unchanged_part = cached_line:sub(last_hunk.end_a + 1, start_a - (hunk_kind ~= "insertion" and 1 or 0))
        table.insert(updated_line, #updated_line, unchanged_part)
      end

      table.insert(highlights, highlight)
      last_hunk = { end_a = (count_a == 0) and start_a or end_a }
      col_offset = col_offset + col_delta
    end

    if i == #line_diff and last_hunk.end_a < #cached_line then
      -- Add unchanged characters at the end of the line
      table.insert(updated_line, cached_line:sub(last_hunk.end_a + 1))
    end
  end
  updated_lines[line] = table.concat(updated_line)
end

-- Expose function to tests
M._add_inline_highlights = add_inline_highlights

-- TODO: restore_buffer_state
local id = vim.api.nvim_create_augroup("command_preview.nvim", { clear = true })
-- We need to be able to tell when the command was cancelled so the buffer lines are refetched next time.
vim.api.nvim_create_autocmd({ "CmdLineLeave" }, {
  group = id,
  -- Schedule wrap to run after a potential command execution
  callback = vim.schedule_wrap(function()
    restore_buffer_state()
  end),
})

M.version = "1.2.0"

return M
