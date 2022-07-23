# live-command.nvim

![live_command_demo](https://user-images.githubusercontent.com/40792180/179546128-ad49096e-7301-4929-9b24-2b08996bdff2.gif)

View the effects of any command on your buffer contents live. Preview macros, the `:norm` command & more!

> :warning: This plugin is still in development and breaking changes may occur without prior announcement.
> I will also reserve the right to force-push to the main branch which may prevent you from being able to
> pull the recent changes depending on your plugin manager.
> Make sure to watch this project on GitHub to be notified when it's released!

## :sparkles: Goals and Features
- Make it extremely simple to create previewable commands in Neovim
- Smart highlighting based on the Levenshtein distance algorithm, heavily optimized for performance
- View individual insertions, replacements and deletions

## Requirements
Neovim nightly (0.8).

## :rocket: Getting started
Install using your favorite package manager and call the setup function with a table of
commands to create. Here is an example that creates a previewable `:Norm` command (using packer.nvim):
```lua
use {
  "smjonas/live-command.nvim",
  config = function()
    require("live_command").setup {
      commands = {
        Norm = { cmd = "norm" },
      },
    }
  end,
}
```

## :gear: Usage and Customization
Each command you want to preview requires a name (must be upper-case) and the name of
an existing command that is run on each keypress.

Here is a list of available settings:

| Key         | Type     | Description                                                                                                                                | Optional? |
| ----------- | -------- | ------------------------------------------------------------------------------------------------------------------------------------------ | --------- |
| cmd         | string   | The name of an existing command run in the preview callback.                                                                               | No        |
| args        | string   | Arguments passed to the command. If not provided, the arguments are supplied from the command-line while the user is typing the command.   | Yes       |

### Example
The following example creates three `:Regx` commands where `x` is the name of a register (`a`, `b` or `c`).
These commands can be used to preview macros.
```lua
local commands = {}
for _, register in ipairs { "a", "b", "c" } do
  commands["Reg" .. register] = { cmd = "norm", args = "@" .. register }
end

require("live_command").setup {
  commands = commands,
}
```
\
All of the following options can be set globally (for all created commands), or per individual command.

---

`enable_highlighting: boolean`

Default: `true`

Whether highlights should be shown. If `false`, only text changes are shown.

---

`hl_group: string`

Default: `IncSearch`

The highlight group used for highlighting buffer changes.

---

`max_highlights: number`

Default: `9999`

Determines the maximum number of highlights shown in total. Note that the actual number of highlights may be slightly higher than this value.
You can lower this value to improve performance in some cases.

---

`max_line_highlights: table | function: string -> table`

Default: `{ count = 15, disable_highlights = true }`

Determines the maximum amount of highlights per line. This option is mostly used to avoid a distracting amount of highlights and has negligible performance impact.
If a table, it must contain the keys `count` and `disable_highlights`.
If a function, it will be called with the contents of the updated line(s) and must also return a table with the same keys.
If at least `count` highlights have been computed per line, the whole line is either shown without any highlights (if `disable_highlights = true`) or fully highlighted.
The exact argument depends on which editing operations are applied to the line(s).

---

### Global options

To set options globally, use the `defaults` table:
```lua
require("live_command").setup {
  defaults = { hl_group = "DiffAdd" },
  -- commands = ...
}
```

