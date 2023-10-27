local M = {}

---@class livecmd.Highlight
---@field line number
---@field column number
---@field length number
---@field hlgroup string|false

local logger = require("live-command.logger")

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

local function add_inline_highlights(line, old_lines, new_lines, undo_deletions, highlights)
  local line_a = splice(old_lines[line])
  local line_b = splice(new_lines[line])
  local line_diff = vim.diff(line_a, line_b, { result_type = "indices" })
  logger.trace(function()
    return ("Changed lines (line %d):\nOriginal: '%s' (len=%d)\nUpdated:  '%s' (len=%d)\n\nInline hunks: %s"):format(
      line,
      old_lines[line],
      #old_lines[line],
      new_lines[line],
      #new_lines[line],
      vim.inspect(line_diff)
    )
  end)

  local defer
  local col_offset = 0
  for _, line_hunk in ipairs(line_diff) do
    local start_a, count_a, start_b, count_b = unpack(line_hunk)
    local hunk_kind = (count_a == 0 and "insertion") or (count_b == 0 and "deletion") or "change"

    if hunk_kind ~= "deletion" or undo_deletions then
      local highlight = {
        hunk = line_hunk,
        kind = hunk_kind,
        line = line,
        -- Add 1 because when count is zero, start_b / start_b is the position before the deletion
        column = (hunk_kind == "deletion") and start_b + 1 or start_b,
        length = (hunk_kind == "deletion") and count_a or count_b,
      }

      if highlight.kind == "deletion" and undo_deletions then
        local deleted_part = old_lines[line]:sub(start_a, start_a + count_a - 1)
        -- Restore deleted characters
        new_lines[line] = string_insert(new_lines[line], deleted_part, col_offset + start_b + 1)
        defer = function()
          col_offset = col_offset + #deleted_part
        end
      end
      -- Observation: when changing "line" to "tes", there should not be an offset (-2)
      -- after changing "lin" to "t" (because we are not modifying the line)
      highlight.column = highlight.column + col_offset
      highlight.hunk = nil
      table.insert(highlights, highlight)

      if defer then
        defer()
        defer = nil
      end
    end
  end
end

--- @param old_lines string[]
--- @param new_lines string[]
--- @param line_range {start:number, end:number}
--- @param inline_highlighting boolean
--- @param undo_deletions boolean
--- @return livecmd.Highlight[], string[]
M.get_highlights = function(diff, old_lines, new_lines, line_range, inline_highlighting, undo_deletions)
  local highlights = {}
  for i, hunk in ipairs(diff) do
    logger.trace(function()
      return ("Hunk %d/%d: %s"):format(i, #diff, vim.inspect(hunk))
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

      logger.trace(function()
        return ("Lines %d-%d:\nOriginal: %s\nUpdated: %s"):format(
          start_line,
          end_line,
          vim.inspect(vim.list_slice(old_lines, start_line, end_line)),
          vim.inspect(vim.list_slice(new_lines, start_line, end_line))
        )
      end)

      for line = start_line, end_line do
        -- Outside of visible area, skip current or all hunks
        if line > line_range[2] then
          return highlights, new_lines
        end

        if line >= line_range[1] then
          if hunk_kind == "deletion" and undo_deletions then
            -- Hunk was deleted: reinsert lines
            table.insert(new_lines, line, old_lines[line])
          end
          if new_lines[line] == "" then
            -- Make empty lines visible
            new_lines[line] = " "
          end
          table.insert(highlights, { kind = hunk_kind, line = line, column = 1, length = -1 })
        end
      end
    else
      -- Change edit
      for line = start_b, start_b + count_b - 1 do
        -- Outside of visible area, skip current or all hunks
        if line > line_range[2] then
          return highlights, new_lines
        end

        if line >= line_range[1] then
          if inline_highlighting then
            -- Get diff for each line in the hunk
            add_inline_highlights(line, old_lines, new_lines, undo_deletions, highlights)
          else
            -- Use a single highlight for the whole line
            table.insert(highlights, { kind = "change", line = line, column = 1, length = -1 })
          end
        end
      end
    end
  end
  return highlights, new_lines
end

return M
