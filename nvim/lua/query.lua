-- ~/.config/nvim/lua/query.lua
-- Ask the AI about the current line or a visual selection; answer in a modal.
-- Built on lua/ai.lua (the reusable connection + modal).
--
-- API:
--   require("query").ask_range(l1, l2)  -- prompts for a question about lines l1..l2

local ai = require("ai")
local M = {}

M.default_question = "¿De qué trata esto?"

function M.ask_range(l1, l2)
  local sel = vim.api.nvim_buf_get_lines(0, l1 - 1, l2, false)
  local text = table.concat(sel, "\n")
  local file = vim.fn.expand("%:p")
  local ft = vim.bo.filetype
  vim.ui.input({ prompt = "Consulta: ", default = M.default_question }, function(q)
    if not q or vim.trim(q) == "" then return end
    local prompt = ("Archivo: %s (líneas %d-%d). Puedes leerlo si necesitas más contexto.\n\n```%s\n%s\n```\n\nPregunta: %s")
      :format(file ~= "" and file or "[sin nombre]", l1, l2, ft, text, q)
    local m = ai.modal(q, { "_Pensando…_" },
      { lines = sel, ft = ft, title = ("%s:%d-%d"):format(vim.fn.expand("%:t"), l1, l2) })
    ai.ask(prompt, function(answer, err)
      m.set(vim.split(err and ("**Error:** " .. err) or answer, "\n"))
    end)
  end)
end

return M
