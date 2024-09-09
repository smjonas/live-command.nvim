# live-command.nvim
![version](https://img.shields.io/badge/version-2.0.0-brightgreen)

> :exclamation: Version 2.0 has been released with breaking changes! Please check out the [migration guide](./migrate_to_v2.md).

Text editing in Neovim with immediate visual feedback: view the effects of any command on your buffer contents live. Preview macros, the `:norm` command & more!

![live-command.nvim demo video](https://user-images.githubusercontent.com/40792180/235201812-adc95327-65cc-4ae4-8c2e-804853dd0c02.gif)
<p><sub>Theme: <a href="https://github.com/folke/tokyonight.nvim">tokyonight.nvim</a></sub></p>

## :sparkles: Motivation and Features
In Neovim version 0.8, the `command-preview` feature has been introduced.
Despite its name, it does not enable automatic previewing of any command.
Instead, users must manually update the buffer text and set highlights *for each command*.

This plugin aims to address this issue by offering a **simple API for creating previewable commands**
in Neovim. Simply provide the command you want to preview and live-command will do all the
work for you. This includes viewing **individual insertions, changes and deletions** as you type.

## Requirements
Neovim 0.8+

## :inbox_tray: Installation
Install using your favorite package manager and call the `setup` function:

<details>
    <summary>lazy.nvim</summary>

```lua
use {
  "smjonas/live-command.nvim",
  -- live-command supports semantic versioning via Git tags
  -- tag = "2.*",
  config = function()
    require("live-command").setup()
  end,
}
```
</details>

<details>
    <summary>vim-plug</summary>

```vim
Plug 'smjonas/live-command.nvim'
```
Somewhere in your init.lua, you will need to call the setup function:
```lua
require("live-command").setup()
```
</details>

## :rocket: Getting started
### Basic Usage
The simplest way to use **live-command** is with the provided `:Preview` command.
For instance, `:Preview delete` will show you a preview of deleting the current line.
You can also pass a count or a range to the command, e.g. `:'<,'>Preview norm A;` will
show the effect of appending a semicolon to every line selected in visual mode.

### Creating Previewable Commands
For a more convenient experience, **live-command** allows you to create custom previewable commands.
This is done by passing a list of commands to the setup function.
For example, you can define a custom `:Norm` command that can be previewed as follows:
```lua
require("live-command").setup {
  commands = {
    Norm = { cmd = "norm" },
  },
}
```

Each command you want to preview requires a name (must be upper-case) and the name of
an existing command that is run on each keypress via the `cmd` field.

## :gear: Customization

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
