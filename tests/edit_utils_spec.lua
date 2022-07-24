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
  it("works for simple case", function()
    local a = "acx"
    local b = "Abbc"
    local edits = {
      { type = "replacement", start_pos = 1, end_pos = 1 },
      { type = "insertion", start_pos = 2, end_pos = 3 },
      -- start_pos and end_pos are relative to a, b_start_pos is relative to b
      { type = "deletion", start_pos = 3, end_pos = 3, b_start_pos = 5 },
    }

    local updated_b = utils.undo_deletions(a, b, edits)
    assert.are_same("Abbcx", updated_b)
  end)

  it("works for more complex deletion case", function()
    local a = "line1X\nline2\nline3\nline4"
    local b = "line1\nline3"
    local edits = {
      -- `X\nline2` and '\nline4' were deleted; not optimal but ok
      { type = "deletion", start_pos = 6, end_pos = 12, b_start_pos = 6 },
      { type = "deletion", start_pos = 19, end_pos = 24, b_start_pos = 12 },
    }

    local updated_b = utils.undo_deletions(a, b, edits)
    assert.are_same(a, updated_b)
  end)

  it("works for mixed insertion, replacement and deletion", function()
    local a = "words"
    local b = "IworR"
    local edits = {
      -- `X\nline2` and '\nline4' were deleted; not optimal but ok
      { type = "insertion", start_pos = 1, end_pos = 1 },
      { type = "replacement", start_pos = 5, end_pos = 5 },
      { type = "deletion", start_pos = 5, end_pos = 5, b_start_pos = 6 },
    }

    local updated_b = utils.undo_deletions(a, b, edits)
    assert.are_same("IworRs", updated_b)
  end)
end)

describe("Index to text position", function()
  it("works across multiple lines", function()
    local text = "line1\nline2"
    -- Input index is 1-based, output line and column are 0-indexed
    local line, col = utils.idx_to_text_pos(text, 7)
    assert.are_same(1, line)
    -- Inclusive
    assert.are_same(0, col)
    -- Sanity check
    assert.are_same("l", vim.split(text, "\n")[line + 1]:sub(col + 1, col + 1))
  end)

  it("works for single line", function()
    local text = "line1"
    -- Input index is 1-based, output line and column are 0-indexed
    local line, col = utils.idx_to_text_pos(text, 1)
    assert.are_same(0, line)
    assert.are_same(0, col)
  end)

  it("works for newline at end of line", function()
    local text = "line1\n"
    -- Input index is 1-based, output line and column are 0-indexed
    local line, col = utils.idx_to_text_pos(text, 6)
    assert.are_same(0, line)
    assert.are_same(5, col)
  end)
end)

describe("Get multiline highlights from edits", function()
  it("works for multi-line insertion", function()
    local a = "line_1\naaline_4\n"
    local b = "line_1\naaNEW\nNEW\nXXline_4\n"
    -- 1-indexed, inclusive; inserted "NEW\nNEW\nXX"
    local edits = { { type = "insertion", start_pos = 10, end_pos = 19 } }
    local actual = utils.get_multiline_highlights(a, b, edits)
    assert.are_same({
      -- 0-indexed; end_col is exclusive
      [1] = { { start_col = 2, end_col = -1 } },
      [2] = { { start_col = 0, end_col = -1 } },
      [3] = { { start_col = 0, end_col = 2 } },
    }, actual)
  end)

  it("returns positions on a single line when inserting at the end of the line", function()
    local a, b = "abc", "abcNEW"
    local edits = { { type = "insertion", start_pos = 4, end_pos = 6 } }
    local actual = utils.get_multiline_highlights(a, b, edits)
    assert.are_same({
      -- 0-indexed; end_col is exclusive
      [0] = { { start_col = 3, end_col = 6 } },
    }, actual)
  end)

  it("works for deletion across multiple lines", function()
    local a = "line1X\nline2\nline3\nline4"
    local b = "line1\nline3"
    local edits = {
      -- `X\nline2` and '\nline4' were deleted; not optimal but ok
      { type = "deletion", start_pos = 6, end_pos = 12, b_start_pos = 6 },
      { type = "deletion", start_pos = 19, end_pos = 24, b_start_pos = 12 },
    }

    local actual = utils.get_multiline_highlights(a, b, edits)
    assert.are_same({
      -- 0-indexed; end_col is exclusive; columns are relative to b
      [0] = { { start_col = 5, end_col = -1 } }, -- deletion of X
      -- deletion of '\nline2'; end_col != -1 here since this a continuation of the first highlight
      [1] = { { start_col = 0, end_col = 5 } },
      -- Line with index 2 should be skipped as there is only a single newline character
      [3] = { { start_col = 0, end_col = 5 } }, -- deletion of '\nline4'
    }, actual)
  end)
end)
