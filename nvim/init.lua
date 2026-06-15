-- ~/.config/nvim/init.lua
-- Punto de entrada de Neovim (estructura modular, 2026).
-- Plugins viven en lua/plugins/*.lua y se cargan automáticamente.

-- 1) Opciones y keymaps base (define <leader> ANTES de cargar lazy)
require("config")

-- 2) Bootstrap de lazy.nvim
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  vim.fn.system({
    "git", "clone", "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git", "--branch=stable", lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

-- 3) Plugins: importa todos los specs de lua/plugins/
require("lazy").setup({ { import = "plugins" } }, {
  install = { colorscheme = { "catppuccin-mocha" } },
  checker = { enabled = true, notify = false }, -- chequea updates en silencio
  change_detection = { notify = false },
})

-- 4) Diagnósticos (en 0.11 virtual_text está OFF por defecto)
vim.diagnostic.config({
  virtual_text = { prefix = "●", spacing = 2 },
  signs = true,
  underline = true,
  update_in_insert = false,
  severity_sort = true,
  float = { border = "rounded", source = true },
})

-- 5) Winbar por ventana: nombre del archivo (color de estado) + cambios de git
require("winbar").setup()
