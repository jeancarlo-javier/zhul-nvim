-- lua/plugins/editor.lua
-- Edición y navegación: telescope, file explorer, git, saltos (flash),
-- lista de diagnósticos (trouble) y text-objects/surround (mini).

return {
  -- Fuzzy finder
  {
    "nvim-telescope/telescope.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
    cmd = "Telescope",
    keys = {
      { "<leader>ff", "<cmd>Telescope find_files<cr>", desc = "Find files" },
      { "<leader>fg", "<cmd>Telescope live_grep<cr>", desc = "Live grep" },
      { "<leader>fb", "<cmd>Telescope buffers<cr>", desc = "Find buffers" },
      { "<leader>fh", "<cmd>Telescope help_tags<cr>", desc = "Help tags" },
      { "<leader>fd", "<cmd>Telescope diagnostics<cr>", desc = "Diagnostics" },
      { "<leader>fr", "<cmd>Telescope resume<cr>", desc = "Resume last search" },
      { "<leader>fo", "<cmd>Telescope oldfiles<cr>", desc = "Recent files" },
    },
    opts = {},
  },

  -- File explorer
  {
    "nvim-tree/nvim-tree.lua",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    lazy = false, -- cargar al inicio para tomar el control de `nvim .` (en vez de netrw)
    keys = {
      { "<leader>ee", "<cmd>NvimTreeToggle<cr>", desc = "Toggle file explorer" },
      { "<leader>ef", "<cmd>NvimTreeFindFileToggle<cr>", desc = "Explorer on current file" },
      { "<leader>ec", "<cmd>NvimTreeCollapse<cr>", desc = "Collapse explorer" },
      { "<leader>er", "<cmd>NvimTreeRefresh<cr>", desc = "Refresh explorer" },
    },
    opts = {
      hijack_netrw = true, -- reemplaza al explorador viejo (netrw)
      hijack_directories = { enable = true, auto_open = true }, -- `nvim .` abre el árbol
      view = {
        width = 30,
        number = true,         -- número absoluto en la línea del cursor
        relativenumber = true, -- números relativos en el resto (para hacer 5j, 3k...)
      },
      renderer = { group_empty = true },
      filters = { dotfiles = false },
      on_attach = function(bufnr)
        local api = require("nvim-tree.api")
        api.config.mappings.default_on_attach(bufnr)

        -- Quita el mapeo por defecto de nvim-tree en <C-]> (CD: "cambiar la raíz a
        -- la carpeta bajo el cursor"). Así <C-]> sigue ciclando entre splits también
        -- desde la barra lateral (cae al mapeo global <C-w>w en vez de re-enraizar).
        pcall(vim.keymap.del, "n", "<C-]>", { buffer = bufnr })

        local function jump_open_dir(direction)
          local current_line = vim.api.nvim_win_get_cursor(0)[1]
          local total_lines = vim.api.nvim_buf_line_count(0)
          local step = direction == "next" and 1 or -1
          local line = current_line + step
          while line >= 1 and line <= total_lines do
            vim.api.nvim_win_set_cursor(0, { line, 0 })
            local ok, node = pcall(api.tree.get_node_under_cursor)
            if ok and node and node.type == "directory" and node.open then
              return
            end
            line = line + step
          end
          vim.api.nvim_win_set_cursor(0, { current_line, 0 })
        end

        local o = { buffer = bufnr, noremap = true, silent = true, nowait = true }
        vim.keymap.set("n", "}", function() jump_open_dir("next") end, vim.tbl_extend("force", o, { desc = "Next open folder" }))
        vim.keymap.set("n", "{", function() jump_open_dir("prev") end, vim.tbl_extend("force", o, { desc = "Prev open folder" }))
      end,
    },
  },

  -- Git signs en el gutter + atajos para hunks
  {
    "lewis6991/gitsigns.nvim",
    event = { "BufReadPre", "BufNewFile" },
    opts = {
      attach_to_untracked = true, -- archivos nuevos (sin trackear) también muestran +líneas
      signs = {
        add = { text = "+" },
        change = { text = "~" },
        delete = { text = "_" },
        topdelete = { text = "‾" },
        changedelete = { text = "~" },
      },
      on_attach = function(bufnr)
        local gs = require("gitsigns")
        local function map(l, r, desc)
          vim.keymap.set("n", l, r, { buffer = bufnr, desc = desc })
        end
        map("]c", function() gs.nav_hunk("next") end, "Git: siguiente cambio")
        map("[c", function() gs.nav_hunk("prev") end, "Git: cambio anterior")
        map("<leader>hs", gs.stage_hunk, "Git: stage hunk")
        map("<leader>hr", gs.reset_hunk, "Git: reset hunk")
        map("<leader>hp", gs.preview_hunk, "Git: preview hunk")
        map("<leader>hb", function() gs.blame_line({ full = true }) end, "Git: blame línea")
        map("<leader>hd", gs.diffthis, "Git: diff del archivo")
      end,
    },
  },

  -- Saltos rápidos por la pantalla (s = flash, S = flash treesitter)
  {
    "folke/flash.nvim",
    event = "VeryLazy",
    opts = {},
    keys = {
      { "s", mode = { "n", "x", "o" }, function() require("flash").jump() end, desc = "Flash" },
      { "S", mode = { "n", "x", "o" }, function() require("flash").treesitter() end, desc = "Flash Treesitter" },
    },
  },

  -- Lista bonita de diagnósticos / referencias
  {
    "folke/trouble.nvim",
    cmd = "Trouble",
    opts = {},
    keys = {
      { "<leader>xx", "<cmd>Trouble diagnostics toggle<cr>", desc = "Diagnostics (Trouble)" },
      { "<leader>xX", "<cmd>Trouble diagnostics toggle filter.buf=0<cr>", desc = "Buffer diagnostics" },
      { "<leader>xs", "<cmd>Trouble symbols toggle<cr>", desc = "Symbols (Trouble)" },
      { "<leader>xq", "<cmd>Trouble qflist toggle<cr>", desc = "Quickfix list (Trouble)" },
    },
  },

  -- mini.nvim: text-objects extra (ai), surround, y autopairs
  {
    "echasnovski/mini.nvim",
    version = false,
    event = "VeryLazy",
    config = function()
      require("mini.ai").setup() -- text-objects extra (ej: ci( cambia dentro de "(")
      -- surround con prefijo "gs" para no chocar con flash (que usa "s")
      require("mini.surround").setup({
        mappings = {
          add = "gsa",
          delete = "gsd",
          find = "gsf",
          find_left = "gsF",
          highlight = "gsh",
          replace = "gsr",
          update_n_lines = "gsn",
        },
      })
      require("mini.pairs").setup() -- autopairs (reemplaza nvim-autopairs)
    end,
  },
}
