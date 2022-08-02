local provider = require("live_command.levenshtein_edits_provider")

describe("Levenshtein edits provider", function()
  it("computes correct distance matrix", function()
    local _, actual = provider.get_edits("abc", "ab")
    assert.are_same({
      [0] = { [0] = 0, 1, 2 },
      [1] = { [0] = 1, 0, 1 },
      [2] = { [0] = 2, 1, 0 },
      [3] = { [0] = 3, 2, 1 },
    }, actual)
  end)
end)

describe("Levenshtein get_edits", function()
  it("works for insertion", function()
    local actual, _ = provider.get_edits("b", "abc")
    assert.are_same({
      { type = "insertion", start_pos = 1, end_pos = 1 },
      { type = "insertion", start_pos = 3, end_pos = 3 },
    }, actual)
  end)

  it("works when first string is empty", function()
    local actual = provider.get_edits("", "ab")
    assert.are_same({
      { type = "insertion", start_pos = 1, end_pos = 2 },
    }, actual)
  end)

  it("works when second string is empty", function()
    local actual = provider.get_edits("ab", "")
    assert.are_same({
      { type = "deletion", start_pos = 1, end_pos = 2, b_start_pos = 1 },
    }, actual)
  end)

  it("works when both words are equal", function()
    local actual = provider.get_edits("Word", "Word")
    assert.are_same({}, actual)
  end)

  it("works for replacement", function()
    local actual = provider.get_edits("abcd", "aBCd")
    assert.are_same({
      { type = "replacement", start_pos = 2, end_pos = 3 },
    }, actual)
  end)

  it("works for mixed insertion and replacement", function()
    local actual = provider.get_edits("abcd", "AbecD")
    assert.are_same({
      { type = "replacement", start_pos = 1, end_pos = 1 },
      { type = "insertion", start_pos = 3, end_pos = 3 },
      { type = "replacement", start_pos = 5, end_pos = 5 },
    }, actual)
  end)

  -- it("prefers right positions when deleting multiple identical characters in a row", function()
  --   local actual = cmd_preview._get_edits("abcccce", "abcce")
  --   assert.are_same({
  --     { type = "deletion", start_pos = 5, end_pos = 6, b_start_pos = 5 },
  --   }, actual)
  -- end)

  it("works for deletion within word", function()
    local actual = provider.get_edits("abcde", "d")
    assert.are_same({
      { type = "deletion", start_pos = 1, end_pos = 3, b_start_pos = 1 },
      { type = "deletion", start_pos = 5, end_pos = 5, b_start_pos = 2 },
    }, actual)
  end)

  it("works for mixed insertion and deletion", function()
    local actual = provider.get_edits("a_ :=", "a:=,")
    assert.are_same({
      { type = "deletion", start_pos = 2, end_pos = 3, b_start_pos = 2 },
      { type = "insertion", start_pos = 4, end_pos = 4 },
    }, actual)
  end)

  it("prioritizes consecutive edits of the same type", function()
    -- This used to yield a replacement, insertion, replacement
    local actual = provider.get_edits([['word']], [[new "word"]])
    assert.are_same({
      { type = "insertion", start_pos = 1, end_pos = 4 },
      { type = "replacement", start_pos = 5, end_pos = 5 },
      { type = "replacement", start_pos = 10, end_pos = 10 },
    }, actual)
  end)
end)

describe("Levenshtein merge_edits", function()
  it("works when deleting characters at start / end of a word", function()
    local edits = provider.get_edits("ok  black ok", "ok  la ok")
    local actual = provider._merge_edits(edits, "ok  black ok")
    assert.are_same({
      { type = "substitution", start_pos = 5, end_pos = 10 },
    }, actual)
  end)

  it("does not merge when less than half of a word's characters have changed", function()
    local a = "eiht for"
    local edits = provider.get_edits(a, "eight four")
    local actual = provider._merge_edits(edits, a)
    assert.are_same(edits, actual)
  end)

  it("works when characters were inserted in the middle of a word", function()
    local a = "ok  black ok"
    local edits = provider.get_edits(a, "ok  la ok")
    local actual = provider._merge_edits(edits, a)
    assert.are_same({
      { type = "substitution", start_pos = 5, end_pos = 10 },
    }, actual)
  end)

  it("does not merge when characters were inserted at the start / end of a word", function()
    local edits = provider.get_edits("ok  black ok", "ok  la ok")
    local actual = provider._merge_edits(edits, "ok  black ok")
    assert.are_same({
      { type = "substitution", start_pos = 5, end_pos = 10 },
    }, actual)
  end)
end)
