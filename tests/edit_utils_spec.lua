local utils = require("live_command.edit_utils")

describe("Stripping common prefix and suffix", function()
  it("works", function()
    local new_a, new_b, new_start = utils.strip_common("xxxAyy", "xxxabcy")
    assert.are_same("Ay", new_a)
    assert.are_same("abc", new_b)
    -- 0-indexed
    assert.are_same(3, new_start)
  end)

  it("works when strings are equal", function()
    local new_a, new_b, skipped_cols_start, skipped_cols_end = utils.strip_common("Word", "Word")
    assert.are_same("", new_a)
    assert.are_same("", new_b)
    assert.are_same(4, skipped_cols_start)
    assert.are_same(0, skipped_cols_end)
  end)

  it("returns correct start_index when no common prefix or suffix", function()
    local new_a, new_b, new_start = utils.strip_common("abc", "ABC")
    assert.are_same("abc", new_a)
    assert.are_same("ABC", new_b)
    assert.are_same(0, new_start)
  end)

  it("linewise", function()
    local a = { "Line 1", "X", "Line 2" }
    local b = { "Line 1", "Line", "Line", "Line 2" }
    local new_a, new_b, start_lines_count = utils.strip_common_linewise(a, b)
    assert.are_same({ "X" }, new_a)
    assert.are_same({ "Line", "Line" }, new_b)
    -- Original tables should not change
    assert.are_same({ "Line 1", "X", "Line 2" }, a)
    assert.are_same({ "Line 1", "Line", "Line", "Line 2" }, b)
    assert.are_same(1, start_lines_count)
  end)
end)

describe("Undo deletions", function()
  it("#kekl works for simple case", function()
    local a = "acx"
    local b = "Abbc"
    local edits = {
      { type = "change", a_start = 1, len = 1, b_start = 1 },
      { type = "insertion", a_start = 2, len = 2, b_start = 2 },
      { type = "deletion", a_start = 3, len = 1, b_start = 5 },
    }

    local updated_b = utils.undo_deletions(a, b, edits)
    assert.are_same("Abbcx", updated_b)

    assert.are_same({
      -- b_start should now be relative to b
      { type = "change", a_start = 1, len = 1, b_start = 1 },
      { type = "insertion", a_start = 2, len = 2, b_start = 2 },
      { type = "deletion", a_start = 3, len = 1, b_start = 5 },
    }, edits)
  end)

  it("#kekl works for more complex deletion case", function()
    local a = "line1X\nline2\nline3\nline4"
    local b = "line1\nline3"
    local edits = {
      -- `X\nline2` and '\nline4' were deleted; not optimal but ok
      { type = "deletion", a_start = 6, len = 7, b_start = 6 },
      { type = "deletion", a_start = 19, len = 6, b_start = 12 },
    }

    local updated_b = utils.undo_deletions(a, b, edits)
    assert.are_same(a, updated_b)

    assert.are_same({
      { type = "deletion", a_start = 6, len = 7, b_start = 6 },
      -- b_start should have been increased to account for the updated b
      -- 19 is now the position where the second highlight will start:
      -- ('line1X\nline2\nline3\nline4')
      --                        ^
      { type = "deletion", a_start = 19, len = 6, b_start = 19 },
    }, edits)
  end)

  it("works for mixed insertion, change and deletion", function()
    local a = "words"
    local b = "IworR"

    local edits = {
      { type = "insertion", a_start = 1, len = 1, b_start = 1 },
      { type = "change", a_start = 4, len = 1, b_start = 5 },
      { type = "deletion", a_start = 5, len = 1, b_start = 6 },
    }

    local updated_b = utils.undo_deletions(a, b, edits)
    assert.are_same("IworRs", updated_b)
  end)

  it("works when deletion edit is followed by other edits", function()
    local a = "one 'word'"
    local b = [["word"]]
    local edits = {
      { type = "deletion", a_start = 1, len = 4, b_start = 1 },
      { type = "change", a_start = 4, len = 1, b_start = 1 },
      { type = "change", a_start = 10, len = 1, b_start = 6 },
    }

    local updated_b = utils.undo_deletions(a, b, edits)
    assert.are_same([[one "word"]], updated_b)

    assert.are_same({
      { type = "deletion", a_start = 1, b_start = 1, len = 4 },
      -- Positions should have been shifted
      { type = "change", a_start = 4, b_start = 5, len = 1 },
      { type = "change", a_start = 10, b_start = 10, len = 1 },
    }, edits)
  end)
end)

describe("Index to text position", function()
  it("works across multiple lines", function()
    local text = "line1\nline2"
    -- 1-indexed
    local line, col = utils.idx_to_text_pos(text, 7)
    assert.are_same(2, line)
    -- 1-indexed, inclusive
    assert.are_same(1, col)
    -- Sanity check
    assert.are_same("l", vim.split(text, "\n")[line]:sub(col, col))
  end)

  it("works for single line", function()
    local text = "line1"
    -- 1-indexed
    local line, col = utils.idx_to_text_pos(text, 1)
    -- 1-indexed, inclusive
    assert.are_same(1, line)
    assert.are_same(1, col)
  end)

  it("works for newline at end of line", function()
    local text = "line1\n"
    -- 1-indexed
    local line, col = utils.idx_to_text_pos(text, 6)
    -- 1-indexed, inclusive
    assert.are_same(1, line)
    assert.are_same(6, col)
  end)
end)

describe("Get multiline highlights from edits", function()
  -- These must not be nil or else some highlights would be skipped
  local dummy_hl_groups = { insertion = "I", change = "R", deletion = "D" }

  it("works for insertion across multiple lines", function()
    -- a = "line_1\naaline_4\n"
    local b = "line_1\naaNEW\nNEW\nXXline_4\n"
    -- 1-indexed, inclusive; inserted "NEW\nNEW\nXX"
    local edits = { { type = "insertion", a_start = 10, len = 10, b_start = 10 } }
    local actual = utils.get_multiline_highlights(b, edits, dummy_hl_groups)
    assert.are_same({
      -- 1-indexed, inclusive
      [2] = { { hl_group = "I", start_col = 3, end_col = -1 } },
      [3] = { { hl_group = "I", start_col = 1, end_col = -1 } },
      [4] = { { hl_group = "I", start_col = 1, end_col = 2 } },
    }, actual)
  end)

  it("returns positions on a single line when inserting at the end of the line", function()
    -- a = "abc"
    local b = "abcNEW"
    local edits = { { type = "insertion", a_start = 3, len = 3, b_start = 4 } }
    local actual = utils.get_multiline_highlights(b, edits, dummy_hl_groups)
    assert.are_same({
      -- 1-indexed, inclusive
      [1] = { { hl_group = "I", start_col = 4, end_col = 6 } },
    }, actual)
  end)

  it("works for deletion after insertion on single line", function()
    -- a = "LiXX"
    local b = "ILi"
    local edits = {
      { type = "insertion", a_start = 1, len = 1, b_start = 1 },
      { type = "deletion", a_start = 3, len = 2, b_start = 4 },
    }

    local actual = utils.get_multiline_highlights(b, edits, dummy_hl_groups)
    assert.are_same({
      [1] = {
        { hl_group = "I", start_col = 1, end_col = 1 },
        { hl_group = "D", start_col = 4, end_col = 5 },
      },
    }, actual)
  end)

  it("works for deletion across multiple lines", function()
    local a = "line1X\nline2\nline3\nline4"
    local b = "line1\nline3"
    local edits = {
      -- `X\nline2` and '\nline4' were deleted (not optimal but ok)
      { type = "deletion", a_start = 6, len = 7, b_start = 6 },
      { type = "deletion", a_start = 19, len = 6, b_start = 12 },
    }

    b = utils.undo_deletions(a, b, edits)
    local actual = utils.get_multiline_highlights(b, edits, dummy_hl_groups)
    assert.are_same({
      -- 1-indexed, inclusive; columns are relative to b
      [1] = { { hl_group = "D", start_col = 6, end_col = -1 } }, -- deletion of X
      -- deletion of '\nline2'; end_col != -1 here since this a continuation of the first highlight
      [2] = { { hl_group = "D", start_col = 1, end_col = 5 } },
      -- Line 3 should be skipped as there is only a single newline character
      [4] = { { hl_group = "D", start_col = 1, end_col = 5 } }, -- deletion of '\nline4'
    }, actual)
  end)
end)
