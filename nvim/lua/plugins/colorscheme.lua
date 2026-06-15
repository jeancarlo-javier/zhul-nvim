-- lua/plugins/colorscheme.lua
-- Tema Catppuccin Mocha con fondo transparente (hereda el bg del terminal).

return {
  {
    "catppuccin/nvim",
    name = "catppuccin",
    priority = 1000, -- cargar antes que el resto para evitar parpadeo de colores
    config = function()
      require("catppuccin").setup({
        flavour = "mocha",
        transparent_background = true, -- usa el fondo del terminal (no pinta su propio bg)
        integrations = {
          telescope = true,
          gitsigns = true,
          nvimtree = true,
          treesitter = true,
          mason = true,
          which_key = true,
          blink_cmp = true,
          flash = true,
          snacks = true,
          lualine = true,
          mini = { enabled = true },
          native_lsp = { enabled = true },
          trouble = true,
          todo = true,
        },
      })
      vim.cmd.colorscheme("catppuccin-mocha")
    end,
  },
}
