local live_command = require("live-command")
local api = vim.api

local bufnr

local get_lines = function()
  return api.nvim_buf_get_lines(bufnr, 0, -1, false)
end

before_each(function()
  bufnr = api.nvim_create_buf(false, true)
  api.nvim_buf_set_lines(bufnr, 0, -1, false, { "First line", "Second line" })
  api.nvim_set_current_buf(bufnr)
end)

describe("create_preview_command works for", function()
  it("norm command", function()
    live_command.create_previewable_command("Norm", { cmd = "norm" })
    vim.cmd("Norm daw")
    assert.are_same({ "line", "Second line" }, get_lines())
  end)

  it("norm command with count", function()
    live_command.create_previewable_command("Norm", { cmd = "norm" })
    vim.cmd("2Norm daw")
    assert.are_same({ "First line", "line" }, get_lines())
  end)

  it("norm command with range", function()
    live_command.create_previewable_command("Norm", { cmd = "norm" })
    vim.cmd("1,2Norm daw")
    assert.are_same({ "line", "line" }, get_lines())
  end)

  it("g command", function()
    live_command.create_previewable_command("G", { cmd = "g" })
    vim.cmd("G/Second/d")
    assert.are_same({ "First line" }, get_lines())
  end)

  it("#kek command spec in config", function()
    vim.api.nvim_set_current_buf(bufnr)
    live_command.setup {
      commands = {
        ABC = { cmd = "norm" },
      },
    }
    vim.cmd("ABC daw")
    assert.are_same({ "line", "Second line" }, get_lines())
  end)
end)

describe(":Preview works for", function()
  it("norm command", function()
    vim.cmd("Preview norm daw")
    assert.are_same({ "line", "Second line" }, get_lines())
  end)

  it("norm command with count", function()
    vim.cmd("Preview 2norm daw")
    assert.are_same({ "First line", "line" }, get_lines())
  end)

  it("g command", function()
    vim.cmd("Preview g/Second/d")
    assert.are_same({ "First line" }, get_lines())
  end)
end)
