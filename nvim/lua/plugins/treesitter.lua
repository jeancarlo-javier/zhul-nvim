-- lua/plugins/treesitter.lua
-- Syntax highlighting e indentación con tree-sitter.
-- Nota 2026: branch `master` es estable; `main` es la reescritura aún en
-- estabilización (requiere el CLI tree-sitter). Para un daily-driver usamos master.

return {
  {
    "nvim-treesitter/nvim-treesitter",
    branch = "master",
    lazy = false,
    build = ":TSUpdate",
    main = "nvim-treesitter.configs",
    opts = {
      ensure_installed = {
        "c", "lua", "luadoc", "vim", "vimdoc", "query",
        "python", "rust", "javascript", "typescript", "tsx",
        "html", "css", "json", "jsonc", "yaml",
        "markdown", "markdown_inline", "bash",
      },
      auto_install = true,
      highlight = { enable = true },
      indent = { enable = true },
    },
  },
}
