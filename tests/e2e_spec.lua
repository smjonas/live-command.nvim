local live_command = require("live-command")
local api = vim.api

local bufnr
local create_and_run_preview_cmd = function(cmd)
  api.nvim_set_current_buf(bufnr)
  live_command.create_preview_command("CustomPreviewCommand", cmd)
  vim.cmd("CustomPreviewCommand " .. cmd)
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
    local cmd = "norm daw"
    create_and_run_preview_cmd(cmd)
    assert.are_same({ "line", "Second line" }, get_lines())
  end)

  it("norm command with count", function()
    local cmd = "2norm daw"
    create_and_run_preview_cmd(cmd)
    assert.are_same({ "First line", "line" }, get_lines())
  end)

  it("g command", function()
    local cmd = "g/Second/d"
    create_and_run_preview_cmd(cmd)
    assert.are_same({ "First line" }, get_lines())
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
