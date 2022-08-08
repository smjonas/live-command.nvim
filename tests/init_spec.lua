local live_command = require("live_command")

describe("Preview", function()
  setup(function()
    live_command.utils = require("live_command.edit_utils")
    live_command.provider = require("live_command.levenshtein_edits_provider")
  end)

  describe("per line", function()
    it("works", function()
      local set_line = mock(function(line_nr, line) end)
      local apply_highlight = mock(function(hl) end)
      local cached_lines = { "Line 1", "Line 2", "Line", "Line" }
      local updated_lines = { "LRne", "LineI 2", "ne 3", "Line" }

      live_command._preview_per_line(
        cached_lines,
        updated_lines,
        { insertion = "I", change = "R", deletion = "D" },
        function() end,
        set_line,
        apply_highlight
      )
      assert.stub(set_line).was_called_with(1, "LRne 1")
      assert.stub(set_line).was_called_with(2, "LineI 2")
      assert.stub(set_line).was_called_with(3, "Line 3")
      assert.stub(set_line).was_called_with(4, "Line")

      assert.stub(apply_highlight).was_called_with {
        line = 1,
        start_col = 2,
        end_col = 2,
        hl_group = "R",
      }

      assert.stub(apply_highlight).was_called_with {
        line = 1,
        start_col = 5,
        end_col = 6,
        hl_group = "D",
      }

      assert.stub(apply_highlight).was_called_with {
        line = 2,
        start_col = 5,
        end_col = 5,
        hl_group = "I",
      }

      assert.stub(apply_highlight).was_called_with {
        line = 3,
        start_col = 1,
        end_col = 2,
        hl_group = "D",
      }

      assert.stub(apply_highlight).was_called_with {
        line = 3,
        start_col = 5,
        end_col = 6,
        hl_group = "I",
      }
    end)

    it("works when change / insertion is preceded by deletion", function()
      local apply_highlight = mock(function(hl) end)
      live_command._preview_per_line(
        { [[this 'word']] },
        { [["word"]] },
        { insertion = "I", change = "R", deletion = "D" },
        nil,
        function() end,
        apply_highlight
      )

      assert.stub(apply_highlight).was_called_with {
        line = 1,
        start_col = 1,
        end_col = 5,
        hl_group = "D",
      }

      assert.stub(apply_highlight).was_called_with {
        line = 1,
        -- Should be shifted because of the deletion edit at the start
        start_col = 6,
        end_col = 6,
        hl_group = "R",
      }

      assert.stub(apply_highlight).was_called_with {
        line = 1,
        start_col = 11,
        end_col = 11,
        hl_group = "R",
      }
    end)

    it("deletions are not undone when hl_groups.deletion is nil", function()
      local set_line = mock(function(line_nr, line) end)
      local set_lines = mock(function(lines) end)
      local apply_highlight = mock(function(hl) end)
      local cached_lines = { "Line 1" }
      local updated_lines = { "LRne" }

      live_command._preview_per_line(
        cached_lines,
        updated_lines,
        { insertion = "I", change = "R", deletion = nil },
        set_lines,
        set_line,
        apply_highlight
      )
      assert.stub(set_line).was_not_called_with("LRne 1")
      assert.stub(set_line).was_not_called_with("LRne")
      assert.stub(set_lines).was_called_with { "LRne" }

      assert.stub(apply_highlight).was_called_with {
        line = 1,
        start_col = 2,
        end_col = 2,
        hl_group = "R",
      }

      assert.stub(apply_highlight).was_not_called_with {
        line = 1,
        start_col = 5,
        end_col = 6,
        hl_group = "D",
      }
    end)
  end)

  it("across lines works", function()
    local set_lines = mock(function(lines) end)
    local apply_highlight = mock(function(hl) end)

    local cached_lines = {
      "Identical",
      "Line",
      "Line 2",
    }
    local updated_lines = {
      "Identical",
      -- One insertion and one deletion
      "I Line",
      "Line",
    }

    live_command._preview_across_lines(
      cached_lines,
      updated_lines,
      { insertion = "I", change = "R", deletion = "D" },
      set_lines,
      apply_highlight
    )
    assert.stub(set_lines).was_called_with { "Identical", "I Line", "Line 2" }

    assert.stub(apply_highlight).was_called_with {
      line = 2,
      start_col = 1,
      end_col = 2,
      hl_group = "I",
    }

    assert.stub(apply_highlight).was_called_with {
      line = 3,
      start_col = 5,
      end_col = 6,
      hl_group = "D",
    }
  end)
end)
