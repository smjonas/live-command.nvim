local provider = require("live_command.provider.levenshtein")

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
      { type = "insertion", a_start = 1, len = 1, b_start = 1 },
      { type = "insertion", a_start = 1, len = 1, b_start = 3 },
    }, actual)
  end)

  it("works when first string is empty", function()
    local actual = provider.get_edits("", "ab")
    assert.are_same({
      { type = "insertion", a_start = 1, len = 2, b_start = 1 },
    }, actual)
  end)

  it("works when second string is empty", function()
    local actual = provider.get_edits("ab", "")
    assert.are_same({
      { type = "deletion", a_start = 1, len = 2, b_start = 1 },
    }, actual)
  end)

  it("works when both words are equal", function()
    local actual = provider.get_edits("Word", "Word")
    assert.are_same({}, actual)
  end)

  it("works for change", function()
    local actual = provider.get_edits("abcd", "aBCd")
    assert.are_same({
      { type = "change", a_start = 2, b_start = 2, len = 2 },
    }, actual)
  end)

  it("works for mixed insertion and change", function()
    local actual = provider.get_edits("a", "bc")
    assert.are_same({
      { type = "change", a_start = 1, b_start = 1, len = 1 },
      { type = "insertion", a_start = 1, b_start = 2, len = 1 },
    }, actual)
  end)

  -- it("prefers right positions when deleting multiple identical characters in a row", function()
  --   local actual = cmd_preview._get_edits("abcccce", "abcce")
  --   assert.are_same({
  --     { type = "deletion", a_start = 5, a_end = 6, b_start = 5 },
  --   }, actual)
  -- end)

  it("works for deletion within word", function()
    local actual = provider.get_edits("abcde", "d")
    assert.are_same({
      { type = "deletion", a_start = 1, b_start = 1, len = 3 },
      { type = "deletion", a_start = 5, b_start = 2, len = 1 },
    }, actual)
  end)

  it("works for mixed insertion and deletion 1", function()
    local actual = provider.get_edits("a_ :=", "a:=,")
    assert.are_same({
      { type = "deletion", a_start = 2, b_start = 2, len = 2 },
      { type = "insertion", a_start = 5, b_start = 4, len = 1 },
    }, actual)
  end)

  it("works for mixed insertion and deletion 2", function()
    local actual = provider.get_edits("Line", "ne 3")
    assert.are_same({
      { type = "deletion", a_start = 1, b_start = 1, len = 2 },
      { type = "insertion", a_start = 4, b_start = 3, len = 2 },
    }, actual)
  end)

  -- TODO: prioritize whole word edits
  it("#skip works for mixed change and deletion", function()
    local actual = provider.get_edits("Line 1 test", "LRne")
    -- LRnXXXXXeXX
    assert.are_same({
      { type = "deletion", a_start = 1, b_start = 1, len = 2 },
      { type = "insertion", a_start = 4, b_start = 3, len = 2 },
    }, actual)
  end)

  it("prioritizes consecutive edits of the same type", function()
    -- This used to yield a change, insertion, replacement
    local actual = provider.get_edits([['word']], [[new "word"]])
    assert.are_same({
      { type = "insertion", a_start = 1, b_start = 1, len = 4 },
      { type = "change", a_start = 1, b_start = 5, len = 1 },
      { type = "change", a_start = 6, b_start = 10, len = 1 },
    }, actual)
  end)
end)
