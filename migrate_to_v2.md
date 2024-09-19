# Migration to v2.x
This is a guide for users looking to migrate to version `2.x` of `live-command`.
If you'd prefer to avoid breaking changes, you can pin the plugin to tag [`1.x`](https://github.com/smjonas/live-command.nvim/releases/tag/1.x) tag.

## What's new in version 2.0?
Version 2.0 is a complete rewrite, aimed at improving maintainability and future extensibility.
It introduces a simplified user-facing API, alongside improvements to the architecture of the plugin and the addition of a new `:Preview` command.

**Breaking changes**:
- Custom command specifications now only consist of a `cmd` value (a string). The `args`
  and `range` fields have been removed. See [next section](#how-can-i-migrate-from-older-versions) for details.

**New feature**:
- A new generic `:Preview` command allows you to preview any command without needing to
  define it in your configuration. This is useful for testing `live-command`'s capabilities
  or for previewing commands you use infrequently, where creating a separate user command doesn't
  seem necessary. The command accepts a range or count. Example: `:'<,'>Preview norm daw`
  previews the deletion of the first word in the selected lines.

## How can I migrate from older versions?
In versions `1.x`, the following example demonstrated how to preview the results of a macro:
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
In version `2.x`, you have two options:
1. Define a command `Norm = { cmd = "norm" }` and use it as `:Norm <count>@<register>` (e.g., `:Norm 5@a` to apply macro stored in register `a` five times).
2. Alternatively, define a custom `:Reg` user command that bevaves like the old version:

<details>
  <summary>View code</summary>

```lua
-- Transforms ":5Reg a" into ":norm 5@a"
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
