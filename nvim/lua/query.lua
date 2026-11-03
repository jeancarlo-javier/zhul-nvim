-- ~/.config/nvim/lua/query.lua
-- Ask the AI about the current line or a visual selection; answer in a modal.
-- Left pane: the selection, then related code the AI points to (read from disk,
-- so it's the real code, never AI-written). Built on lua/ai.lua.
--
-- API:
--   require("query").ask_range(l1, l2)  -- prompts for a question about lines l1..l2

local ai = require("ai")
local M = {}

M.default_question = "¿De qué trata esto?"
M.max_related_lines = 40 -- per snippet, keeps the left pane readable

local RELATED_HINT = [[

Al final, si ayuda a entender el código, añade hasta 3 ubicaciones de código relacionado o útil (definiciones que usa, quién lo llama, config que lo afecta), una por línea y EXACTAMENTE así:
@@related <ruta absoluta>:<línea inicio>-<línea fin> <motivo en pocas palabras>
Solo ubicaciones que hayas leído y verificado; no busques de más solo para esto. Si no hay nada útil, omítelas.]]

-- Splits "@@related path:a-b reason" lines out of the answer.
-- Returns answer_lines, related = { { path, a, b, reason }, ... }
function M.parse(answer)
  local out, related = {}, {}
  for _, l in ipairs(vim.split(answer, "\n")) do
    local p, a, b, why = l:match("^%s*@@related%s+(%S+):(%d+)%-(%d+)%s*(.*)$")
    if p then
      related[#related + 1] = { path = p, a = tonumber(a), b = tonumber(b), why = why }
    else
      out[#out + 1] = l
    end
  end
  while #out > 0 and vim.trim(out[#out]) == "" do out[#out] = nil end
  return out, related
end

-- Real lines from disk for each related location; skips unreadable ones.
local function snippets(related)
  local lines = {}
  for _, r in ipairs(related) do
    local ok, file = pcall(vim.fn.readfile, r.path)
    if ok and #file > 0 and r.a <= #file then
      local b = math.min(r.b, #file, r.a + M.max_related_lines - 1)
      vim.list_extend(lines, { "", ("── %s:%d-%d · %s"):format(vim.fn.fnamemodify(r.path, ":~:."), r.a, b, r.why) })
      vim.list_extend(lines, vim.list_slice(file, r.a, b))
    end
  end
  return lines
end

function M.ask_range(l1, l2)
  local sel = vim.api.nvim_buf_get_lines(0, l1 - 1, l2, false)
  local text = table.concat(sel, "\n")
  local file = vim.fn.expand("%:p")
  local ft = vim.bo.filetype
  vim.ui.input({ prompt = "Consulta: ", default = M.default_question }, function(q)
    if not q or vim.trim(q) == "" then return end
    local prompt = ("Archivo: %s (líneas %d-%d). Puedes leerlo si necesitas más contexto.\n\n```%s\n%s\n```\n\nPregunta: %s%s")
      :format(file ~= "" and file or "[sin nombre]", l1, l2, ft, text, q, RELATED_HINT)
    -- shortcut: related snippets use the selection's highlighting, even from other languages.
    local m = ai.modal(q, { "_Pensando…_" },
      { lines = sel, ft = ft, title = ("%s:%d-%d"):format(vim.fn.expand("%:t"), l1, l2) })
    ai.ask(prompt, function(answer, err)
      if err then return m.set({ "**Error:** " .. err }) end
      local out, related = M.parse(answer)
      m.set(out)
      m.append_ctx(snippets(related))
    end)
  end)
end

return M
