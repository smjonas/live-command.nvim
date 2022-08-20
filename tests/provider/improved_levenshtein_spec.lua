local provider = require("live_command.provider.improved_levenshtein")
local should_substitute = function(word)
  return word.edited_chars_count.total > #word.text / 2
end

describe("#lev Improved Levenshtein get_edits", function()
  it("#kek when deleting characters at start / end of a word", function()
    local a, b = "ok  black ok", "ok  la okI"
    local edits = provider.get_edits(a, b, should_substitute)
    assert.are_same({
      { type = "substitution", a_start = 5, len = 2, b_start = 5 },
      { type = "insertion", a_start = 12, len = 1, b_start = 10 },
    }, edits)
  end)

  it("works when characters were inserted in the middle of a word", function()
    local a, b = "ok  black ok", "k  la ok"
    local edits = provider.get_edits(a, b, should_substitute)
    assert.are_same({
      { type = "deletion", a_start = 1, len = 1, b_start = 1 },
      { type = "substitution", a_start = 5, len = 2, b_start = 4 },
    }, edits)
  end)

  it("#cur shifts edits of following words (deletion)", function()
    local a, b = "this 'word'", "x"
    local edits = provider.get_edits(a, b, should_substitute)
    assert.are_same({
      { type = "substitution", a_start = 1, len = 1, b_start = 1 },
      { type = "deletion", a_start = 2, len = 7, b_start = 2 },
    }, edits)
  end)

  it("#cur shifts edits of following words (insertion)", function()
    local a, b = "local fn = vim.fn", "R fn = vim.fn,"
    local edits = provider.get_edits(a, b, should_substitute)
    assert.are_same({
      { type = "substitution", a_start = 1, len = 1, b_start = 1 },
      { type = "insertion", a_start = 17, len = 1, b_start = 14 },
    }, edits)
  end)

  it("does not merge when less than half of a word's characters were changed", function()
    local a, b = "eiht for", "eight four"
    local edits = provider.get_edits(a, b, should_substitute)
    assert.are_same({
      { a_start = 2, b_start = 3, len = 1, type = "insertion" },
      { a_start = 7, b_start = 9, len = 1, type = "insertion" },
    }, edits)
  end)

  it("does not merge for mixed deletion + insertion", function()
    local a, b = "Line", "ne 3"
    local edits = provider.get_edits(a, b, should_substitute)
    -- Edits should be unchanged
    assert.are_same({
      { type = "deletion", a_start = 1, len = 2, b_start = 1 },
      { type = "insertion", a_start = 4, len = 2, b_start = 3 },
    }, edits)
  end)

  it("does not merge for mixed deletion + change", function()
    local a, b = [[this 'word']], [["word"]]
    local edits = provider.get_edits(a, b, should_substitute)
    -- Edits should be unchanged
    assert.are_same({
      { a_start = 1, b_start = 1, len = 5, type = "deletion" },
      { a_start = 6, b_start = 1, len = 1, type = "change" },
      { a_start = 11, b_start = 6, len = 1, type = "change" },
    }, edits)
  end)
end)
