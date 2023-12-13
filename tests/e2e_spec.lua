local live_command = require("live-command")
local api = vim.api

local bufnr
local preview_cmd = function(cmd)
  api.nvim_set_current_buf(bufnr)
  live_command.create_preview_command("Preview", cmd)
  vim.cmd("Preview " .. cmd)
end

local get_lines = function()
  return api.nvim_buf_get_lines(bufnr, 0, -1, false)
end

describe("Preview", function()
  setup(function()
    live_command.setup()
  end)

  before_each(function()
    bufnr = api.nvim_create_buf(false, true)
    api.nvim_buf_set_lines(bufnr, 0, -1, false, { "First line", "Second line" })
  end)

  -- it("g command", function()
  --   local cmd = "g/Second/d"
  --   run_cmd(cmd)
  --   print("rastrst")
  --   print(vim.g.kekw)
  --   -- assert.are_same({ "First line" }, get_lines())
  -- end)

  it("norm command", function()
    local cmd = "norm daw"
    preview_cmd(cmd)
    assert.are_same({ "line", "Second line" }, get_lines())
  end)
end)
