# live-command.nvim

![live_command_demo](https://user-images.githubusercontent.com/40792180/179546128-ad49096e-7301-4929-9b24-2b08996bdff2.gif)

View the effects of any command on your buffer contents live. Preview macros, the `:norm` command & more!

> :warning: This plugin is still in development and breaking changes may occur without prior announcement.
> Make sure to watch this project on GitHub to be notified when it's released!

## Goals and Features
- Make it extremely simple to create previewable commands in Neovim
- Smart highlighting based on the Levenshtein distance algorithm
- View individual insertions, replacements and deletions

## Requirements
Neovim nightly (0.8).

## :rocket: Getting started
Install using your favorite package manager and call the setup function with a table of
commands to create. Here is an example that creates a previewable `:Norm` command:
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
| args        | string   | Arguments passed to the command. If `nil`, the arguments are supplied from the command-line while the user is typing the command.   | Yes       |

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

To change the default options globally, use the `defaults` table. The defaults are:

```lua
require("live_command").setup {
  defaults = {
    enable_highlighting = true,
    hl_groups = {
      insertion = "DiffAdd",
      replacement = "DiffChanged",
      deletion = "DiffDelete",
    },
    hl_range = { 0, 0, kind = "relative" },
  },
}
```

---

`enable_highlighting: boolean`

Default: `true`

Whether highlights should be shown. If `false`, only text changes are shown.

---

`hl_groups: table<string, string?>`

Default: `{ insertion = "DiffAdd", replacement = "DiffChanged", deletion = "DiffDelete" }`

A list of highlight groups per edit type (insertion, replacement or deletion) used for highlighting buffer changes.
The value can be `nil` in which case no highlights will be shown for that type. If `hl_groups.deletion` is `nil`,
deletion edits will not be undone which is otherwise done to make them visible.

---

`hl_range: table`

Default: `{ 0, 0, kind = "relative" }`

Determines the line range the command is executed on to calculate the highlights.
By default, if you run a command like `42Norm dsb`, changes to buffer lines outside the
given range (here: `42,42`) will not be previewed for performance reasons.
For certain commands that operate on surrounding lines (such as `dsb`),
it makes sense to increase this range, e.g. `{ -20, 20, kind = "relative" }`.
This will include the previous / next 20 lines.
To make sure that all highlights are shown, you can use `{ 1, -1, kind = "absolute" }`
(lines are 1-based, negative values are counted from the end of the buffer).

---

Like this project? Give it a :star: to show your support!

Also consider checking out my other plugin [inc-rename.nvim](https://github.com/smjonas/inc-rename.nvim),
which is optimized for live-renaming with LSP.
