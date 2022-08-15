local M = {}

local provider = require("live_command.provider.levenshtein")
local utils = require("live_command.edit_utils")

local function get_char_pos_to_word(b)
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
  return char_pos_to_word, word_start_pos
end

local function get_edits_per_word(edits, char_pos_to_word)
  local edits_per_word = {}
  local modified_chars_count = {}
  -- Get a list of edits (their indices, to be precise) that changed each word
  -- and the number of characters modified in a word
  for i, edit in ipairs(edits) do
    local start_pos, end_pos = edit.b_start, edit.b_start + edit.len - 1
    -- -- Move start_pos to the right until the next word (if there is one) and end_pos to the left
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
    if i == 3 then
      -- assert(start_word, vim.inspect(start_pos, char_pos_to_word))
    end
    if start_word then
      if not edits_per_word[start_word] then
        edits_per_word[start_word] = {}
      end
      table.insert(edits_per_word[start_word], i)

      local end_word = char_pos_to_word[end_pos]
      if start_word ~= end_word then
        if not edits_per_word[end_word] then
          edits_per_word[end_word] = {}
        end
        table.insert(edits_per_word[end_word], i)
      end

      if not modified_chars_count[start_word] then
        modified_chars_count[start_word] = {
          modified_count = 0,
          deleted_count = 0,
        }
      end
      local count_key = edit.type == "deletion" and "deleted_count" or "modified_count"

      for j = start_pos, end_pos do
        local word = char_pos_to_word[j]
        if word then
          modified_chars_count[start_word][count_key] = modified_chars_count[start_word][count_key] + 1
        end
      end
    end
  end
  return edits_per_word, modified_chars_count
end

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

local function remove_marked_deletion_edits(edits, b)
  vim.pretty_print(edits)
  local offset = 0
  local new_b = b
  local edits_to_remove = {}
  for i, edit in ipairs(edits) do
    if edit.remove then
      new_b = new_b:sub(1, edit.b_start - 1) .. new_b:sub(edit.b_start + edit.len - 1)
      offset = offset + edit.len
      edits_to_remove[i] = true
    else
      -- Shift any other edit to account for the deleted substring
      edits[i].a_start = edits[i].a_start - offset
      edits[i].b_start = edits[i].b_start - offset
    end
  end
  compact(edits, edits_to_remove)
  return edits, new_b
end

-- If at least half of the characters in a word have been changed,
-- multiple edits will be combined into a single replacement edit.
-- This reduces the amount of highlights which may be confusing in the default Levenshtein provider.
M.get_edits = function(a, b)
  local edits = provider.get_edits(a, b)
  if #edits == 1 then
    -- Nothing to merge
    return edits
  end
  local splayed_edits
  b, splayed_edits = utils.undo_deletions(a, b, edits, { in_place = false })

  local char_pos_to_word, word_start_pos = get_char_pos_to_word(b)
  local edits_per_word, modified_chars_count = get_edits_per_word(splayed_edits, char_pos_to_word)
  -- vim.pretty_print(edits_per_word, modified_chars_count)

  local words = vim.split(b, "%s+", { trimempty = true })
  for i = 1, #words do
    -- vim.pretty_print("edits for i", i, edits_per_word[i])
    -- At least n / 2 characters must have changed for a merge
    local word_len = #words[i]
    vim.pretty_print(edits_per_word[i], modified_chars_count[i], word_len)
    if
      edits_per_word[i]
      and #edits_per_word[i] > 1
      and word_len > 2
      and modified_chars_count[i].modified_count + modified_chars_count[i].deleted_count > word_len / 2
    then
      local edit_pos = edits_per_word[i][1]
      vim.pretty_print("splayed", splayed_edits[edit_pos])
      -- Create a new substitution edit spanning across all characters of the current word
      -- that have not been deleted and mark any existing deletion edits for removal
      local substitution_edit = {
        type = "substitution",
        a_start = word_start_pos[i],
        len = word_len - modified_chars_count[i].deleted_count,
        b_start = splayed_edits[edit_pos].b_start,
      }
      if splayed_edits[edit_pos].type == "deletion" then
        -- Start the substitution edit after the first deletion edit of the current word (if available)
        substitution_edit.b_start = substitution_edit.b_start - splayed_edits[edit_pos].len
      end

      for _, edit in ipairs(edits_per_word[i]) do
        -- Mark all deletion edits of the current word for removal
        if edits[edit].type == "deletion" then
          edits[edit].remove = true
        end
      end
      table.insert(edits, edit_pos, substitution_edit)
    end
  end
  return remove_marked_deletion_edits(edits, b)
end

return M
