local M = {}

-- Strips the common prefix and suffix from the two strings
-- and returns the updated strings and start position.
M.strip_common = function(str_a, str_b)
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

M.strip_common_linewise = function(lines_a, lines_b)
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

-- Given a string a that has been transformed into string b using a set of editing
-- operations, returns b without any deletion operations applied to it.
-- This will adjust positions of edits after a deletion is encountered.
M.undo_deletions = function(a, b, edits)
  local function string_insert(str_1, str_2, pos)
    return str_1:sub(1, pos - 1) .. str_2 .. str_1:sub(pos)
  end
  local updated_b = b
  local offset = 0

  for _, edit in ipairs(edits) do
    if edit.type == "deletion" then
      local deleted_chars = a:sub(edit.start_pos, edit.end_pos)
      updated_b = string_insert(updated_b, deleted_chars, edit.b_start_pos + offset)
      -- Increase positions to account for updated b
      local length = edit.end_pos - edit.start_pos + 1
      edit.start_pos = edit.b_start_pos + offset
      edit.end_pos = edit.start_pos + length - 1
      -- Not needed anymore
      edit.b_start_pos = nil
      offset = offset + length
    else
      -- Shift all other edits
      edit.start_pos = edit.start_pos + offset
      edit.end_pos = edit.end_pos + offset
    end
  end
  return updated_b
end

-- Returns the 0-indexed line and column numbers of the idx-th character of s in s.
-- A new line begins when a newline character is encountered.
M.idx_to_text_pos = function(s, idx)
  local line = 1
  local cur_idx = 0
  for i = 1, idx - 1 do
    if s:sub(i, i) == "\n" then
      line = line + 1
      -- Line begins at the current character
      cur_idx = i
    end
  end
  return line, idx - cur_idx
end

-- Given strings a and b and a table of edit operations that turn
-- a into b (after deletions have been undone in b), returns a list
-- of highlights that correspond to these edit operations.
M.get_multiline_highlights = function(b, edits, hl_groups)
  local hls = {}
  for _, edit in ipairs(edits) do
    if hl_groups[edit.type] ~= nil then
      local start_line, start_col = M.idx_to_text_pos(b, edit.start_pos)
      -- Do not create a highlight for a single newline character at the end of a line,
      -- instead jump to the next line
      if b:sub(edit.start_pos, edit.start_pos) == "\n" then
        start_line = start_line + 1
        start_col = 1
      end
      if not hls[start_line] then
        hls[start_line] = {}
      end
      local end_line, end_col = M.idx_to_text_pos(b, edit.end_pos)

      local hl_group = hl_groups[edit.type]
      if start_line == end_line then
        table.insert(hls[start_line], { start_col = start_col, end_col = end_col, hl_group = hl_group })
      else
        -- Highlight to the end of the first line
        table.insert(hls[start_line], { start_col = start_col, end_col = -1, hl_group = hl_group })
        -- Highlight all lines inbetween
        for line = start_line + 1, end_line - 1 do
          if not hls[line] then
            hls[line] = {}
          end
          table.insert(hls[line], { start_col = 1, end_col = -1, hl_group = hl_group })
        end
        if not hls[end_line] then
          hls[end_line] = {}
        end
        -- Highlight from the start of the last line
        table.insert(hls[end_line], { start_col = 1, end_col = end_col, hl_group = hl_group })
      end
    end
  end
  return hls
end

return M
