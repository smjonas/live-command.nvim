local M = {}

local handlers = {}

---@param arg string
---@param handler fun(string)
M.register_argument_handler = function(arg, handler)
  handlers[arg] = handler
end

local create_user_command = function()
  vim.api.nvim_create_user_command("LiveCommand", function(selected)
    local arg = selected.fargs[1]
    local handler = handlers[arg]
    if handler then
      handler(arg)
    else
      vim.notify("[live-command] Unknown argument " .. arg)
    end
  end, {
    nargs = 1,
    complete = function(arglead, _, _)
      local args = vim.tbl_keys(handlers)
      -- Only complete arguments that start with arglead
      return vim.tbl_filter(function(arg)
        return arg:match("^" .. arglead)
      end, args)
    end,
  })
end

create_user_command()

return M
