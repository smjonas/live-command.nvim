local provider = require("live_command.levenshtein_edits_provider")
local utils = require("live_command.edit_utils")

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

describe("#mer Levenshtein merge_edits", function()
  it("works when deleting characters at start / end of a word", function()
    local a, b = "ok  black ok", "ok  la okI"
    local edits = provider.get_edits(a, b)
    -- merge_edits requires deletions to be undone
    b, edits = utils.undo_deletions(a, b, edits, { in_place = true })

    local actual = provider.merge_edits(edits, b)
    assert.are_same({
      { type = "substitution", a_start = 5, len = 5, b_start = 5 },
      { type = "insertion", a_start = 12, len = 1, b_start = 13 },
    }, actual)
  end)

  it("does not merge when less than half of a word's characters have changed", function()
    local a, b = "eiht for", "eight four"
    local edits = provider.get_edits(a, b)
    b, edits = utils.undo_deletions(a, b, edits, { in_place = true })

    local actual = provider.merge_edits(edits, b)
    assert.are_same(edits, actual)
  end)

  it("works when characters were inserted in the middle of a word", function()
    local a, b = "ok  black ok", "k  la ok"
    local edits = provider.get_edits(a, b)
    b, edits = utils.undo_deletions(a, b, edits, { in_place = true })

    local actual = provider.merge_edits(edits, b)
    assert.are_same({
      { type = "deletion", a_start = 1, len = 1, b_start = 1 },
      { type = "substitution", a_start = 5, len = 5, b_start = 5 },
    }, actual)
  end)

  it("does not merge for more complex mixed deletion + insertion", function()
    local a, b = "Line", "ne 3"
    local edits = provider.get_edits(a, b)
    b, edits = utils.undo_deletions(a, b, edits, { in_place = true })

    local actual = provider.merge_edits(edits, b)
    -- Edits should be unchanged
    assert.are_same({
      { type = "deletion", a_start = 1, len = 2, b_start = 1 },
      { type = "insertion", a_start = 4, len = 2, b_start = 5 },
    }, actual)
  end)

  it("#cur does not merge", function()
    local a, b = [[this 'word']], [["word"]]
    local edits = provider.get_edits(a, b)
    b, edits = utils.undo_deletions(a, b, edits, { in_place = true })

    local actual = provider.merge_edits(edits, b)
    -- Edits should be unchanged
    assert.are_same({
      { type = "deletion", a_start = 1, len = 2, b_start = 1 },
      { type = "insertion", a_start = 4, len = 2, b_start = 5 },
    }, actual)
  end)

  it("shifts edits of following words", function()
    local a, b = "this 'word'", "x"
    local edits = provider.get_edits(a, b)
    b, edits = utils.undo_deletions(a, b, edits, { in_place = true })

    local actual = provider.merge_edits(edits, b)
    assert.are_same({
      { type = "substitution", a_start = 1, len = 4, b_start = 1 },
      -- Should have been shortened and shifted to the right
      { type = "deletion", a_start = 6, len = 6, b_start = 6 },
    }, actual)
  end)
end)
