-- lua/plugins/ui.lua
-- Interfaz: statusline, hints de atajos, y mejoras de calidad de vida (snacks).

return {
  -- Statusline
  {
    "nvim-lualine/lualine.nvim",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    event = "VeryLazy",
    opts = {
      options = {
        theme = "catppuccin",
        globalstatus = true, -- una sola statusline para todas las ventanas (0.7+)
        section_separators = "",
        component_separators = "|",
      },
    },
  },

  -- Hints de atajos (which-key v3)
  {
    "folke/which-key.nvim",
    event = "VeryLazy",
    opts = {},
  },

  -- Quality of life de folke: bigfile, indent guides, notifier, statuscolumn, etc.
  {
    "folke/snacks.nvim",
    priority = 1000,
    lazy = false,
    opts = {
      bigfile = { enabled = true },     -- desactiva features pesadas en archivos enormes
      quickfile = { enabled = true },   -- arranque más rápido al abrir un archivo directo
      indent = { enabled = true },      -- guías de indentación + scope
      notifier = { enabled = true },    -- reemplaza vim.notify con notificaciones bonitas
      statuscolumn = { enabled = true },-- columna de números/signos/folds unificada
      scope = { enabled = true },
      words = { enabled = true },       -- resalta la palabra bajo el cursor (LSP references)
      input = { enabled = true },       -- reemplaza vim.ui.input
    },
  },

  -- Resalta y permite buscar TODO / FIX / HACK / NOTE
  {
    "folke/todo-comments.nvim",
    event = { "BufReadPost", "BufNewFile" },
    dependencies = { "nvim-lua/plenary.nvim" },
    opts = { signs = true },
    keys = {
      { "<leader>ft", "<cmd>TodoTelescope<cr>", desc = "Find TODOs" },
    },
  },
}
