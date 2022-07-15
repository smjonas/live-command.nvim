local cmd_preview = require("cmd_preview")

describe("Stripping common prefix and suffix", function()
  it("works", function()
    local new_a, new_b, new_start = cmd_preview._strip_common("xxxAyy", "xxxabcy")
    assert.are_same("Ay", new_a)
    assert.are_same("abc", new_b)
    -- 0-indexed
    assert.are_same(3, new_start)
  end)

  it("accounts for number of skipped lines by adjusting new_start", function()
    local new_a, new_b, new_start, skipped_lines_count =
      cmd_preview._strip_common("line_1\nline_2\nL", "line_1\nline_2\nLine_3\n")

    assert.are_same("", new_a)
    assert.are_same("ine_3\n", new_b)
    -- 0-indexed, this is the column offset in the first line
    assert.are_same(1, new_start)
    assert.are_same(2, skipped_lines_count)
  end)

  it("returns correct start_index when no common prefix or suffix", function()
    local new_a, new_b, new_start = cmd_preview._strip_common("abc", "ABC")
    assert.are_same("abc", new_a)
    assert.are_same("ABC", new_b)
    assert.are_same(0, new_start)
  end)

  it("linewise", function()
    local a = { "Line 1", "X", "Line 2" }
    local b = { "Line 1", "Line", "Line", "Line 2" }
    local new_a, new_b, start_lines_count = cmd_preview._strip_common_linewise(a, b)
    assert.are_same({ "X" }, new_a)
    assert.are_same({ "Line", "Line" }, new_b)
    -- Original tables should not change
    assert.are_same({ "Line 1", "X", "Line 2" }, a)
    assert.are_same({ "Line 1", "Line", "Line", "Line 2" }, b)
    assert.are_same(1, start_lines_count)
  end)
end)

describe("Levenshtein distance algorithm", function()
  it("computes correct matrix", function()
    local _, actual = cmd_preview._get_levenshtein_edits("abc", "ab", -1)
    assert.are_same({
      [0] = { [0] = 0, 1, 2 },
      [1] = { [0] = 1, 0, 1 },
      [2] = { [0] = 2, 1, 0 },
      [3] = { [0] = 3, 2, 1 },
    }, actual)
  end)
end)

describe("Levenshtein edits", function()
  it("works for insertion", function()
    local actual = cmd_preview._get_levenshtein_edits("ad", "abcd", -1)
    assert.are_same({
      { type = "insertion", start_pos = 2, end_pos = 3 },
    }, actual)
  end)

  it("works when first string is empty", function()
    local actual = cmd_preview._get_levenshtein_edits("", "ab", -1)
    assert.are_same({
      { type = "insertion", start_pos = 1, end_pos = 2 },
    }, actual)
  end)

  it("works for replacement", function()
    local actual = cmd_preview._get_levenshtein_edits("abcd", "aBCd", -1)
    assert.are_same({
      { type = "replacement", start_pos = 2, end_pos = 3 },
    }, actual)
  end)

  it("works for mixed insertion and replacement", function()
    local actual = cmd_preview._get_levenshtein_edits("abcd", "AbecD", -1)
    assert.are_same({
      { type = "replacement", start_pos = 1, end_pos = 1 },
      { type = "insertion", start_pos = 3, end_pos = 3 },
      { type = "replacement", start_pos = 5, end_pos = 5 },
    }, actual)
  end)

  it("works for deletion at end of word", function()
    local actual = cmd_preview._get_levenshtein_edits("abcd", "ab", -1)
    -- Deletion edits are not stored
    assert.are_same({}, actual)
  end)

  it("works for deletion within word", function()
    local actual = cmd_preview._get_levenshtein_edits("abcd", "ad", -1)
    -- Deletion edits are not stored
    assert.are_same({}, actual)
  end)

  it("returns early when max_edits_count is reached", function()
    local actual = cmd_preview._get_levenshtein_edits("abcd", "aXbXcXd", 3)
    assert.are_same({
      { type = "insertion", start_pos = 1, end_pos = 7 },
    }, actual)
  end)
end)

describe("Get multiline highlights from Levenshtein edits", function()
  it("(index to text position)", function()
    local text = "line1\nline2"
    -- Input index is 1-based, output line and column are 0-indexed
    local line, col = cmd_preview._idx_to_text_pos(text, 7)
    assert.are_same(1, line)
    -- Inclusive
    assert.are_same(0, col)
    -- Sanity check
    assert.are_same("l", vim.split(text, "\n")[line + 1]:sub(col + 1, col + 1))
  end)

  it("(index to text position for single line)", function()
    local text = "line1"
    -- Input index is 1-based, output line and column are 0-indexed
    local line, col = cmd_preview._idx_to_text_pos(text, 1)
    assert.are_same(0, line)
    assert.are_same(0, col)
  end)

  it("works for multi-line insertion", function()
    local text = "line_1\nXXNEW\nNEW\nXXline_4\n"
    -- 1-indexed, inclusive; inserted "XXNEW\nNEW\nXX"
    local edits = { { type = "insertion", start_pos = 10, end_pos = 19 } }
    local actual = cmd_preview._get_multiline_highlights(text, edits)
    assert.are_same({
      -- 0-indexed; end_col is exclusive
      { line = 1, start_col = 2, end_col = -1 },
      { line = 2, start_col = 0, end_col = -1 },
      { line = 3, start_col = 0, end_col = 2 },
    }, actual)
  end)

  it("returns positions on a single line when inserting at the end of the line", function()
    local text = "abcNEW"
    local edits = { { type = "insertion", start_pos = 4, end_pos = 6 } }
    local actual = cmd_preview._get_multiline_highlights(text, edits)
    assert.are_same({
      -- 0-indexed; end_col is exclusive
      { line = 0, start_col = 3, end_col = 6 },
    }, actual)
  end)
end)
