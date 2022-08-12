local M = {}

-- Removes all gaps in the array (https://stackoverflow.com/a/53038524/10365305)
local function compact(arr, gaps)
  local j = 1
  local n = #arr

  for i = 1, n do
    if gaps[i] then
      arr[i] = nil
    else
      -- Move i's kept value to j's position, if it's not already there.
      if i ~= j then
        arr[j] = arr[i]
        arr[i] = nil
      end
      j = j + 1 -- Increment position of where we'll place the next kept value.
    end
  end
  return arr
end

-- If at least half of the characters in a word have been changed,
-- multiple edits will be combined into a single replacement edit.
-- This reduces the amount of highlights which may be confusing without this function.
-- Requires deletions to be already undone!
M.merge_edits = function(edits, b)
  -- TODO: refactor to not return anything
  if #edits == 1 then
    -- Nothing to merge
    return edits
  end

  local in_word
  local cur_word = 0
  -- Map each non-whitespace character position in b to a word.
  -- Also store the starting position for each word.
  local char_pos_to_word = {}
  local word_start_pos = {}
  for i = 1, #b do
    if b:sub(i, i):find("%S") then
      if not in_word then
        cur_word = cur_word + 1
        in_word = true
        word_start_pos[cur_word] = i
      end
      char_pos_to_word[i] = cur_word
      char_pos_to_word.last_pos = i
    else
      in_word = false
    end
  end

  local edits_per_word = {}
  local changed_chars_count_per_word = {}
  -- Get a list of edits (their indices, to be precise) that changed each word
  -- and the number of characters modified in a word
  for i, edit in ipairs(edits) do
    local start_pos, end_pos = edit.b_start, edit.b_start + edit.len - 1
    -- Move start_pos to the right until the next word (if there is one) and end_pos to the left
    while start_pos <= char_pos_to_word.last_pos and start_pos < end_pos do
      if char_pos_to_word[start_pos] and char_pos_to_word[end_pos] then
        break
      end
      if not char_pos_to_word[start_pos] then
        start_pos = start_pos + 1
      end
      if not char_pos_to_word[end_pos] then
        end_pos = end_pos - 1
      end
    end

    local start_word = char_pos_to_word[start_pos]
    if char_pos_to_word[start_pos] then
      local end_word = char_pos_to_word[end_pos]
      if not edits_per_word[start_word] then
        edits_per_word[start_word] = {}
      end
      table.insert(edits_per_word[start_word], i)
      if start_word ~= end_word then
        if not edits_per_word[end_word] then
          edits_per_word[end_word] = {}
        end
        table.insert(edits_per_word[end_word], i)
        vim.pretty_print(edit)
        for j = start_pos, end_pos do
          local word = char_pos_to_word[j]
          if word then
            changed_chars_count_per_word[word] = (changed_chars_count_per_word[word] or 0) + 1
          end
        end
      else
        changed_chars_count_per_word[start_word] = (changed_chars_count_per_word[start_word] or 0) + edit.len
      end
    end
  end

  -- local get_changed_chars_count = function(edit)
  --   if edit.type == "insertion" or edit.type == "deletion" then
  --     vim.pretty_print("added" .. edit.len .. "for ", edit)
  --     return edit.len
  --   end
  --   return -edit.len
  -- end

  -- assert(false, changed_chars_count_per_word)
  local words = vim.split(b, "%s+", { trimempty = true })
  local edits_to_remove = {}
  for i = 1, #words do
    vim.pretty_print(edits_per_word[i])
    -- At least n / 2 characters must have changed for a merge
    local word_len = #words[i]
    if
      edits_per_word[i]
      and #edits_per_word[i] > 1
      and word_len > 2
      and changed_chars_count_per_word[i] > word_len / 2
    then
      -- Replace the edits with a single substitution edit
      local edit_pos = edits_per_word[i][1]
      -- local changed_chars_count = get_changed_chars_count(edits[edit_pos])
      for j = 2, #edits_per_word[i] do
        vim.pretty_print(edits_per_word[i][j])
        -- changed_chars_count = changed_chars_count + get_changed_chars_count(edits[edits_per_word[i][j]])
      end

      local substitution_edit = {
        type = "substitution",
        a_start = word_start_pos[i],
        len = word_len,
        b_start = edits[edit_pos].b_start,
      }
      edits[edit_pos] = substitution_edit

      for j = 2, #edits_per_word[i] do
        -- Shift the next edits to the right to account for the new substitution edit,
        -- delete them if they have been overwritten
        local edit = edits[edits_per_word[i][2]]
        local substitution_end = substitution_edit.b_start + substitution_edit.len - 1
        if substitution_end >= edit.b_start + edit.len - 1 then
          edits_to_remove[edits_per_word[i][j]] = true
        elseif edit.b_start <= substitution_end then
          -- vim.pretty_print('try to shift', edit, edits)
          edit.a_start = edit.a_start + word_len
          edit.b_start = edit.b_start + word_len
          edit.len = edit.len - word_len
          assert(edit.len > 0)
        end
      end
    end
  end
  compact(edits, edits_to_remove)
  return edits
end

local function update_edits(edit_type, cur_edit, a_start, b_start, edits)
  if cur_edit.type == edit_type and (cur_edit.a_start == a_start + 1 or cur_edit.b_start == b_start + 1) then
    -- Extend the edit
    cur_edit.a_start = a_start
    cur_edit.b_start = b_start
    cur_edit.len = cur_edit.len + 1
  else
    -- Create a new edit
    cur_edit = { type = edit_type, a_start = a_start, b_start = b_start, len = 1 }
    table.insert(edits, 1, cur_edit)
  end
  return cur_edit
end

-- Returns a list of insertion and change operations
-- that turn the first string into the second one.
M.get_edits = function(str_a, str_b)
  if str_a == str_b then
    return {}
  end

  local len_a, len_b = #str_a, #str_b
  if len_a == 0 then
    return { { type = "insertion", a_start = 1, len = len_b, b_start = 1 } }
  elseif len_b == 0 then
    return { { type = "deletion", a_start = 1, len = len_a, b_start = 1 } }
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
    cur_edit = update_edits("deletion", cur_edit, row, col, edits)
    cur_edit.b_start = col + 1
    row = row - 1
    col = col + 1
  end

  local function try_insertion()
    local can_insert = matrix[row][col - 1] <= matrix[row - 1][col] and matrix[row][col - 1] <= matrix[row - 1][col - 1]
    if can_insert then
      cur_edit = update_edits("insertion", cur_edit, row, col, edits)
    end
    return can_insert
  end

  local function do_change()
    cur_edit = update_edits("change", cur_edit, row, col, edits)
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
          do_change()
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
                do_change()
              end
            end
          else
            do_change()
          end
        end
      end
    else
      row = row - 1
    end
    col = col - 1
  end

  if col > 0 then
    table.insert(edits, 1, { type = "insertion", a_start = 1, b_start = row + 1, len = col })
  elseif row > 0 then
    table.insert(edits, 1, { type = "deletion", a_start = 1, b_start = col + 1, len = row })
  end
  return edits, matrix
end

return M
