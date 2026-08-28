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
      { "<leader>gs", "<cmd>Telescope git_status<cr>", desc = "Git: archivos modificados" },
      { "<leader>gc", "<cmd>Telescope git_commits<cr>", desc = "Git: commits del repo" },
      { "<leader>gb", "<cmd>Telescope git_bcommits<cr>", desc = "Git: commits de este archivo" },
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
        width = 32,
        signcolumn = "no",     -- git y diagnósticos van pegados al nombre, no en columna aparte
        number = true,         -- número absoluto en la línea del cursor
        relativenumber = true, -- números relativos en el resto (para hacer 5j, 3k...)
      },
      renderer = {
        group_empty = true,
        full_name = true,                    -- nombre completo en flotante cuando no cabe
        root_folder_label = false,           -- sin cabecera de ruta: ya sabes dónde estás
        indent_width = 2,
        indent_markers = { enable = false }, -- sin guías └│: la sangría ya marca el nivel
        hidden_display = "simple",           -- "(1 hidden)" bajo la carpeta que filtró algo
        highlight_git = "icon",              -- git colorea SOLO el glifo, no el nombre
        highlight_opened_files = "name",     -- archivo abierto en terracota (ver colorscheme.lua)
        highlight_diagnostics = "icon",      -- colorea el signo de error/warning
        icons = {
          git_placement = "after",
          diagnostics_placement = "after",
          show = { folder_arrow = false },   -- el icono de carpeta ya dice si está abierta
          glyphs = {
            git = {
              unstaged = "●", staged = "●", unmerged = "", renamed = "›",
              untracked = "○", deleted = "✗", ignored = "",
            },
          },
        },
      },
      diagnostics = {
        enable = true,                       -- errores/warnings del LSP dentro del árbol
        icons = { hint = "·", info = "·", warning = "▲", error = "▲" },
      },
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

        -- Copiar rutas del nodo bajo el cursor. `c` pasa a ser prefijo, así que
        -- copiar-archivo (que era `c`) se mueve a `cc`. Los defaults y/Y/gy siguen vivos.
        vim.keymap.del("n", "c", { buffer = bufnr }) -- el default trae nowait: mataría `cr`/`ca`
        local copy = {
          c = { api.fs.copy.node, "Copiar archivo (para pegar con p)" },
          r = { api.fs.copy.relative_path, "Copiar ruta relativa" },
          a = { api.fs.copy.absolute_path, "Copiar ruta absoluta" },
          n = { api.fs.copy.filename, "Copiar nombre del archivo" },
        }
        for key, spec in pairs(copy) do
          local opts = vim.tbl_extend("force", o, { nowait = false, desc = spec[2] })
          vim.keymap.set("n", "c" .. key, spec[1], opts)
          vim.keymap.set("n", "<leader>c" .. key, spec[1], opts) -- mismo atajo que en un archivo
        end

        vim.keymap.set("n", "}", function() jump_open_dir("next") end, vim.tbl_extend("force", o, { desc = "Next open folder" }))
        vim.keymap.set("n", "{", function() jump_open_dir("prev") end, vim.tbl_extend("force", o, { desc = "Prev open folder" }))

        -- Ratón tipo VSCode. Un solo clic:
        --   carpeta -> la abre/cierra
        --   archivo -> lo pinta en el editor pero el foco SE QUEDA en el árbol
        --              (preview), para poder seguir paseando por la lista.
        -- Doble clic en un archivo -> lo abre de verdad y salta a él.
        --
        -- Por qué mapeamos también <LeftMouse> (el press), que parece innecesario:
        -- un doble clic emite <LeftMouse> <LeftRelease> <2-LeftMouse> <LeftRelease>,
        -- pero ese release final NO pasa por los mapeos. El press por defecto es
        -- quien lleva la cuenta de clics, y al llegar ese release suelto Neovim lo
        -- resuelve como "seleccionar palabra" -> te quedabas en modo VISUAL (y con
        -- which-key abierto) tras cada doble clic. Reemplazando el press por un
        -- posicionamiento manual esa máquina de estados nunca arranca: no hay
        -- visual y el cuarto evento ni se emite.
        -- Precio: perdemos arrastrar-para-seleccionar iniciado desde la ventana del
        -- árbol. En el árbol no sirve de nada; empezar el drag ya dentro del código
        -- (que es lo normal) sigue funcionando igual.
        vim.keymap.set({ "n", "x" }, "<LeftMouse>", function()
          local pos = vim.fn.getmousepos()
          if pos.winid == 0 or not vim.api.nvim_win_is_valid(pos.winid) then return end
          if pos.line < 1 then return end -- clic en winbar/statusline, no en texto
          local buf = vim.api.nvim_win_get_buf(pos.winid)
          if pos.line > vim.api.nvim_buf_line_count(buf) then return end
          local text = vim.api.nvim_buf_get_lines(buf, pos.line - 1, pos.line, false)[1] or ""
          vim.api.nvim_set_current_win(pos.winid)
          vim.api.nvim_win_set_cursor(pos.winid, { pos.line, math.min(math.max(pos.column - 1, 0), #text) })
        end, vim.tbl_extend("force", o, { desc = "Clic: mover el cursor" }))

        -- Abrir el archivo y saltar a él. El doble clic termina con un evento de
        -- ratón que Neovim NO entrega a los mapeos, y para entonces ya cambiamos de
        -- ventana: cae en el archivo recién abierto y lo interpreta como arrastre,
        -- dejándote en modo VISUAL (con which-key abriendo su panel encima). Como
        -- el evento no se puede interceptar, se deshace el efecto: si el modo salta
        -- a visual justo después de abrir, salimos. Los 300 ms solo desarman la
        -- guarda: entrar en visual a mano un momento después sigue funcionando.
        local function open_and_focus()
          api.node.open.edit()
          local guard
          guard = vim.api.nvim_create_autocmd("ModeChanged", {
            callback = function()
              if not vim.fn.mode():match("^[vV\22]") then return end
              vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "n", false)
              -- sin desarmar aquí a propósito: un doble clic real suelta varios
              -- eventos de arrastre (temblor de mano) y cada uno vuelve a entrar
              -- en visual. Solo el temporizador de abajo quita la guarda.
            end,
          })
          vim.defer_fn(function() pcall(vim.api.nvim_del_autocmd, guard) end, 300)
        end

        local function click_open(double)
          local ok, node = pcall(api.tree.get_node_under_cursor)
          if not ok or not node then return end
          if node.type == "directory" then
            -- en el doble clic la carpeta ya la abrió/cerró el primer clic
            if not double then api.node.open.edit() end
          elseif node.type == "file" then
            if double then open_and_focus() else api.node.open.preview() end
          end
        end

        vim.keymap.set({ "n", "x" }, "<LeftRelease>", function() click_open(false) end,
          vim.tbl_extend("force", o, { desc = "Clic: abrir carpeta / preview archivo" }))
        vim.keymap.set({ "n", "x" }, "<2-LeftMouse>", function() click_open(true) end,
          vim.tbl_extend("force", o, { desc = "Doble clic: abrir archivo y enfocarlo" }))
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
        map("<leader>hu", gs.undo_stage_hunk, "Git: deshacer stage del hunk")
        map("<leader>hR", gs.reset_buffer, "Git: reset del archivo entero")
        map("<leader>hB", gs.toggle_current_line_blame, "Git: blame inline (toggle)")
        map("<leader>hD", gs.toggle_deleted, "Git: mostrar líneas borradas")
        -- stage/reset por selección visual
        vim.keymap.set("v", "<leader>hs", function() gs.stage_hunk({ vim.fn.line("."), vim.fn.line("v") }) end,
          { buffer = bufnr, desc = "Git: stage selección" })
        vim.keymap.set("v", "<leader>hr", function() gs.reset_hunk({ vim.fn.line("."), vim.fn.line("v") }) end,
          { buffer = bufnr, desc = "Git: reset selección" })
      end,
    },
  },

  -- Diffs visuales side-by-side + historial (usa el :diff nativo, con panel de archivos)
  {
    "sindrets/diffview.nvim",
    cmd = { "DiffviewOpen", "DiffviewFileHistory", "DiffviewClose" },
    opts = {
      enhanced_diff_hl = true, -- resalta la palabra que cambió, no solo la línea
      view = {
        merge_tool = { layout = "diff3_mixed" }, -- en conflictos: local | base+resultado | remoto
      },
    },
    keys = {
      { "<leader>gd", "<cmd>DiffviewOpen<cr>", desc = "Diff: cambios sin commitear" },
      { "<leader>gD", function()
          vim.ui.input({ prompt = "Diff contra (rama/commit): ", default = "main" }, function(ref)
            if ref and ref ~= "" then vim.cmd("DiffviewOpen " .. ref .. "...HEAD") end
          end)
        end, desc = "Diff: contra otra rama" },
      { "<leader>gh", "<cmd>DiffviewFileHistory %<cr>", desc = "Diff: historial de este archivo" },
      { "<leader>gh", "<cmd>'<,'>DiffviewFileHistory<cr>", mode = "v", desc = "Diff: historial de la selección" },
      { "<leader>gH", "<cmd>DiffviewFileHistory<cr>", desc = "Diff: historial del repo" },
      { "<leader>gq", "<cmd>DiffviewClose<cr>", desc = "Diff: cerrar" },
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
