local M = {}

local provider = require("live_command.provider.levenshtein")
local utils = require("live_command.edit_utils")

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

local function get_edits_per_word(edits, splayed_edits, word_start_pos, words)
  local edits_per_word = {}
  local edited_chars_count = {}

  -- Get a list of edits (their indices, to be precise) that changed each word
  -- and the number of characters modified in a word
  for i, word in ipairs(words) do
    for j, edit in ipairs(splayed_edits) do
      -- local count_key = edit.type == "deletion" and "deleted" or "modified"
      local overlap = math.max(
        0,
        math.min(word_start_pos[i] + #word, edit.b_start + edit.len) - math.max(word_start_pos[i], edit.b_start)
      )

      if overlap > 0 then
        if not edited_chars_count[i] then
          edited_chars_count[i] = {
            insertion = 0,
            change = 0,
            deletion = 0,
            total = 0,
          }
        end
        edited_chars_count[i][edit.type] = edited_chars_count[i][edit.type] + overlap
        edited_chars_count[i].total = edited_chars_count[i].total + overlap
        if overlap == edit.len then
          if not edits_per_word[i] then
            -- TODO: refactor with default_table
            edits_per_word[i] = {}
          end
          table.insert(edits_per_word[i], j)
        end
      end

      if edit.b_start >= word_start_pos[i] then
        edits[j].overlap = overlap
        edits[j].word_len = #word
      end
    end
  end
  return edits_per_word, edited_chars_count
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

local function remove_marked_deletion_edits(edits)
  local offset = 0
  local edits_to_remove = {}
  for i, edit in ipairs(edits) do
    -- Shift all edits to account for the deleted substring
    if edit.activate then
      edits[i].len = edit.len - edit.overlap
    else
      edits[i].b_start = edit.b_start - offset
    end
    if edit.remove then
      edits_to_remove[i] = true
      offset = offset + edit.len
    end
    edits[i].activate = nil
    edits[i].overlap = nil
    edits[i].word_len = nil
  end
  compact(edits, edits_to_remove)
  return edits
end

-- If at least half of the characters in a word have been changed,
-- multiple edits will be combined into a single substitution edit.
-- This reduces the amount of highlights which may be confusing when using
-- the default Levenshtein provider.
M.get_edits = function(a, b, should_substitute)
  local edits = provider.get_edits(a, b)
  if #edits == 1 then
    -- Nothing to merge
    return edits
  end
  local splayed_edits
  b, splayed_edits = utils.undo_deletions(a, b, edits, { in_place = false })

  local char_pos_to_word, word_start_pos = get_char_pos_to_word(b)
  local words = vim.split(b, "%s+", { trimempty = true })
  local edits_per_word, edited_chars_count = get_edits_per_word(edits, splayed_edits, word_start_pos, words)

  for i = 1, #words do
    -- TODO: edits_per_word does not need to be nested
    local word_len = #words[i]
    if
      edits_per_word[i]
      and should_substitute {
        text = words[i],
        edited_chars_count = edited_chars_count[i],
      }
    then
      local edit_pos = edits_per_word[i][1]
      -- Create a new substitution edit spanning across all characters of the current word
      -- that have not been deleted and mark any existing deletion edits for removal
      local substitution_edit = {
        type = "substitution",
        a_start = word_start_pos[i],
        len = word_len - edited_chars_count[i].deletion,
        b_start = edits[edit_pos].b_start,
      }

      for _, edit in ipairs(edits_per_word[i] or {}) do
        if edits[edit].type == "change" or edits[edit].type == "deletion" then
          edits[edit].remove = true
        end
        edits[edit].activate = true
      end
      local neighbor_pos = edits_per_word[i][#edits_per_word[i]] + 1
      local neighbor_edit = edits[neighbor_pos]
      if neighbor_edit and neighbor_edit.overlap and char_pos_to_word[neighbor_edit.b_start] == i then
        edits[neighbor_pos].activate = true
      end
      table.insert(edits, edit_pos, substitution_edit)
    end
  end
  return remove_marked_deletion_edits(edits)
end

return M
