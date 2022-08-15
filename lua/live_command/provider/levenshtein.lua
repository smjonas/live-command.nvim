local M = {}


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
M.get_edits = function(a, b)
  if a == b then
    return {}
  end

  local len_a, len_b = #a, #b
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
      cost = a:sub(row, row) == b:sub(col, col) and 0 or 1
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
    if a:sub(row, row) ~= b:sub(col, col) then
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
          if cur_edit.type == "insertion" or a:sub(row, row) == b:sub(col - 1, col - 1) then
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
