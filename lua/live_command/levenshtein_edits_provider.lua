local M = {}

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

-- If at least half of the characters in a word have been changed,
-- multiple edits will be combined into a single substitution edit.
-- This reduces the amount of highlights which may be confusing without this function.
local function merge_edits(edits, a)
  if #edits == 1 then
    -- Nothing to merge
    return edits
  end

  local in_word
  local cur_word = 0
  local char_pos_to_word = {}
  local word_start_pos = {}
  -- Map each non-whitespace character position to a word.
  -- Also store the starting position for each word.
  for i = 1, #a do
    if a:sub(i, i):find("%S") then
      if not in_word then
        cur_word = cur_word + 1
        in_word = true
        word_start_pos[cur_word] = i
      end
      char_pos_to_word[i] = cur_word
    else
      in_word = false
    end
  end

  local edits_per_word = {}
  local changed_chars_count_per_word = {}
  -- Get a list of edits (their indices, to be precise) that changed each word
  -- and the number of characters modified in a word
  for i, edit in ipairs(edits) do
    local start_word, end_word = char_pos_to_word[edit.start_pos], char_pos_to_word[edit.end_pos]
    print(i, start_word, end_word, edit.start_pos, edit.end_pos)
    if not edits_per_word[start_word] then
      edits_per_word[start_word] = {}
    end
    table.insert(edits_per_word[start_word], i)
    if start_word ~= end_word then
      if not edits_per_word[end_word] then
        edits_per_word[end_word] = {}
      end
      table.insert(edits_per_word[end_word], i)
      for j = edit.start_word, edit.end_word do
        local word = char_pos_to_word[j]
        if word then
          changed_chars_count_per_word[word] = changed_chars_count_per_word[word] + 1
        end
      end
    else
      changed_chars_count_per_word[start_word] = (changed_chars_count_per_word[start_word] or 0)
        + (edit.end_pos - edit.start_pos + 1)
    end
  end

  local words = vim.split(a, "%s+", { trimempty = true })
  for i = 1, #words do
    -- At least n / 2 characters must have changed for a merge
    local word_len = #words[i]
    if edits_per_word[i] and changed_chars_count_per_word[i] >= word_len / 2 then
      -- Replace the edits with a single substitution edit
      edits[edits_per_word[i][1]] =
        { type = "substitution", start_pos = word_start_pos[i], end_pos = word_start_pos[i] + word_len }
      for j = 2, #edits_per_word[i] do
        table.remove(edits, edits_per_word[i][j])
      end
    end
  end
  return edits
end

-- Expose function to tests
M._merge_edits = merge_edits

-- Returns a list of insertion and replacement operations
-- that turn the first string into the second one.
M.get_edits = function(str_a, str_b)
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

  local function do_deletion()
    cur_edit = update_edits("deletion", cur_edit, row, edits)
    cur_edit.b_start_pos = col + 1
    row = row - 1
    col = col + 1
  end

  local function try_insertion()
    local can_insert = matrix[row][col - 1] <= matrix[row - 1][col] and matrix[row][col - 1] <= matrix[row - 1][col - 1]
    if can_insert then
      cur_edit = update_edits("insertion", cur_edit, col, edits)
    end
    return can_insert
  end

  local function do_replacement()
    cur_edit = update_edits("replacement", cur_edit, col, edits)
    row = row - 1
  end

  while row > 0 and col > 0 do
    if str_a:sub(row, row) ~= str_b:sub(col, col) then
      local can_delete = matrix[row - 1][col] <= matrix[row][col - 1]
        and matrix[row - 1][col] <= matrix[row - 1][col - 1]

      -- There was no previous edit
      if not cur_edit.type then
        if can_delete then
          do_deletion()
        elseif not try_insertion() then
          do_replacement()
        end
      else
        -- Prioritize edits of the same type as the previous one
        if can_delete and cur_edit.type == "deletion" then
          do_deletion()
        else
          -- Check if moving left in the matrix (=> insertion) is the shortest path
          if cur_edit.type == "insertion" or str_a:sub(row, row) == str_b:sub(col - 1, col - 1) then
            if not try_insertion() then
              if can_delete then
                do_deletion()
              else
                do_replacement()
              end
            end
          else
            do_replacement()
          end
        end
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

return M
