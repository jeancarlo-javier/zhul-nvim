-- lua/plugins/ui.lua
-- Interfaz: statusline, hints de atajos, y mejoras de calidad de vida (snacks).

-- b:tab_order = position in the tab bar (see bufferline's sort_by); a b: var so a preview
-- replacing another can take its slot (lua/config.lua), and :bdelete clears it
local next_tab = 0

return {
  -- Statusline
  {
    "nvim-lualine/lualine.nvim",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    event = "VeryLazy",
    opts = {
      options = {
        theme = "auto", -- toma los colores del colorscheme activo (kanagawa)
        globalstatus = true, -- una sola statusline para todas las ventanas (0.7+)
        section_separators = "",
        component_separators = "|",
      },
      -- empty editor after closing every tab: no "[No Name]" label
      sections = { lualine_c = { { "filename", symbols = { unnamed = "" } } } },
    },
  },

  -- Tabs de archivos (buffers) arriba, con "x" clickeable para cerrar
  {
    "akinsho/bufferline.nvim",
    version = "*",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    event = "VeryLazy",
    init = function() -- at startup, so files opened before bufferline loads are counted too
      local grp = vim.api.nvim_create_augroup("tab_order", { clear = true })
      vim.api.nvim_create_autocmd("BufAdd", { -- also fires when a closed buffer is relisted
        group = grp,
        callback = function(ev)
          if vim.b[ev.buf].tab_order then return end -- a rename (:saveas) keeps the tab in place
          next_tab = next_tab + 1
          vim.b[ev.buf].tab_order = next_tab
        end,
      })

      -- Drag a file tab onto another to move it there (bufferline has no drag). The press
      -- column comes from on_key: a <LeftMouse> map would be shadowed by nvim-tree's
      -- buffer-local one. Same column math as bufferline's hover (ui.on_hover_over).
      local press_col
      local function tab_at(col)
        local state = require("bufferline.state")
        local pos = state.left_offset_size
        if col <= pos then return end
        for _, item in ipairs(state.visible_components) do
          pos = pos + item.length
          if col <= pos then return item.id end
        end
      end
      local left_mouse = vim.keycode("<LeftMouse>")
      vim.on_key(function(_, typed)
        if typed == left_mouse then
          local p = vim.fn.getmousepos()
          press_col = p.screenrow == 1 and p.screencol or nil
        end
      end, vim.api.nvim_create_namespace("tab_drag"))
      -- true when the release ended a tab drag (nvim-tree's own <LeftRelease> asks first)
      _G.tab_drag_release = function()
        local p, col = vim.fn.getmousepos(), press_col
        press_col = nil
        if not col or p.screenrow ~= 1 or not package.loaded["bufferline"] then return false end
        local from, to = tab_at(col), tab_at(p.screencol)
        if not from or not to or from == to then return false end
        local ids = vim.tbl_map(function(e) return e.id end, require("bufferline").get_elements().elements)
        local f, t = vim.fn.index(ids, from) + 1, vim.fn.index(ids, to) + 1
        table.insert(ids, t, table.remove(ids, f)) -- right of where it was: lands after `to`
        for i, id in ipairs(ids) do vim.b[id].tab_order = i end
        require("bufferline.ui").refresh()
        return true
      end
      vim.keymap.set({ "n", "x" }, "<LeftRelease>", function()
        if not tab_drag_release() then vim.api.nvim_feedkeys(vim.keycode("<LeftRelease>"), "ni", false) end
      end, { desc = "Drag a tab to reorder" })
    end,
    config = function(_, opts)
      require("bufferline").setup(opts)
      -- Only the selected tab gets a line, on its left edge: separators become spaces (same
      -- width, so click areas don't shift) and the selected indicator (▎, near-invisible in
      -- this colorscheme) is drawn as a separator. bufferline has no per-tab separator option.
      local render = _G.nvim_bufferline
      _G.nvim_bufferline = function()
        local s = render():gsub("(%%#BufferLineSeparator#)([^%%]*)", function(hl, sep)
          return hl .. (" "):rep(vim.fn.strwidth(sep))
        end)
        return (s:gsub("%%#BufferLineIndicatorSelected#[^%%]*", "%%#BufferLineSeparator#▏"))
      end
    end,
    opts = {
      options = {
        -- Snacks.bufdelete cierra el buffer sin romper el layout de ventanas
        close_command = function(n) Snacks.bufdelete(n) end,
        right_mouse_command = function(n) Snacks.bufdelete(n) end,
        -- no tab for the empty [No Name] left after closing the last one (VSCode's empty
        -- editor); clicking it from the tree would also open it in the tree's window
        custom_filter = function(b)
          if vim.b[b].diffview then return false end -- a Diffview pane's file, not a tab
          -- inside a Diffview only the tab numbers show: a file tab clicked there opens in a diff pane
          if package.loaded["diffview.lib"] and require("diffview.lib").get_current_view() then return false end
          return vim.api.nvim_buf_get_name(b) ~= "" or vim.bo[b].modified
        end,
        -- new tabs go on the right, in the order they were opened. By id (default) or
        -- "insert_at_end" (by id after one redraw), a reopened file keeps its old buffer
        -- number and jumped back to the left.
        sort_by = function(a, b)
          local oa, ob = vim.b[a.id].tab_order or 0, vim.b[b.id].tab_order or 0
          if oa ~= ob then return oa < ob end
          return a.id < b.id
        end,
        show_buffer_close_icons = true,
        -- the default icon (󰅖, Nerd Font v3) may not render in the terminal font; ASCII always does
        buffer_close_icon = "x",
        diagnostics = "nvim_lsp",
        offsets = {
          { filetype = "NvimTree", text = "Explorer", separator = true },
          { filetype = "DiffviewFiles", text = "Source Control", separator = true },
          { filetype = "DiffviewFileHistory", text = "File History", separator = true },
        },
      },
    },
  },

  -- Hints de atajos (which-key v3)
  {
    "folke/which-key.nvim",
    event = "VeryLazy",
    opts = {
      spec = {
        { "<leader>f", group = "buscar / find" },   -- <space>f + f/a/F/g/b/h/d/r/o/t
        { "<leader>e", group = "explorador" },       -- <space>e + e/f/c/C/r (nvim-tree)
        { "<leader>m", group = "mover líneas" },     -- <space>m + j/k (con N opcional)
        { "<leader>l", group = "líneas" },           -- <space>ll = toggle wrap
        { "<leader>g", group = "git / diffs" },       -- <space>g + d/D/h/H/s/c/b/q
        { "<leader>h", group = "git hunks" },         -- <space>h + s/r/p/b/d... (gitsigns)
        { "<leader>c", group = "copiar ruta" },       -- <space>c + r/a/n
        { "<leader>s", group = "splits / ventanas" }, -- <space>s + v/h/e/x
        { "<leader>t", group = "pestañas / traducir"},-- <space>t + o/x/n/p / t/w/s/e/l
        { "<leader>u", group = "ui / toggles" },     -- <space>u + n
      },
    },
  },

  -- Quality of life de folke: bigfile, indent guides, notifier, statuscolumn, etc.
  {
    "folke/snacks.nvim",
    priority = 1000,
    lazy = false,
    opts = {
      bigfile = { enabled = true },     -- desactiva features pesadas en archivos enormes
      quickfile = { enabled = true },   -- arranque más rápido al abrir un archivo directo
      -- guías de indentación; underline en el scope actual como señal extra
      -- (no depende solo del color, más accesible para daltonismo/bajo contraste)
      indent = { enabled = true, scope = { underline = true } },
      notifier = { enabled = true },    -- reemplaza vim.notify con notificaciones bonitas
      statuscolumn = { enabled = true },-- columna de números/signos/folds unificada
      scope = { enabled = true },       -- chunk scope (minimap del bloque lógico)
      words = { enabled = true },       -- resalta la palabra bajo el cursor (LSP references)
      input = { enabled = true },       -- reemplaza vim.ui.input
      -- Preview de imágenes APAGADO a propósito: en Warp (kitty graphics a medias) las
      -- imágenes salían gigantes, descuadradas y sin borrarse. Se hará de otra forma.
      -- Abrir un archivo de imagen lo maneja Quick Look (ver lua/config.lua).
      image = { enabled = false },
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
