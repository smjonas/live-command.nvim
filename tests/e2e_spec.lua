local live_command = require("live-command")
local api = vim.api

local bufnr
local create_preview_cmd = function(cmd_name, cmd_opts)
  api.nvim_set_current_buf(bufnr)
  live_command.create_previewable_command(cmd_name, cmd_opts)
end

local preview = function(cmd)
  api.nvim_set_current_buf(bufnr)
  vim.cmd("Preview " .. cmd)
end

local get_lines = function()
  return api.nvim_buf_get_lines(bufnr, 0, -1, false)
end

setup(function()
  live_command.setup()
end)

before_each(function()
  bufnr = api.nvim_create_buf(false, true)
  api.nvim_buf_set_lines(bufnr, 0, -1, false, { "First line", "Second line" })
end)

describe("create_preview_command works for", function()
  it("norm command", function()
    create_preview_cmd("Norm", { cmd = "norm" })
    vim.cmd("Norm daw")
    assert.are_same({ "line", "Second line" }, get_lines())
  end)

  it("norm command with count", function()
    create_preview_cmd("Norm", { cmd = "norm" })
    vim.cmd("2Norm daw")
    assert.are_same({ "First line", "line" }, get_lines())
  end)

  it("g command", function()
    create_preview_cmd("G", { cmd = "g" })
    vim.cmd("G/Second/d")
    assert.are_same({ "First line" }, get_lines())
  end)

  it("command spec in config", function()
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
    local cmd = "norm daw"
    preview(cmd)
    assert.are_same({ "line", "Second line" }, get_lines())
  end)

  it("norm command with count", function()
    local cmd = "2norm daw"
    preview(cmd)
    assert.are_same({ "First line", "line" }, get_lines())
  end)

  it("g command", function()
    local cmd = "g/Second/d"
    preview(cmd)
    assert.are_same({ "First line" }, get_lines())
  end)
end)
