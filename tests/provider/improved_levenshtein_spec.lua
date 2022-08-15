local provider = require("live_command.provider.improved_levenshtein")
local utils = require("live_command.edit_utils")

describe("Improved Levenshtein get_edits", function()
  it("#first works when deleting characters at start / end of a word", function()
    local a, b = "ok  black ok", "ok  la okI"
    local edits, new_b = provider.get_edits(a, b)
    assert.are_same({
      { type = "substitution", a_start = 5, len = 2, b_start = 5 },
      { type = "insertion", a_start = 12, len = 1, b_start = 13 },
    }, edits)
    assert.are_same(b, new_b)
  end)

  it("works when characters were inserted in the middle of a word", function()
    local a, b = "ok  black ok", "k  la ok"
    local edits = provider.get_edits(a, b)
    b = utils.undo_deletions(a, b, edits, { in_place = true })

    local actual = provider.get_edits(edits, b)
    assert.are_same({
      { type = "deletion", a_start = 1, len = 1, b_start = 1 },
      { type = "substitution", a_start = 5, len = 5, b_start = 5 },
    }, actual)
  end)

  it("shifts edits of following words", function()
    local a, b = "this 'word'", "x"
    local edits = provider.get_edits(a, b)
    b = utils.undo_deletions(a, b, edits, { in_place = true })

    local actual = provider.get_edits(edits, b)
    assert.are_same({
      { type = "substitution", a_start = 1, len = 4, b_start = 1 },
      -- Should have been shortened and shifted to the right
      { type = "deletion", a_start = 6, len = 6, b_start = 6 },
    }, actual)
  end)

  it("does not merge when less than half of a word's characters have changed", function()
    local a, b = "eiht for", "eight four"
    local edits = provider.get_edits(a, b)
    b = utils.undo_deletions(a, b, edits, { in_place = true })

    local actual = provider.get_edits(edits, b)
    assert.are_same(edits, actual)
  end)

  it("does not merge for more complex mixed deletion + insertion", function()
    local a, b = "Line", "ne 3"
    local edits = provider.get_edits(a, b)
    b = utils.undo_deletions(a, b, edits, { in_place = true })

    local actual = provider.get_edits(edits, b)
    -- Edits should be unchanged
    assert.are_same({
      { type = "deletion", a_start = 1, len = 2, b_start = 1 },
      { type = "insertion", a_start = 4, len = 2, b_start = 5 },
    }, actual)
  end)

  it("does not merge", function()
    local a, b = [[this 'word']], [["word"]]
    local edits = provider.get_edits(a, b)
    b = utils.undo_deletions(a, b, edits, { in_place = true })

    local actual = provider.get_edits(edits, b)
    -- Edits should be unchanged
    assert.are_same({
      { type = "deletion", a_start = 1, len = 2, b_start = 1 },
      { type = "insertion", a_start = 4, len = 2, b_start = 5 },
    }, actual)
  end)
end)
