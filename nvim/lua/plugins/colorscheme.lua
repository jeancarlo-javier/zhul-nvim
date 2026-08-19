-- lua/plugins/colorscheme.lua
-- Kanagawa "dragon": tinta cálida y desaturada, para que combine con el fondo
-- de Warp (#1b1c17, oliva oscuro) en vez de pelearse con él como hacía el
-- morado/azul frío de Catppuccin Mocha. Fondo transparente: manda el terminal.

return {
  {
    "rebelot/kanagawa.nvim",
    name = "kanagawa",
    priority = 1000, -- cargar antes que el resto para evitar parpadeo de colores
    config = function()
      require("kanagawa").setup({
        theme = "dragon",
        background = { dark = "dragon" },
        transparent = true,    -- hereda el bg (y la imagen) del terminal
        dimInactive = false,
        terminalColors = false, -- los 16 colores ANSI los define Warp, no nvim
        colors = {
          theme = { all = { ui = { bg_gutter = "none" } } }, -- gutter sin bloque de color
        },
        overrides = function(colors)
          local theme = colors.theme
          return {
            -- Sidebar: la jerarquía la da el BRILLO, no el tono.
            -- carpetas claras > archivos apagados > archivo abierto en terracota.
            NvimTreeNormal           = { fg = theme.ui.special, bg = "none" },
            NvimTreeNormalNC         = { fg = theme.ui.special, bg = "none" },
            NvimTreeEndOfBuffer      = { fg = theme.ui.bg, bg = "none" },
            NvimTreeFolderName       = { fg = theme.ui.fg },
            NvimTreeOpenedFolderName = { fg = theme.ui.fg, bold = true },
            NvimTreeEmptyFolderName  = { fg = theme.ui.nontext },
            NvimTreeOpenedFile       = { fg = theme.syn.constant, bold = true },
            NvimTreeIndentMarker     = { fg = theme.ui.nontext },
            NvimTreeWinSeparator     = { fg = theme.ui.bg_p2, bg = "none" },
            NvimTreeCursorLine       = { bg = theme.ui.bg_p1 },

            -- Sin cajas gritonas: bordes y flotantes casi invisibles.
            WinSeparator = { fg = theme.ui.bg_p2, bg = "none" },
            NormalFloat  = { bg = "none" },
            FloatBorder  = { fg = theme.ui.bg_p2, bg = "none" },
            FloatTitle   = { fg = theme.syn.constant, bg = "none" },
            LineNr       = { fg = theme.ui.bg_p2 },      -- números del sidebar, apagados
            CursorLineNr = { fg = theme.syn.constant },  -- solo la línea actual resalta
          }
        end,
      })
      vim.cmd.colorscheme("kanagawa-dragon")
    end,
  },
}
