-- ~/.config/nvim/lua/query.lua
-- Ask the AI about a visual selection or, without one, about the whole file; answer in
-- a chat-like modal (`a` = follow-up). Left pane: the selection, then related code the
-- AI points to (read from disk, so it's the real code, never AI-written). Built on lua/ai.lua.
--
-- API:
--   require("query").ask_range(l1, l2)  -- question about lines l1..l2 (prefilled to fit the code, see query_kinds)
--   require("query").ask_file()         -- free question about the current file (empty input)

local ai = require("ai")
local M = {}

M.max_related_lines = 40 -- per snippet, keeps the left pane readable

local PANEL_HINT = [[

Termina SIEMPRE la respuesta con un bloque para el panel de código (la selección ya se muestra), una línea por elemento y EXACTAMENTE en estos formatos:
@@related <ruta absoluta>:<línea inicio>-<línea fin> <motivo en pocas palabras>
@@note <ruta absoluta>:<línea> <nota breve, máximo 60 caracteres>
Reglas:
1. OBLIGATORIO: si la pregunta trata de un código que no está en la selección (una función, variable o tipo que nombra), el PRIMER @@related es ese código, completo.
2. Después, hasta 2 @@related más con lo relacionado: definiciones que usa, quién lo llama, config que lo afecta.
3. Hasta 5 @@note sobre líneas clave de la selección o de esas ubicaciones: lo que no es obvio leyendo el código. Se muestran encima de la línea, como un comentario.
Solo ubicaciones y líneas que hayas leído y verificado. Las reglas 2 y 3 son opcionales: no busques de más solo para ellas.
Responde y escribe las notas en el idioma de la pregunta, aunque el código esté en otro.]]

-- Splits "@@related path:a-b reason" and "@@note path:line text" lines out of the answer.
-- Returns answer_lines, related = { { path, a, b, why } }, notes = { { path, line, text } }
function M.parse(answer)
  local out, related, notes = {}, {}, {}
  for _, l in ipairs(vim.split(answer, "\n")) do
    local p, a, b, why = l:match("^%s*@@related%s+(%S+):(%d+)%-(%d+)%s*(.*)$")
    local np, nl, nt = l:match("^%s*@@note%s+(%S+):(%d+)%s+(.+)$")
    if p then
      related[#related + 1] = { path = p, a = tonumber(a), b = tonumber(b), why = why }
    elseif np then
      notes[#notes + 1] = { path = np, line = tonumber(nl), text = vim.trim(nt) }
    else
      out[#out + 1] = l
    end
  end
  while #out > 0 and vim.trim(out[#out]) == "" do out[#out] = nil end
  return out, related, notes
end

-- "path:line" key, resolved so symlinked paths (~/.config/nvim → repo) still match.
local function key(path, line)
  return vim.fn.resolve(vim.fn.fnamemodify(path, ":p")) .. ":" .. line
end

-- Real lines from disk for each related location (unreadable ones skipped), placed under
-- `base_len` fixed pane lines. `rows` maps key(path, line) → 0-based pane row; it gets the
-- snippet rows added (existing entries, e.g. the selection, win).
local function snippets(related, base_len, rows)
  local lines = {}
  for _, r in ipairs(related) do
    local ok, file = pcall(vim.fn.readfile, r.path)
    if ok and #file > 0 and r.a <= #file then
      local b = math.min(r.b, #file, r.a + M.max_related_lines - 1)
      if base_len + #lines > 0 then lines[#lines + 1] = "" end -- separator, not at the very top
      lines[#lines + 1] = ("── %s:%d-%d · %s"):format(vim.fn.fnamemodify(r.path, ":~:."), r.a, b, r.why)
      for n = r.a, b do
        local k = key(r.path, n)
        if rows[k] == nil then rows[k] = base_len + #lines end
        lines[#lines + 1] = file[n]
      end
    end
  end
  return lines
end

-- Notes whose line is visible in the pane, as { row, text }; the rest are dropped.
local function place(notes, rows)
  local out = {}
  for _, n in ipairs(notes) do
    local row = rows[key(n.path, n.line)]
    if row then out[#out + 1] = { row = row, text = n.text } end
  end
  return out
end

-- Question about the selection (lines l1..l2): code goes in the prompt and the left pane.
-- `frag` = exact text of a charwise selection; ignored when it is the whole lines anyway.
function M.ask_range(l1, l2, frag)
  local sel = vim.api.nvim_buf_get_lines(0, l1 - 1, l2, false)
  if frag and vim.trim(frag) == vim.trim(table.concat(sel, "\n")) then frag = nil end
  local file = vim.fn.expand("%:p")
  local ft = vim.bo.filetype
  local context = ("Archivo: %s (líneas %d-%d). Puedes leerlo si necesitas más contexto.\n\n```%s\n%s\n```\n\n")
    :format(file ~= "" and file or "[sin nombre]", l1, l2, ft, table.concat(sel, "\n"))
  if frag then context = context .. ("Seleccionado dentro de esas líneas: `%s`\n\n"):format(vim.trim(frag)) end
  -- everything read now: the buffer may change while the default question is picked
  local pane = { lines = sel, ft = ft, title = ("%s:%d-%d"):format(vim.fn.expand("%:t"), l1, l2), path = file, first = l1 }
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  require("query_kinds").pick({ file = file, ft = ft, lines = lines, l1 = l1, l2 = l2, frag = frag }, function(question)
    M.chat(context, question, pane)
  end)
end

-- Free question about the whole file (no selection). The AI reads it from disk; the left
-- pane starts empty and fills with related code.
-- shortcut: unsaved edits aren't seen (AI reads disk), send the buffer if that bites.
function M.ask_file()
  local file = vim.fn.expand("%:p")
  local ft = vim.bo.filetype
  local context
  if file ~= "" and vim.fn.filereadable(file) == 1 then
    context = ("Archivo: %s. Pregunta general sobre este archivo; léelo para responder.\n\n"):format(file)
  else -- unnamed/unsaved buffer: nothing on disk to read, so send its content
    context = ("Buffer sin guardar (%s):\n\n```%s\n%s\n```\n\n")
      :format(ft, ft, table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n"))
  end
  M.chat(context, "", { lines = {}, ft = ft, title = vim.fn.expand("%:t") ~= "" and vim.fn.expand("%:t") or "[sin nombre]" })
end

-- Chat modal: asks q (input prefilled with `default`), then `a` for follow-ups.
-- `pane` is the left pane ({ lines, ft, title, path?, first? }): its lines stay fixed; the
-- related code under them and all notes are replaced each turn (they explain the current
-- answer, not older ones). path/first let notes land on the fixed lines too.
function M.chat(context, default, pane)
  vim.ui.input({ prompt = "Consulta: ", default = default }, function(q)
    if not q or vim.trim(q) == "" then return end
    -- shortcut: related snippets use the selection's highlighting, even from other languages.
    local m = ai.modal(q, {}, pane)
    vim.api.nvim_win_set_config(m.win, { footer = " a: repreguntar · q: cerrar ", footer_pos = "center" })
    local turns, busy = {}, false

    -- Whole transcript; later turns get their question as a header. Returns the last turn's first row.
    local function render()
      local lines, head = {}, 1
      for i, t in ipairs(turns) do
        if i > 1 then
          vim.list_extend(lines, { "", "---", "" })
          head = #lines + 1
          vim.list_extend(lines, { "**" .. t.q .. "**", "" })
        end
        vim.list_extend(lines, t.a or { "_Pensando…_" })
      end
      m.set(lines)
      return head
    end

    local function send(question)
      -- cs -q keeps no session, so earlier turns ride along in the prompt.
      local history = {}
      for _, t in ipairs(turns) do
        history[#history + 1] = ("Pregunta anterior: %s\nTu respuesta: %s\n\n"):format(t.q, table.concat(t.a, "\n"))
      end
      local turn = { q = question }
      turns[#turns + 1] = turn
      busy = true
      local row = render()
      if vim.api.nvim_win_is_valid(m.win) then vim.api.nvim_win_set_cursor(m.win, { row, 0 }) end
      ai.ask(context .. table.concat(history) .. "Pregunta: " .. question .. PANEL_HINT, function(answer, err)
        busy = false
        if err then
          turn.a = { "**Error:** " .. err }
        else
          local out, related, notes = M.parse(answer)
          turn.a = out
          local rows = {}
          if pane.path and pane.path ~= "" then
            for i = 0, #pane.lines - 1 do rows[key(pane.path, pane.first + i)] = i end
          end
          local extra = snippets(related, #pane.lines, rows)
          m.set_ctx_extra(extra, place(notes, rows)) -- errors keep the previous turn's code
        end
        render()
      end)
    end

    vim.keymap.set("n", "a", function()
      if busy then return vim.notify("Consulta: espera la respuesta en curso", vim.log.levels.WARN) end
      vim.ui.input({ prompt = "Repregunta: " }, function(fq)
        if fq and vim.trim(fq) ~= "" then send(fq) end
      end)
    end, { buffer = m.buf, nowait = true, desc = "Repreguntar sobre este código" })

    send(q)
  end)
  -- prefilled → start in normal mode (Enter sends, edit with c/w/A...); empty → stay in insert.
  -- The input always starts insert, so undo it once it has.
  if default ~= "" then vim.schedule(function() vim.cmd.stopinsert() end) end
end

return M
