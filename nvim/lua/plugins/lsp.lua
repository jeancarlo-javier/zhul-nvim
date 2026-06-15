-- lua/plugins/lsp.lua
-- LSP (API nativa de Neovim 0.11), autocompletado (blink.cmp),
-- formateo (conform) y soporte de desarrollo en Lua (lazydev).

return {
  -- Tipos/librerías de Neovim al editar config Lua (reemplaza neodev).
  -- Hace que `vim.*` se resuelva sin necesidad de diagnostics.globals = { "vim" }.
  {
    "folke/lazydev.nvim",
    ft = "lua",
    opts = {
      library = {
        { path = "${3rd}/luv/library", words = { "vim%.uv" } },
      },
    },
  },

  -- Motor de autocompletado moderno (reemplaza nvim-cmp + cmp-* + LuaSnip)
  {
    "saghen/blink.cmp",
    version = "1.*", -- estable; V2 trae cambios incompatibles
    event = "InsertEnter",
    dependencies = { "rafamadriz/friendly-snippets" },
    opts = {
      keymap = {
        preset = "super-tab", -- Tab acepta/expande, Shift-Tab retrocede
        ["<C-space>"] = { "show", "show_documentation", "hide_documentation" },
        ["<C-e>"] = { "cancel", "fallback" },
        ["<C-k>"] = { "show_signature", "hide_signature", "fallback" },
      },
      appearance = { nerd_font_variant = "mono" },
      completion = { documentation = { auto_show = true } },
      sources = {
        default = { "lazydev", "lsp", "path", "snippets", "buffer" },
        providers = {
          lazydev = { name = "LazyDev", module = "lazydev.integrations.blink", score_offset = 100 },
        },
      },
      fuzzy = { implementation = "prefer_rust_with_warning" },
      signature = { enabled = true },
    },
    opts_extend = { "sources.default" },
  },

  -- Formateo (format-on-save). Esto hace lo que el viejo bloque de Prettier
  -- roto intentaba: formatear al guardar, pero bien hecho y multi-lenguaje.
  {
    "stevearc/conform.nvim",
    event = { "BufWritePre" },
    cmd = { "ConformInfo" },
    keys = {
      {
        "<leader>cf",
        function() require("conform").format({ async = true, lsp_format = "fallback" }) end,
        mode = { "n", "v" },
        desc = "Format buffer",
      },
      {
        "<leader>uf",
        function()
          vim.g.disable_autoformat = not vim.g.disable_autoformat
          vim.notify("Format-on-save: " .. (vim.g.disable_autoformat and "OFF" or "ON"))
        end,
        desc = "Toggle format-on-save",
      },
    },
    opts = {
      formatters_by_ft = {
        lua = { "stylua" },
        python = { "ruff_format" },
        javascript = { "prettier" },
        typescript = { "prettier" },
        javascriptreact = { "prettier" },
        typescriptreact = { "prettier" },
        css = { "prettier" },
        html = { "prettier" },
        json = { "prettier" },
        jsonc = { "prettier" },
        yaml = { "prettier" },
        markdown = { "prettier" },
      },
      format_on_save = function(bufnr)
        if vim.g.disable_autoformat or vim.b[bufnr].disable_autoformat then
          return
        end
        return { timeout_ms = 500, lsp_format = "fallback" }
      end,
    },
  },

  -- LSP: Mason instala/activa los servers; Neovim 0.11 los enciende solo.
  {
    "neovim/nvim-lspconfig",
    event = { "BufReadPre", "BufNewFile" },
    dependencies = {
      { "mason-org/mason.nvim", opts = {} },
      "mason-org/mason-lspconfig.nvim",
      -- Auto-instala los formatters que usa conform
      {
        "WhoIsSethDaniel/mason-tool-installer.nvim",
        opts = { ensure_installed = { "stylua", "prettier", "ruff" } },
      },
      "saghen/blink.cmp",
    },
    config = function()
      -- Capabilities de completado para TODOS los servers (blink)
      vim.lsp.config("*", {
        capabilities = require("blink.cmp").get_lsp_capabilities(),
      })

      -- Ajustes específicos por server (se fusionan sobre "*")
      vim.lsp.config("lua_ls", {
        settings = { Lua = { workspace = { checkThirdParty = false } } },
      })

      -- mason-lspconfig 2.x: con automatic_enable (default) llama a
      -- vim.lsp.enable() por cada server instalado. Sin loop manual.
      -- `eslint` = vscode-eslint-language-server (el MISMO motor que la
      -- extensión ESLint de VSCode). Soporta flat config y .eslintrc legacy.
      require("mason-lspconfig").setup({
        ensure_installed = { "lua_ls", "ts_ls", "pyright", "rust_analyzer", "eslint" },
      })

      -- ESLint --fix al guardar (equivale a source.fixAll.eslint de VSCode).
      -- Solo se activa en buffers donde el server eslint realmente se enganchó.
      vim.api.nvim_create_autocmd("LspAttach", {
        group = vim.api.nvim_create_augroup("user_eslint_fix", { clear = true }),
        callback = function(ev)
          local client = vim.lsp.get_client_by_id(ev.data.client_id)
          if client and client.name == "eslint" then
            vim.api.nvim_create_autocmd("BufWritePre", {
              buffer = ev.buf,
              command = "LspEslintFixAll",
            })
          end
        end,
      })

      -- Atajos LSP por buffer (las 0.11 defaults grn/gra/grr/gri/K ya existen)
      vim.api.nvim_create_autocmd("LspAttach", {
        group = vim.api.nvim_create_augroup("user_lsp_attach", { clear = true }),
        callback = function(ev)
          local tb = require("telescope.builtin")
          local map = function(keys, fn, desc)
            vim.keymap.set("n", keys, fn, { buffer = ev.buf, desc = "LSP: " .. desc })
          end
          map("gd", tb.lsp_definitions, "Go to definition")
          map("gr", tb.lsp_references, "References")
          map("gi", tb.lsp_implementations, "Go to implementation")
          map("gD", vim.lsp.buf.declaration, "Go to declaration")
          map("<leader>ds", tb.lsp_document_symbols, "Document symbols")
          map("<leader>rn", vim.lsp.buf.rename, "Rename")
          vim.keymap.set({ "n", "v" }, "<leader>ca", vim.lsp.buf.code_action,
            { buffer = ev.buf, desc = "LSP: Code action" })
        end,
      })
    end,
  },
}
