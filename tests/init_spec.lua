local live_command = require("live-command")

describe("inline_highlights", function()
  setup(function()
    live_command._set_logger(require("live-command.logger"))
  end)

  -- Checks for the case when the end of the line was unchanged
  it("single insertion", function()
    local highlights = {}
    local updated_lines = { "new word" }
    live_command._add_inline_highlights(1, { "word" }, updated_lines, true, highlights)

    assert.are_same({
      { kind = "insertion", line = 1, column = 1, length = 4 },
    }, highlights)
    assert.are_same({ "new word" }, updated_lines)
  end)

  it("insertions", function()
    local highlights = {}
    local updated_lines = { "new word new" }
    live_command._add_inline_highlights(1, { "word" }, updated_lines, true, highlights)

    assert.are_same({
      { kind = "insertion", line = 1, column = 1, length = 4 },
      { kind = "insertion", line = 1, column = 9, length = 4 },
    }, highlights)
    assert.are_same({ "new word new" }, updated_lines)
  end)

  it("insertions + deletion", function()
    local highlights = {}
    local updated_lines = { "test1" }
    live_command._add_inline_highlights(1, { "a test" }, updated_lines, true, highlights)

    assert.are_same({
      { kind = "deletion", line = 1, column = 1, length = 2 },
      { kind = "insertion", line = 1, column = 7, length = 1 },
    }, highlights)
    assert.are_same({ "a test1" }, updated_lines)
  end)

  it("change 1", function()
    local highlights = {}
    local updated_lines = { "      x.insert" }
    live_command._add_inline_highlights(1, { "      table.insert" }, updated_lines, true, highlights)

    assert.are_same({
      { kind = "change", line = 1, column = 7, length = 1 },
    }, highlights)
    assert.are_same({ "      x.insert" }, updated_lines)
  end)

  it("change 2", function()
    local highlights = {}
    local updated_lines = { "test = Function()" }
    live_command._add_inline_highlights(1, { "config = function()" }, updated_lines, true, highlights)
    assert.are_same({
      { kind = "change", line = 1, column = 1, length = 4 },
      { kind = "change", line = 1, column = 8, length = 1 },
    }, highlights)
    assert.are_same({ "test = Function()" }, updated_lines)
  end)

  it("change should not use negative column values", function()
    local highlights = {}
    local updated_lines = { "tes" }
    live_command._add_inline_highlights(1, { "line" }, updated_lines, true, highlights)

    assert.are_same({
      { kind = "change", line = 1, column = 1, length = 1 },
      { kind = "insertion", line = 1, column = 3, length = 1 },
    }, highlights)
    assert.are_same({ "tes" }, updated_lines)
  end)

  -- TODO: create the same test but when undo_deletions = false
  it("change + deletion", function()
    local highlights = {}
    local updated_lines = { "lel" }
    live_command._add_inline_highlights(1, { "-- require plugins.nvim-surround" }, updated_lines, true, highlights)
    assert.are_same({
      { kind = "change", line = 1, column = 1, length = 1 },
      { kind = "deletion", line = 1, column = 3, length = 2 },
      { kind = "deletion", line = 1, column = 6, length = 19 },
    }, highlights)
    assert.are_same({ "le plugins.nvim-surround" }, updated_lines)
  end)

  it("deletion", function()
    local highlights = {}
    local updated_lines = { "local s" }
    live_command._add_inline_highlights(1, { "local tests" }, updated_lines, true, highlights)
    assert.are_same({
      { kind = "deletion", line = 1, column = 7, length = 4 },
    }, highlights)
    assert.are_same({ "local tests" }, updated_lines)
  end)
end)
