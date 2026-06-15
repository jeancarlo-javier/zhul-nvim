# zhul-nvim

> My personal **Neovim** configuration — modular Lua, [`lazy.nvim`](https://github.com/folke/lazy.nvim), Neovim **0.11+**.
> A portable backup & restore kit so I can stand the whole setup back up on a fresh machine in minutes.

Theme is **Catppuccin Mocha** with a **transparent background** (it inherits the terminal's background), a single global statusline (`lualine`), and a custom **per-window file header (winbar)** so you can always tell which file is in which split — even in diffs.

---

## ✨ Highlights

- **Custom winbar header** (`lua/winbar.lua`): each window shows its filename with a VSCode-style **status color** (red = LSP error, yellow = modified, normal = clean) on the left, and **git line changes** (`+added` `~changed` `-removed`) on the right. Transparent, per-window, rebuilds on diagnostics/git changes.
- **Modern LSP stack** (Neovim 0.11 native): Mason + `mason-lspconfig` auto-enable, `blink.cmp` completion (super-tab), `conform.nvim` format-on-save (prettier/stylua/ruff), ESLint `--fix` on save.
- **File explorer** (`nvim-tree`) with custom **jump-between-open-folders** (`{` / `}`) navigation.
- **Split cycling** with `Ctrl+]` (forward) / `Ctrl+[` (backward) — see the [Ctrl+[ section](#-the-ctrl-saga-karabiner--f13).
- Telescope, Treesitter, Flash, Trouble, gitsigns, mini.nvim, snacks.nvim, which-key, todo-comments.

---

## 📦 Requirements

| Tool | Why |
|------|-----|
| **Neovim ≥ 0.11** | Native LSP API (`vim.lsp.config/enable`), winbar |
| **git** | `lazy.nvim` bootstrap + plugin installs |
| A **Nerd Font** | devicons in winbar / tree / statusline |
| **ripgrep** (`rg`) | Telescope `live_grep` |
| **Node.js** | `ts_ls`, `eslint`, `prettier` |
| **Karabiner-Elements** (macOS) | optional — only for the `Ctrl+[` remap |

Language servers (`lua_ls`, `ts_ls`, `pyright`, `rust_analyzer`, `eslint`) and tools (`stylua`, `prettier`, `ruff`) are installed automatically by **Mason** on first launch.

---

## 🗂 Structure

```
zhul-nvim/
├── README.md
├── install.sh                 # restore script (backs up any existing config)
├── nvim/                       # → goes to ~/.config/nvim
│   ├── init.lua                # entry: config → lazy → plugins → diagnostics → winbar
│   ├── lazy-lock.json          # pinned plugin versions (reproducible installs)
│   └── lua/
│       ├── config.lua          # options + all core keymaps
│       ├── winbar.lua          # custom per-window file header
│       └── plugins/
│           ├── colorscheme.lua # catppuccin mocha, transparent
│           ├── editor.lua      # telescope, nvim-tree, gitsigns, flash, trouble, mini
│           ├── lsp.lua         # mason, lspconfig, blink.cmp, conform, lazydev
│           ├── treesitter.lua  # syntax + indent
│           └── ui.lua          # lualine, which-key, snacks, todo-comments
└── karabiner/
    ├── ctrl-bracket-f13.json   # Karabiner complex_modification rule
    └── ctrl-bracket-f13.js     # same rule for Karabiner's "Add your own rule (JS)"
```

---

## 🚀 Restore on a new machine

```bash
git clone https://github.com/jeancarlo-javier/zhul-nvim.git
cd zhul-nvim
./install.sh          # copies nvim/ → ~/.config/nvim (backs up any existing) + the Karabiner rule
nvim                  # lazy.nvim installs plugins; Mason installs servers/formatters
```

Prefer to do it by hand? Just copy `nvim/` to `~/.config/nvim` and launch `nvim`.

---

## ⌨️ Keymaps

Leader = `Space`.

### Windows & splits
| Key | Action |
|-----|--------|
| `<leader>sv` / `<leader>sh` | Split vertical / horizontal |
| `<leader>se` / `<leader>sx` | Equalize / close split |
| `<C-h/j/k/l>` | Move to window left/down/up/right |
| `<C-Arrows>` | Resize split |
| `<C-]>` | **Cycle to next split** (loops) |
| `Ctrl+[` (→ `<F13>`) | **Cycle to previous split** (loops) |

### Buffers, tabs, editing
| Key | Action |
|-----|--------|
| `<S-h>` / `<S-l>` | Previous / next buffer |
| `<leader>to/tx/tn/tp` | Tab new/close/next/prev |
| `jk` (insert) | Exit insert mode |
| `<leader>un` | Toggle absolute / hybrid line numbers |
| `J` / `K` (visual) | Move selection down / up |

### Telescope
| Key | Action |
|-----|--------|
| `<leader>ff` / `fg` / `fb` | Find files / live grep / buffers |
| `<leader>fd` / `fo` / `fr` | Diagnostics / recent files / resume |
| `<leader>ft` | Find TODOs |

### File explorer (nvim-tree)
| Key | Action |
|-----|--------|
| `<leader>ee` / `ef` | Toggle / reveal current file |
| `<leader>ec` / `er` | Collapse / refresh |
| `{` / `}` (inside tree) | **Jump to previous / next open folder** |

### LSP (buffer-local) & code
| Key | Action |
|-----|--------|
| `gd` / `gr` / `gi` / `gD` | Definition / references / implementation / declaration |
| `<leader>rn` / `<leader>ca` | Rename / code action |
| `<leader>ds` | Document symbols |
| `<leader>cf` / `<leader>uf` | Format buffer / toggle format-on-save |

### Git (gitsigns) · Jumps · Diagnostics · Surround
| Key | Action |
|-----|--------|
| `]c` / `[c` | Next / previous hunk |
| `<leader>hs/hr/hp/hb/hd` | Stage / reset / preview / blame / diff hunk |
| `s` / `S` | Flash jump / Flash treesitter |
| `<leader>xx/xX/xs/xq` | Trouble: diagnostics / buffer / symbols / quickfix |
| `gsa/gsd/gsr` … | mini.surround add / delete / replace |

### Completion (blink.cmp)
`Tab` / `Shift-Tab` navigate · `<C-space>` docs · `<C-e>` cancel · `<C-k>` signature.

---

## 🔌 Plugins

| Plugin | Role |
|--------|------|
| `folke/lazy.nvim` | Plugin manager |
| `catppuccin/nvim` | Colorscheme (mocha, transparent) |
| `nvim-telescope/telescope.nvim` | Fuzzy finder |
| `nvim-tree/nvim-tree.lua` | File explorer |
| `lewis6991/gitsigns.nvim` | Git gutter + hunks (`attach_to_untracked = true`) |
| `folke/flash.nvim` | Fast motions |
| `folke/trouble.nvim` | Diagnostics list |
| `echasnovski/mini.nvim` | ai / surround / pairs |
| `neovim/nvim-lspconfig` + `mason.nvim` + `mason-lspconfig` | LSP |
| `saghen/blink.cmp` | Completion (super-tab) |
| `stevearc/conform.nvim` | Format-on-save |
| `folke/lazydev.nvim` | Lua/Neovim type support |
| `nvim-treesitter/nvim-treesitter` | Syntax / indent (`master` branch) |
| `nvim-lualine/lualine.nvim` | Statusline (`globalstatus = true`) |
| `folke/which-key.nvim` | Keymap hints |
| `folke/snacks.nvim` | bigfile, indent, notifier, statuscolumn, scope, input |
| `folke/todo-comments.nvim` | TODO/FIX/HACK highlighting |

Exact commits are pinned in `nvim/lazy-lock.json` — run `:Lazy restore` to match them.

---

## 🪟 The winbar header

`lualine` runs with `globalstatus = true` (one statusline for the whole editor), which means there's **no per-window label**. In diffs/splits you couldn't tell which file was which. `lua/winbar.lua` adds a transparent, per-window header:

- **Left:** devicon + dim parent folder + filename, colored by status — red (LSP error) → yellow (modified) → normal (clean); a `●` marks unsaved changes; inactive windows dim out.
- **Right:** git changes from gitsigns — `+N` (green), `~N` (yellow), `-N` (red).

Each window's ID is baked into its winbar expression (`vim.g.actual_curwin` isn't reliable during winbar evaluation), so every split renders its **own** buffer.

---

## ⌨️ The `Ctrl+[` saga (Karabiner → F13)

I wanted `Ctrl+]` / `Ctrl+[` to cycle splits. `Ctrl+]` works, but **`Ctrl+[` is physically identical to `Esc`** — they send the same byte (`0x1B`), an ASCII control-code convention. Neovim also hardcodes `<C-[>` ≡ `<Esc>` ([neovim/neovim#17867](https://github.com/neovim/neovim/issues/17867)), and Warp can't emit a custom sequence for it ([warp#8462](https://github.com/warpdotdev/Warp/issues/8462)). So no terminal or keyboard-layout change fixes it.

**The global fix:** intercept the key **above** the terminal with [Karabiner-Elements](https://karabiner-elements.pqrs.org/), remapping `Ctrl+[` → **F13** (an unused key) only inside terminal apps. Neovim then maps `<F13>` → previous split.

```
Ctrl+[ ──(Karabiner, in Warp/Ghostty only)──▶ F13 ──(Neovim)──▶ <C-w>W (prev split)
```

Setup:
1. `brew install --cask karabiner-elements`, grant **Input Monitoring**.
2. Enable the rule: drop `karabiner/ctrl-bracket-f13.json` into `~/.config/karabiner/assets/complex_modifications/` and enable it under **Settings → Complex Modifications** (or paste `ctrl-bracket-f13.js` into "Add your own rule").
3. The `<F13>` → `<C-w>W` map is already in `lua/config.lua`.

> Caveat: at the OS level Karabiner can't distinguish nvim from the shell, so inside those terminals `Ctrl+[` no longer sends `Esc` at the shell prompt (only matters for shell vi-mode).

---

## License

Personal config — MIT. Use freely.
