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

## Motivation

Native, OS-level input methods tend to clash with Vim/Neovim.  An external IME
intercepts keys globally and keeps its own state, so switching between the
editor and the IME is awkward: you lose track of which side "owns" your
keystrokes, mode changes and `Escape` can leave the IME in an unexpected state,
and commands can arrive mangled.  Toggling the system IME on and off for the
few insertions that need it is easy to forget and easy to get wrong.

This plugin takes the opposite approach: instead of fighting a native input
method, it implements the input method *inside* Neovim using its built-in
language mappings.  That keeps everything Vim-native and self-contained — the
input method only exists in Insert mode, leaves every other mode untouched, and
needs no OS integration, background daemon or session-wide toggle.  It's also
deliberately small and dependency-free, which is enough for transliteration
methods even though full-featured IMEs (with candidate windows) are still the
right tool for stateful scripts — see [Unsupported: stateful input
methods](#unsupported-stateful-input-methods).

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
  "JWShaw/nvim-m17n",
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

## Supported input methods

The parser (`lua/m17n/mim.lua`) understands the **static transliteration** style
of `.mim` file: a single `(map ...)` of key sequences to plain output, e.g.

```lisp
(map
 (map
  ("a" ?а)
  ("shch" ?щ)
  ("~~" "Ъ")))

(state
 (init
  (map)))
```

If a file looks like this it will work.  `description`, `title` and `state`
forms are otherwise ignored.

## Unsupported: stateful input methods

Many m17n methods are **stateful**: they use multiple states, variables,
candidate lists and commands such as `select`, `shift`, `set`, `delete`,
`move`, `undo`, `cond` and `include`.  Those cannot be expressed as static
key → output mappings and are **not supported** by this plugin.  Examples:

* **Chinese** — `zh-pinyin.mim`, `zh-pinyin-vi.mim`, `zh-zhuyin.mim`,
  `zh-cangjie.mim`, `zh-quick.mim`, `zh-py.mim`, …
* **Indic** (ITRANS / InScript / typewriter) — `hi-*`, `bn-*`, `gu-*`, `kn-*`,
  `ml-*`, `te-*`, `ta-*`, `si-*`, `sa-*`, `mr-*`, …
* **Vietnamese** — `vi-telex`, `vi-vni`, `vi-viqr`, `vi-tcvn`, `vi-nom*`, …
* **Others** — Tibetan `bo-*`, Thai `th-*`, Korean `ko-romaja`, `ja-anthy`
  (which loads an external conversion server).

If you load one of these, the parser finds no usable static entries and nothing
is mapped.  Roughly 60% of the methods shipped in `/usr/share/m17n` are the
supported static kind; the rest are stateful.  You can tell them apart by
looking for a lone `(state (init (map)))` (supported) versus several states or
commands like `select` / `shift` / `set` (unsupported).

For those languages, use a full input-method framework such as
[fcitx5](https://fcitx-im.org/) or [ibus](https://github.com/ibus/ibus).  They
run the real m17n engine and provide candidate windows where needed — which is
also why reproducing them faithfully in Lua is out of scope here.

## License

Plugin code: MIT (or your preferred license).  The bundled `.mim` file remains
under its original LGPL-2.1-or-later license.

## AI disclaimer

This project was written using **DeepSeek 4.1 Flash** and **OpenCode**.  The
code and documentation were generated by an AI assistant and may contain
mistakes.  Review and test it before relying on it.
