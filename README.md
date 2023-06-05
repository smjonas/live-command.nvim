# live-command.nvim
![version](https://img.shields.io/badge/version-1.2.1-brightgreen)

Text editing in Neovim with immediate visual feedback: view the effects of any command on your buffer contents live. Preview macros, the `:norm` command & more!

![live-command.nvim demo video](https://user-images.githubusercontent.com/40792180/235201812-adc95327-65cc-4ae4-8c2e-804853dd0c02.gif)
<p><sub>Theme: <a href="https://github.com/folke/tokyonight.nvim">tokyonight.nvim</a></sub></p>

## :sparkles: Motivation and Features
In version 0.8, Neovim has introduced the `command-preview` feature.
Contrary to what "command preview" suggests, previewing any given
command does not work out of the box: you need to manually update the buffer text and set
highlights *for every command*.

This plugin tries to change that: it provides a **simple API for creating previewable commands**
in Neovim. Just specify the command you want to run and live-command will do all the
work for you. This includes viewing **individual insertions, changes and deletions** as you
type.

## Requirements
Neovim 0.8+

## :rocket: Getting started
Install using your favorite package manager and call the setup function with a table of
commands to create. Here is an example that creates a previewable `:Norm` command:
```lua
use {
  "smjonas/live-command.nvim",
  -- live-command supports semantic versioning via tags
  -- tag = "1.*",
  config = function()
    require("live-command").setup {
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

| Key         | Type     | Description
| ----------- | -------- | ------------------------------------------------------------------------------------------------------------------------------------------
| cmd         | string   | The name of an existing command to preview.
| args        | string? \| function(arg: string?, opts: table) -> string | Arguments passed to the command. If a function, takes in the options passed to the command and must return the transformed argument(s) `cmd` will be called with. `opts` has the same structure as the `opts` table passed to the `nvim_create_user_command` callback function. If `nil`, the arguments are supplied from the command-line while the user is typing the command.
| range       | string?  | The range to prepend to the command. Set this to `""` if you don't want the new command to receive a count, e.g. when turning `:9Reg a` into `:norm 9@a`. If `nil`, the range will be supplied from the command entered.

### Example
The following example creates a `:Reg` command which allows you to preview the effects of macros (e.g. `:5Reg a` to run macro `a` five times).
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

require("live-command").setup {
  commands = commands,
}
```
\
All of the following options can be set globally (for all created commands), or per command.

To change the default options globally, use the `defaults` table. The defaults are:

```lua
require("live-command").setup {
  defaults = {
    enable_highlighting = true,
    inline_highlighting = true,
    hl_groups = {
      insertion = "DiffAdd",
      deletion = "DiffDelete",
      change = "DiffChange",
    },
  },
}
```

---

`enable_highlighting: boolean`

Default: `true`

Whether highlights should be shown. If `false`, only text changes are shown.

---

`inline_highlighting: boolean`

Default: `true`

If `true`, differing lines will be compared in a second run of the diff algorithm. This
can result in multiple highlights per line. Otherwise, the whole line will be highlighted as
a single change highlight.

---

`hl_groups: table<string, string|boolean>`

Default: `{ insertion = "DiffAdd", deletion = "DiffDelete", change = "DiffChange" }`

A list of highlight groups per edit type (insertion, deletion or change) used for highlighting buffer changes.
The table will be merged with the defaults so you can omit any keys that are the same as the default.
If a value is set to `false`, no highlights will be shown for that type. If `hl_groups.deletion` is `false`,
deletion edits will not be undone which is otherwise done to make the text changes visible.

---

Like this project? Give it a :star: to show your support!

Also consider checking out my other plugin [inc-rename.nvim](https://github.com/smjonas/inc-rename.nvim),
which is optimized for live-renaming with LSP.
