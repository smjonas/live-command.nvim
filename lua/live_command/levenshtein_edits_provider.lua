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

  while row > 0 and col > 0 do
    if str_a:sub(row, row) ~= str_b:sub(col, col) then
      if matrix[row - 1][col] <= matrix[row][col - 1] and matrix[row - 1][col] <= matrix[row - 1][col - 1] then
        -- TODO: continue fine-tuning edits
        cur_edit = update_edits("deletion", cur_edit, row, edits)
        cur_edit.b_start_pos = col + 1
        row = row - 1
        col = col + 1
      elseif matrix[row][col - 1] <= matrix[row - 1][col] and matrix[row][col - 1] <= matrix[row - 1][col - 1] then
        cur_edit = update_edits("insertion", cur_edit, col, edits)
      else
        cur_edit = update_edits("replacement", cur_edit, col, edits)
        row = row - 1
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
