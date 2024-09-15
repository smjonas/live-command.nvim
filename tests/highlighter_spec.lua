local highlighter = require("live-command.highlighter")

describe("inline_highlights", function()
  local function compute_diff(old_lines, new_lines)
    return vim.diff(old_lines[1], new_lines[1], { result_type = "indices" })
  end

  -- Checks for the case when the end of the line was unchanged
  it("single insertion", function()
    local old_lines = { "word" }
    local new_lines = { "new word" }

    local diff = compute_diff(old_lines, new_lines)
    local line_range = { 1, #new_lines }

    local inline_highlighting = true
    local undo_deletions = true

    local highlights, updated_lines =
      highlighter.get_highlights(diff, old_lines, new_lines, line_range, inline_highlighting, undo_deletions)

    assert.are_same({
      { kind = "insertion", line = 1, column = 1, length = 4 },
    }, highlights)
    assert.are_same({ "new word" }, updated_lines)
  end)

  it("insertions", function()
    local old_lines = { "word" }
    local new_lines = { "new word new" }

    local diff = compute_diff(old_lines, new_lines)
    local line_range = { 1, #new_lines }

    local inline_highlighting = true
    local undo_deletions = true

    local highlights, updated_lines =
      highlighter.get_highlights(diff, old_lines, new_lines, line_range, inline_highlighting, undo_deletions)

    assert.are_same({
      { kind = "insertion", line = 1, column = 1, length = 4 },
      { kind = "insertion", line = 1, column = 9, length = 4 },
    }, highlights)
    assert.are_same({ "new word new" }, updated_lines)
  end)

  it("insertions + deletion", function()
    local old_lines = { "a test" }
    local new_lines = { "test1" }

    local diff = compute_diff(old_lines, new_lines)
    local line_range = { 1, #new_lines }

    local inline_highlighting = true
    local undo_deletions = true

    local highlights, updated_lines =
      highlighter.get_highlights(diff, old_lines, new_lines, line_range, inline_highlighting, undo_deletions)

    assert.are_same({
      { kind = "deletion", line = 1, column = 1, length = 2 },
      { kind = "insertion", line = 1, column = 7, length = 1 },
    }, highlights)
    assert.are_same({ "a test1" }, updated_lines)
  end)

  it("change 1", function()
    local old_lines = { "      table.insert" }
    local new_lines = { "      x.insert" }

    local diff = compute_diff(old_lines, new_lines)
    local line_range = { 1, #new_lines }

    local inline_highlighting = true
    local undo_deletions = true

    local highlights, updated_lines =
      highlighter.get_highlights(diff, old_lines, new_lines, line_range, inline_highlighting, undo_deletions)

    assert.are_same({
      { kind = "change", line = 1, column = 7, length = 1 },
    }, highlights)
    assert.are_same({ "      x.insert" }, updated_lines)
  end)

  it("change 2", function()
    local old_lines = { "config = function()" }
    local new_lines = { "test = Function()" }

    local diff = compute_diff(old_lines, new_lines)
    local line_range = { 1, #new_lines }

    local inline_highlighting = true
    local undo_deletions = true

    local highlights, updated_lines =
      highlighter.get_highlights(diff, old_lines, new_lines, line_range, inline_highlighting, undo_deletions)

    assert.are_same({
      { kind = "change", line = 1, column = 1, length = 4 },
      { kind = "change", line = 1, column = 8, length = 1 },
    }, highlights)
    assert.are_same({ "test = Function()" }, updated_lines)
  end)

  it("change should not use negative column values", function()
    local old_lines = { "line" }
    local new_lines = { "tes" }

    local diff = compute_diff(old_lines, new_lines)
    local line_range = { 1, #new_lines }

    local inline_highlighting = true
    local undo_deletions = true

    local highlights, updated_lines =
      highlighter.get_highlights(diff, old_lines, new_lines, line_range, inline_highlighting, undo_deletions)

    assert.are_same({
      { kind = "change", line = 1, column = 1, length = 1 },
      { kind = "insertion", line = 1, column = 3, length = 1 },
    }, highlights)
    assert.are_same({ "tes" }, updated_lines)
  end)

  -- TODO: create the same test but when undo_deletions = false
  it("change + deletion", function()
    local old_lines = { "-- require plugins.nvim-surround" }
    local new_lines = { "lel" }

    local diff = compute_diff(old_lines, new_lines)
    local line_range = { 1, #new_lines }

    local inline_highlighting = true
    local undo_deletions = true

    local highlights, updated_lines =
      highlighter.get_highlights(diff, old_lines, new_lines, line_range, inline_highlighting, undo_deletions)

    assert.are_same({
      { kind = "change", line = 1, column = 1, length = 1 },
      { kind = "deletion", line = 1, column = 3, length = 2 },
      { kind = "deletion", line = 1, column = 6, length = 19 },
    }, highlights)
    assert.are_same({ "le plugins.nvim-surround" }, updated_lines)
  end)

  it("deletion", function()
    local old_lines = { "local tests" }
    local new_lines = { "local s" }

    local diff = compute_diff(old_lines, new_lines)
    local line_range = { 1, #new_lines }

    local inline_highlighting = true
    local undo_deletions = true

    local highlights, updated_lines =
      highlighter.get_highlights(diff, old_lines, new_lines, line_range, inline_highlighting, undo_deletions)

    assert.are_same({
      { kind = "deletion", line = 1, column = 7, length = 4 },
    }, highlights)
    assert.are_same({ "local tests" }, updated_lines)
  end)
end)
