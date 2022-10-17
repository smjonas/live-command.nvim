local M = {}

M.defaults = {
  enable_highlighting = true,
  inline_highlighting = true,
  hl_groups = {
    insertion = "DiffAdd",
    deletion = "DiffDelete",
    change = "DiffChange",
  },
}

local should_cache_lines = true
local cached_lines
local prev_lazyredraw

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

-- Inserts str_2 into str_1 at the given position.
local function string_insert(str_1, str_2, pos)
  return str_1:sub(1, pos - 1) .. str_2 .. str_1:sub(pos)
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

  for _, line_hunk in ipairs(line_diff) do
    local _, count_a, start_b, count_b = unpack(line_hunk)
    local hunk_kind = (count_a == 0 and "insertion") or (count_b == 0 and "deletion") or "change"

    if hunk_kind ~= "deletion" or undo_deletions then
      table.insert(highlights, {
        hunk = line_hunk,
        kind = hunk_kind,
        line = line,
        -- Add 1 because when count is zero, start_b / start_b is the position before the deletion
        column = (hunk_kind == "deletion") and start_b + 1 or start_b,
        length = (hunk_kind == "deletion") and count_a or count_b,
      })
    end
  end

  local defer
  local col_offset = 0
  for _, highlight in ipairs(highlights) do
    local start_a, count_a, start_b, _ = unpack(highlight.hunk)

    if highlight.kind == "deletion" and undo_deletions then
      local deleted_part = cached_lns[line]:sub(start_a, start_a + count_a - 1)
      -- Restore deleted characters
      updated_lines[line] = string_insert(updated_lines[line], deleted_part, col_offset + start_b + 1)
      defer = function()
        col_offset = col_offset + #deleted_part
      end
    end
    -- Observation: when changing "line" to "tes", there should not be an offset (-2)
    -- after changing "lin" to "t" (because we are not modifying the line)

    highlight.column = highlight.column + col_offset
    -- No longer needed
    highlight.hunk = nil

    if defer then
      defer()
      defer = nil
    end
  end
end

-- Expose function to tests
M._add_inline_highlights = add_inline_highlights

local function get_diff_highlights(cached_lns, updated_lines, line_range, opts)
  local highlights = {}
  -- Using the on_hunk callback and returning -1 to cancel causes an error so don't use that
  local hunks = vim.diff(table.concat(cached_lns, "\n"), table.concat(updated_lines, "\n"), {
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
          vim.inspect(vim.list_slice(cached_lns, start_line, end_line)),
          vim.inspect(vim.list_slice(updated_lines, start_line, end_line))
        )
      end)

      for line = start_line, end_line do
        -- Outside of visible area, skip current or all hunks
        if line > line_range[2] then
          return highlights
        end

        if line >= line_range[1] then
          if hunk_kind == "deletion" and opts.undo_deletions then
            -- Hunk was deleted: reinsert lines
            table.insert(updated_lines, line, cached_lns[line])
          end
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
            add_inline_highlights(line, cached_lns, updated_lines, opts.undo_deletions, highlights)
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

-- Expose functions to tests
M._preview_across_lines = get_diff_highlights

local function run_buf_cmd(buf, cmd)
  vim.api.nvim_buf_call(buf, function()
    log(function()
      return ("Previewing command: %s (current line = %d)"):format(cmd, vim.api.nvim_win_get_cursor(0)[1])
    end)
    vim.cmd(cmd)
  end)
end

-- Called when the user is still typing the command or the command arguments
local function command_preview(opts, preview_ns, preview_buf)
  -- Any errors that occur in the preview function are not directly shown to the user but stored in vim.v.errmsg.
  -- Related: https://github.com/neovim/neovim/issues/18910.
  vim.v.errmsg = ""
  logs = {}
  local args = opts.cmd_args
  local command = opts.command

  local bufnr = vim.api.nvim_get_current_buf()
  if should_cache_lines then
    prev_lazyredraw = vim.o.lazyredraw
    vim.o.lazyredraw = true
    cached_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    should_cache_lines = false
  end

  -- Ignore any errors that occur while running the command.
  -- This reduces noise when a plugin modifies vim.v.errmsg (whether accidentally or not).
  local prev_errmsg = vim.v.errmsg
  local visible_line_range = { vim.fn.line("w0"), vim.fn.line("w$") }

  if opts.line1 == opts.line2 then
    run_buf_cmd(bufnr, ("%s %s"):format(command.cmd, args))
  else
    run_buf_cmd(bufnr, ("%d,%d%s %s"):format(opts.line1, opts.line2, command.cmd, args))
  end

  vim.v.errmsg = prev_errmsg
  -- Adjust range to account for potentially inserted lines / scroll
  visible_line_range = {
    math.max(visible_line_range[1], vim.fn.line("w0")),
    math.max(visible_line_range[2], vim.fn.line("w$")),
  }

  local updated_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local set_lines = function(lines)
    -- TODO: is this worth optimizing?
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    if preview_buf then
      vim.api.nvim_buf_set_lines(preview_buf, 0, -1, false, lines)
    end
  end

  if not opts.line1 or not command.enable_highlighting then
    set_lines(updated_lines)
    -- This should not happen
    if not opts.line1 then
      log("No line1 range provided", "ERROR")
    end
    return 2
  end

  -- An empty buffer is represented as { "" }, change it to {}
  if not updated_lines[2] and updated_lines[1] == "" then
    updated_lines = {}
  end

  local highlights = get_diff_highlights(cached_lines, updated_lines, visible_line_range, {
    undo_deletions = command.hl_groups["deletion"] ~= false,
    inline_highlighting = command.inline_highlighting,
  })
  log(function()
    return "Highlights: " .. vim.inspect(highlights)
  end)

  set_lines(updated_lines)
  for _, hl in ipairs(highlights) do
    local hl_group = command.hl_groups[hl.kind]
    if hl_group ~= false then
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

local function restore_buffer_state()
  vim.o.lazyredraw = prev_lazyredraw
  should_cache_lines = true
  if vim.v.errmsg ~= "" then
    log(("An error occurred in the preview function:\n%s"):format(vim.inspect(vim.v.errmsg)), "ERROR")
  end
end

local function execute_command(command)
  log("Executing command: " .. command)
  vim.cmd(command)
  restore_buffer_state()
end

local create_user_commands = function(commands)
  for name, command in pairs(commands) do
    local args, range
    vim.api.nvim_create_user_command(name, function(opts)
      local range_string = range and range
        or (
          opts.range == 2 and ("%s,%s"):format(opts.line1, opts.line2)
          or opts.range == 1 and tostring(opts.line1)
          or ""
        )
      execute_command(("%s%s %s"):format(range_string, command.cmd, args))
    end, {
      nargs = "*",
      range = true,
      preview = function(opts, preview_ns, preview_buf)
        opts.command = command
        args = command.args
        if args then
          -- Update command args if provided
          args = type(args) == "function" and args(opts) or args
        else
          args = opts.args
        end
        opts.cmd_args = args
        range = command.range
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
  local possible_opts = { "enable_highlighting", "inline_highlighting", "hl_groups" }
  for _, command in pairs(config.commands) do
    for _, opt in ipairs(possible_opts) do
      if command[opt] == nil and defaults and defaults[opt] ~= nil then
        command[opt] = defaults[opt]
      else
        command[opt] = command[opt] or M.defaults[opt]
      end
    end
    command.hl_groups = vim.tbl_deep_extend("force", {}, M.defaults.hl_groups, command.hl_groups)

    vim.validate {
      cmd = { command.cmd, "string" },
      args = { command.args, { "string", "function" }, true },
      range = { command.range, { "string" }, true },
      ["command.enable_highlighting"] = { command.enable_highlighting, "boolean", true },
      ["command.inline_highlighting"] = { command.inline_highlighting, "boolean", true },
      ["command.hl_groups"] = { command.hl_groups, "table", true },
    }
  end
end

M.setup = function(user_config)
  if vim.fn.has("nvim-0.8.0") ~= 1 then
    vim.notify(
      "[live-command] This plugin requires at least Neovim 0.8. Please upgrade your Neovim version.",
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

  M.debug = user_config.debug

  vim.api.nvim_create_user_command("LiveCommandLog", function()
    local msg = ("live-command log\n================\n\n%s%s"):format(
      logs.ERROR and "[ERROR]\n" .. table.concat(logs.ERROR, "\n") .. (logs.TRACE and "\n" or "") or "",
      logs.TRACE and "[TRACE]\n" .. table.concat(logs.TRACE, "\n") or ""
    )
    vim.notify(msg)
  end, { nargs = 0 })
end

M.version = "1.2.1"

return M
