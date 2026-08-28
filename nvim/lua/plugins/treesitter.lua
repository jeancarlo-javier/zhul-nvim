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
    init = function()
      -- Shim Neovim 0.12 -> compatibilidad con nvim-treesitter (master) all=false
      if vim.g.__ts_all_shim then
        return
      end
      vim.g.__ts_all_shim = true

      local query = vim.treesitter.query
      local orig_directive = query.add_directive
      local orig_predicate = query.add_predicate

      local function wrap_legacy(handler, opts)
        if type(opts) == "table" and opts.all == false then
          return function(match, pattern, source, pred, metadata)
            local legacy_match = {}
            for k, v in pairs(match) do
              legacy_match[k] = type(v) == "table" and v[#v] or v
            end
            return handler(legacy_match, pattern, source, pred, metadata)
          end
        end
        return handler
      end

      query.add_directive = function(name, handler, opts)
        return orig_directive(name, wrap_legacy(handler, opts), opts)
      end

      query.add_predicate = function(name, handler, opts)
        return orig_predicate(name, wrap_legacy(handler, opts), opts)
      end
    end,
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
