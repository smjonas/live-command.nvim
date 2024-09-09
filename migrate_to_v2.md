# Migration to v2.0
This is a guide for users that want to migrate to version `2.0` of `live-command`.
If you want to stay on version `1.0`, you can also pin the plugin to the tag `v1.0`.

## What has changed in version 2.0?
Version 2.0 is a rewrite of the plugin for better maintainability and future extensibility.
It simplifies the user-facing API while improving the architecture of the plugin and adding a new `:Preview` command.

**Breaking change**:
- Custom command specifications now only consist of a `cmd` value (a string); `args`
  and `range` have been removed. See

**New feature**:
- New generic `:Preview` command that allows to preview any command without having to
  define it in the configuration. This is useful to test out the capabilities of
  `live-command` or if you don't use a command as often to warrant a separate user command.
  The command itself does not take a range or count. Example: `:Preview '<,'>norm daw`
  previews deletion of the first word of the selected lines.

## How can I migrate from older versions?
In versions `1.x`, the following example was provided showing how to preview the results of a macro:
```lua
local commands = {
  Reg = {
    cmd = "norm",
    -- This will transform ":5Reg a" into ":norm 5@a"
    args = function(opts)
      return (opts.count == -1 and "" or opts.count) .. "@" .. opts.args
    end,
    range = "",
  },
}
```
In `v2.0`, you have two options:
1. Define a command `Norm = { cmd = "norm" }` and use it as `:Norm <count>@<register>` (e.g., `:Norm 5@a` to apply macro stored in register `a` five times)
2. Define a custom `:Reg` user command like this that works just like the old version:

<details>
  <summary>View code</summary>

```lua
-- Turns ":5Reg a" into ":norm 5@a"
local function get_command_string(cmd)
  local get_range_string = require("live-command").get_range_string
  local args = (cmd.count == -1 and "" or cmd.count) .. "@" .. cmd.args
  return get_range_string(cmd) .. "norm " .. args
end

vim.api.nvim_create_user_command("Reg", function(cmd)
  vim.cmd(get_command_string(cmd))
end, {
  nargs = "?",
  range = true,
  preview = function(cmd, preview_ns, preview_buf)
    local cmd_to_preview = get_command_string(cmd)
    return require("live-command").preview_callback(cmd_to_preview, preview_ns, preview_buf)
  end
})
```
</details>
