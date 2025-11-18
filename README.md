# live-command.nvim
![version](https://img.shields.io/badge/version-2.2.0-brightgreen)

> :exclamation: Version 2.0 has been released with breaking changes! Be sure to check out the [migration guide](./migrate_to_v2.md).

Text editing in Neovim with immediate visual feedback: see the effects of any command on your buffer in real-time. Preview macros, the `:norm` command, and more!

![live-command.nvim demo video](https://user-images.githubusercontent.com/40792180/235201812-adc95327-65cc-4ae4-8c2e-804853dd0c02.gif)
<p><sub>Theme: <a href="https://github.com/folke/tokyonight.nvim">tokyonight.nvim</a></sub></p>

## :sparkles: Motivation and Features
In Neovim version 0.8, the `command-preview` feature was introduced.
Despite its name, it does not enable automatic previewing of any command.
Instead, users must manually update the buffer text and set highlights *for each command* they wish to preview.

This plugin addresses that limitation by offering a **simple API for creating previewable commands**
in Neovim. Just specify the command you want to preview and live-command will handle the rest.
This includes viewing **individual insertions, changes and deletions** as you type.

## Requirements
Neovim 0.8+

## :inbox_tray: Installation
Install via your favorite package manager and call the `setup` function:

<details>
    <summary>lazy.nvim</summary>

```lua
return {
  "smjonas/live-command.nvim",
  main = "live-command", -- Lazy thinks that MAIN is live_command for some reason
  opts = {
    commands = {
      Norm = { cmd = "norm" },
    },
  },
}
```
</details>

<details>
    <summary>vim-plug</summary>

```vim
Plug 'smjonas/live-command.nvim'
```
In your `init.lua`, call the setup function:
```lua
require("live-command").setup()
```
</details>

## :rocket: Getting started
### Basic Usage
The easiest way to use **live-command** is with the provided `:Preview` command.
For example, `:Preview delete` will show you a preview of deleting the current line.
You can also provide a count or a range to the command, such as `:'<,'>Preview norm A;`, which
shows the effect of appending a semicolon to every visually selected line.

### Creating Previewable Commands
For a more convenient experience, **live-command** allows you to define custom previewable commands.
This can be done by passing a list of commands to the `setup` function.
For instance, to define a custom `:Norm` command that can be previewed, use the following:
```lua
require("live-command").setup {
  commands = {
    Norm = { cmd = "norm" },
  },
}
```

Each command you want to preview needs a name (which must be uppercase) and
an existing command to run on each keypress, specified via the `cmd` field.

If you want to keep the name of existing commands, you can assign an alias like so:

```lua
vim.cmd("cnoreabbrev norm Norm")
```

## :gear: Customization

If you wish to customize the plugin, supply any settings that differ from the defaults
to the `setup` function. The following shows the default options:

```lua
require("live-command").setup {
  enable_highlighting = true,
  inline_highlighting = true,
  hl_groups = {
    insertion = "DiffAdd",
    deletion = "DiffDelete",
    change = "DiffChange",
  },
}
```

---

`enable_highlighting: boolean`

Default: `true`

Determines whether highlights should be shown. If `false`, only text changes are shown, without any highlights.

---

`inline_highlighting: boolean`

Default: `true`

If `true`, differing lines will be compared in a second run of the diff algorithm
to identify smaller differences. This can result in multiple highlights per line.
If set to `false`, the whole line will be highlighted as a single change.

---

`hl_groups: table<string, string|boolean>`

Default: `{ insertion = "DiffAdd", deletion = "DiffDelete", change = "DiffChange" }`

A table mapping edit types (insertion, deletion or change) to highlight groups used for highlighting buffer changes.
This table is merged with the defaults, allowing you to omit any keys that match the default.
If a value is set to `false`, no highlights will be shown for that type.
If `hl_groups.deletion` is `false`, deletion edits will not be undone, so deleted text won't be highlighted.

---

Like this project? Give it a :star: to show your support!

Also consider checking out my other plugin [inc-rename.nvim](https://github.com/smjonas/inc-rename.nvim),
which is optimized for live-renaming with LSP.
