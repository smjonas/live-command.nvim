local cmd_preview = require("cmd_preview")

local measure_time = function(f)
  return function()
    local start_s, start_us = vim.loop.gettimeofday()
    f()
    local end_s, end_us = vim.loop.gettimeofday()
    local start_ms = start_s * 1000.0 + start_us / 1000.0
    local end_ms = end_s * 1000.0 + end_us / 1000.0
    print(("Took %d ms."):format(end_ms - start_ms))
  end
end

describe("Stripping common prefix and suffix", function()
  it("works", function()
    local new_a, new_b, new_start = cmd_preview._strip_common("xxxAyy", "xxxabcy")
    assert.are_same("Ay", new_a)
    assert.are_same("abc", new_b)
    -- 0-indexed
    assert.are_same(3, new_start)
  end)

  it("returns correct start_index when no common prefix or suffix", function()
    local new_a, new_b, new_start = cmd_preview._strip_common("abc", "ABC")
    assert.are_same("abc", new_a)
    assert.are_same("ABC", new_b)
    assert.are_same(0, new_start)
  end)
end)

describe("Levenshtein distance algorithm", function()
  it("computes correct matrix", function()
    local _, actual = cmd_preview._get_levenshtein_edits("abc", "ab")
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
    local actual = cmd_preview._get_levenshtein_edits("ad", "abcd")
    assert.are_same({
      { type = "insertion", start_pos = 2, end_pos = 3 },
    }, actual)
  end)

  it("works for replacement", function()
    local actual = cmd_preview._get_levenshtein_edits("abcd", "aBCd")
    assert.are_same({
      { type = "replacement", start_pos = 2, end_pos = 3 },
    }, actual)
  end)

  it("works for mixed insertion and replacement", function()
    local actual = cmd_preview._get_levenshtein_edits("abcd", "AbecD")
    assert.are_same({
      { type = "replacement", start_pos = 1, end_pos = 1 },
      { type = "insertion", start_pos = 3, end_pos = 3 },
      { type = "replacement", start_pos = 5, end_pos = 5 },
    }, actual)
  end)

  it("works for deletion at end of word", function()
    local actual = cmd_preview._get_levenshtein_edits("abcd", "ab")
    assert.are_same({
      { type = "deletion", start_pos = 3, end_pos = 4 },
    }, actual)
  end)

  it("works for deletion within word", function()
    local actual = cmd_preview._get_levenshtein_edits("abcd", "ad")
    assert.are_same({
      { type = "deletion", start_pos = 2, end_pos = 3 },
    }, actual)
  end)

  it(
    "performance test",
    measure_time(function()
      local a = ("A"):rep(20000)
      local b = ("B"):rep(20000)
      local _, _ = cmd_preview._get_levenshtein_edits(a, b)
    end)
  )

  it(
    "performance test (common prefix and suffix)",
    measure_time(function()
      local a = ("A"):rep(10000) .. "a" .. ("B"):rep(10000)
      local b = ("A"):rep(10000) .. "b" .. ("B"):rep(10000)
      local edits, matrix = cmd_preview._get_levenshtein_edits(a, b)

      assert.are_same({
        { type = "replacement", start_pos = 10001, end_pos = 10002 },
      }, edits)
      assert.are_same({
        { [0] = 0, 1 },
        { [0] = 1, 1 },
      }, matrix)
    end)
  )
end)

describe("Levenshtein edits to highlight positions", function()
  it("(index to text position)", function()
    local text = "line1\nline2"
    -- zero-indexed
    local line, col = cmd_preview._idx_to_text_pos(text, 7)
    assert.are_same(1, line)
    assert.are_same(1, col)
    -- Sanity check
    assert.are_same("i", vim.split(text, "\n")[line + 1]:sub(col + 1, col + 1))
  end)

  it("returns positions on a single line when inserting at the end of the line", function()
    local text = "abcNEW"
    local edits = { { type = "insertion", start_pos = 4, end_pos = 6 } }
    local actual = cmd_preview._edits_to_hl_positions(text, edits)
    assert.are_same({
      -- zero-indexed; end_col is end-exclusive
      { line = 0, start_col = 3, end_col = 6 },
    }, actual)
  end)

  it("returns empty table for deletion edits", function()
    local text = "abc"
    local edits = { { type = "deletion", start_pos = 1, end_pos = 2 } }
    local actual = cmd_preview._edits_to_hl_positions(text, edits)
    assert.are_same({}, actual)
  end)
end)
