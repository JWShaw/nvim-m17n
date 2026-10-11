# nvim-m17n

Toggle an [m17n](https://www.nongnu.org/m17n/) `.mim` input method in Neovim's
Insert mode.  Type transliterated Latin and get Cyrillic (or whatever the
`.mim` file defines) as you go — and only in Insert mode.

```
privet   -> привет
shchuka  -> щука
yolka    -> ёлка
```

Normal, Visual, Operator-pending, Terminal and Command-line modes are left
exactly as they were.

## How it works

Neovim already ships a full multi-key input method engine: **language mappings**
(`:lmap`), enabled per buffer with the `'iminsert'` option.  It natively
supports:

* multi-character key sequences (`shch` → `щ`),
* ambiguous prefixes / dead keys — when a sequence could still be extended,
  Neovim waits for the next key (`s` vs `sh` vs `shch`, `e` vs `e'`, `'` vs `''`),
* pass-through of anything that doesn't match.

This plugin parses the `.mim` file into `lmap` mappings and flips `'iminsert'`
on and off, so all the hard work is done by Neovim itself.

`'iminsert'` is *also* honoured by single-character Normal-mode commands such as
`r` and `f`.  To keep those modes normal, the plugin remembers the on/off state
in Lua and only sets `'iminsert'=1` while you are actually inside Insert mode:
`InsertEnter` restores it, and `InsertLeave` records the real value (so Neovim's
built-in `CTRL-^` toggle keeps working) and resets it to `0`.  When you enter
Insert mode again, your last choice is restored.

## Requirements

* Neovim 0.8 or newer (tested on 0.12).

## Installation

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "you/nvim-m17n",
  config = function()
    require("m17n").setup({
      mim = "ru-translit", -- bundled file at mim/ru-translit.mim
    })
  end,
}
```

Or simply put this directory somewhere on `'runtimepath'` and, if you like:

```lua
require("m17n").setup()
```

`setup()` is optional — the commands and Lua API work with the defaults too.

## Usage

### Commands

| Command           | Description                                        |
| ----------------- | -------------------------------------------------- |
| `:M17nToggle`     | Toggle the input method for the current buffer     |
| `:M17nEnable`     | Turn it on                                          |
| `:M17nDisable`    | Turn it off                                         |
| `:M17nStatus`     | Print the current status                            |
| `:M17nReload`     | Re-read the configured `.mim` file                  |
| `:M17nSetMim {f}` | Switch to another `.mim` file (name or path)        |

### Lua API

```lua
local m17n = require("m17n")

m17n.toggle()        -- returns true if now enabled
m17n.enable()
m17n.disable()
m17n.status()        -- true / false
m17n.reload()
```

### Key mapping

Neovim's built-in insert-mode `CTRL-^` already toggles `'iminsert'` (and
therefore this input method), so you can use it with no configuration:

```
privet<C-^>privet   -> приветprivet
```

If you prefer a different key, configure one.  `toggle_keymap` is set up in
Insert mode:

```lua
require("m17n").setup({
  toggle_keymap = "<C-^>", -- or "<M-i>", "<C-g>", ...
})
```

## Configuration

Defaults:

```lua
require("m17n").setup({
  mim = "ru-translit",   -- bundled name, or a path to any .mim file
  search = false,        -- true: also translate search patterns ('imsearch')
  default_on = false,    -- true: enable automatically in every buffer
  toggle_keymap = nil,   -- e.g. "<C-^>" to add an Insert-mode toggle mapping
})
```

* **`mim`** — either the name of a file in `mim/` on `'runtimepath'`
  (`"ru-translit"`), or a path to a `.mim` file (`"~/.m17n/foo.mim"`).
* **`search`** — when `false` (default), `'imsearch'` is set to `0` while
  enabled so typing a `/` search stays literal.  When `true`, search patterns
  are translated as well.

## Bundled input method

`mim/ru-translit.mim` is the Cyrillic transliteration method from the m17n
contrib collection (*ru-translit*, © Maxim Treskin, LGPL-2.1-or-later).  It
covers Russian plus Ukrainian, Belarusian, Serbian, Macedonian and more.
See the description at the top of the file for the full key table.

To add another `.mim`, drop it in `mim/` and pass its name to `setup()` or use
`:M17nSetMim`.

## Parsing notes

The parser (`lua/m17n/mim.lua`) understands the pragmatic subset used by
transliteration methods: `(map ...)` forms (including nested ones), string and
`?char` literals, and `;` comments.  `description`, `title` and `state` forms
are ignored.  Map entries that need executable expressions are not supported.

## License

Plugin code: MIT (or your preferred license).  The bundled `.mim` file remains
under its original LGPL-2.1-or-later license.
