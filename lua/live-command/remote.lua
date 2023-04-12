---@class Remote
local M = {}

---@type Logger
local logger

local uv = vim.loop
local tmp_file = os.tmpname()
local dirty = true

---@type table
local cur_marks

---@param server_address string
---@param on_chan_id fun(chan_id:number)
---@param num_retries number
local try_connect = function(server_address, on_chan_id, num_retries)
  local ok, chan_id
  for i = 0, num_retries do
    ok, chan_id = pcall(vim.fn.sockconnect, "pipe", server_address, { rpc = true })
    if ok then
      on_chan_id(chan_id)
      return true
    end
    if i ~= num_retries then
      vim.wait(10)
    end
  end
  return false
end

--- Starts a new Nvim instance and connects to it via RPC.
---@param logger_ Logger
---@param on_chan_id fun(chan_id: number)
M.init_rpc = function(logger_, on_chan_id)
  logger = logger_
  local basename = vim.fs.normalize(vim.fn.stdpath("cache"))
  local server_address = basename .. "/live_command_server_%d.pipe"

  -- Try to connect to an existing server that has already been spawned
  local success = try_connect(server_address, on_chan_id, 1)
  if success then
    logger.trace("init_rpc: connected to existing server")
    return
  end

  logger.trace("init_rpc: spawning new server")

  -- Use environment variables from parent process
  local env = { "LIVECOMMAND_NVIM_SERVER=1" }
  for k, v in pairs(uv.os_environ()) do
    table.insert(env, k .. "=" .. v)
  end

  local handle
  handle, _ = uv.spawn(
    vim.v.progpath,
    {
      args = { "--listen", server_address, "-n" },
      env = env,
      cwd = vim.fn.getcwd(),
    },
    vim.schedule_wrap(function(_, _) -- on exit
      handle:close()
    end)
  )

  assert(handle)
  success = try_connect(server_address, on_chan_id, 100)

  if success then
    logger.trace("init_rpc: connected to server")
  else
    vim.notify("[live-command.nvim] failed to connect to remote Neovim instance after 1000 ms", vim.log.levels.ERROR)
  end
end

M.on_buffer_updated = function()
  dirty = true
end

--- Called by the remote Nvim instance to set the marks.
---@param marks table
M.receive_marks = function(marks)
  local bufnr = vim.api.nvim_get_current_buf()
  for _, mark in ipairs(marks) do
    -- Remove first char ' to get mark name, use pcall as sometimes marks fail to be set
    pcall(vim.api.nvim_buf_set_mark, bufnr, mark.name:sub(2), mark.lnum, mark.col - 1, {})
  end
end

--- Synchronizes the current local marks so that the remote instance
--- has the correct mark positions.
---@param chan_id number
local sync_local_marks = function(chan_id)
  local diff = {}
  cur_marks = cur_marks or {}

  -- Index by mark name for easier access
  local new_marks = {}
  for _, entry in ipairs(vim.fn.getmarklist(vim.api.nvim_get_current_buf())) do
    new_marks[entry.mark] = entry
  end

  -- Collect all marks that haven't been synced
  for mark, entry in pairs(new_marks) do
    local new_pos = entry.pos
    local cur_pos = cur_marks[mark] and cur_marks[mark].pos
    if not cur_pos or cur_pos[1] ~= new_pos[1] or cur_pos[2] ~= new_pos[2] or cur_pos[3] ~= new_pos[3] then
      table.insert(diff, { name = mark, lnum = new_pos[2], col = new_pos[3] })
    end
  end

  if next(diff) ~= nil then
    vim.rpcrequest(chan_id, "nvim_exec_lua", "require('live-command.remote').receive_marks(...)", { diff })
  end
  cur_marks = new_marks
end

--- Called when the user enters the command line.
---@param chan_id number?
M.sync = function(chan_id)
  -- Child instance has not been created yet
  if not chan_id then
    return
  end

  if dirty then
    -- Synchronize buffers by writing out the current buffer contents to a temporary file.
    -- Remove A and F option values to not affect the alternate file and the buffer name.
    vim.cmd("let c=&cpoptions | set cpoptions-=A | set cpoptions-=F | silent w! " .. tmp_file .. " | let &cpoptions=c")
    vim.rpcrequest(
      chan_id,
      "nvim_exec",
      -- Store the current sequence number that can be reverted back to
      ("e! %s | lua vim.g._seq_cur = vim.fn.undotree().seq_cur"):format(tmp_file),
      false
    )
    dirty = false
  end
  sync_local_marks(chan_id)
end

--- Runs a command on the remote server and returns the updates buffer lines.
--- This is superior to running vim.cmd from the preview callback in the original Nvim instance
--- as that has a lot of side effects, e.g. https://github.com/neovim/neovim/issues/21495.
---@param chan_id number
---@param cmd string
---@param cursor_row number
---@param cursor_col number
M.run_cmd = function(chan_id, cmd, cursor_row, cursor_col)
  -- Restore the buffer state since the last write and move the cursor to the correct position
  vim.rpcrequest(chan_id, "nvim_exec_lua", "vim.api.nvim_win_set_cursor(...)", { 0, { cursor_row, cursor_col } })

  -- Execute the command asynchronously using rpcnotify as it may block
  vim.rpcnotify(chan_id, "nvim_exec", cmd, false)

  return vim.rpcrequest(
    chan_id,
    "nvim_exec_lua",
    [[local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
      vim.cmd.undo({count = vim.g._seq_cur})
      return lines
    ]],
    {}
  )
end

return M
