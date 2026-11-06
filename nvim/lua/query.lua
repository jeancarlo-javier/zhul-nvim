-- ~/.config/nvim/lua/query.lua
-- Ask the AI about a visual selection or, without one, about the whole file; answer in
-- a chat-like modal (`a` = follow-up). Left pane: the selection, then related code the
-- AI points to (read from disk, so it's the real code, never AI-written). Built on lua/ai.lua.
-- When the question asks for an example or how to do something, the AI may also write
-- example code: it goes under the selection, tinted and labeled as an example (`c` copies
-- it). Jev gates that per question, Sonnet decides real code vs example.
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

-- Only sent when Jev says an example may help. The user learns with this modal (asks for
-- examples or how to do something, never to have code written), so examples teach. Jev sees
-- just the question and the selection; Sonnet reads the project, so it decides: real code
-- first, an example only for what doesn't exist yet, or none.
local EXAMPLE_HINT = [[

Esta pregunta puede pedir un ejemplo o que le enseñes cómo hacer algo. Decide con lo que encuentres en el proyecto:
1. Si el proyecto ya tiene código que lo muestra (dónde se usa o se llama, una prueba, algo parecido), enséñalo con @@related: un ejemplo real va antes que uno inventado.
2. Solo si no existe y un ejemplo ayuda a entenderlo, escribe uno nuevo EXACTAMENTE así, nunca con ``` dentro de la respuesta:
@@example <qué muestra, en pocas palabras>
<el código>
@@end
3. Si con explicar basta, no escribas ninguno.
El ejemplo es para aprender, no para pegarlo tal cual: mínimo, centrado en la idea, con un comentario breve en las líneas clave. Máximo 2, de hasta ~30 líneas, en el lenguaje del proyecto salvo que la pregunta pida otro, con los nombres y firmas reales que leíste. El panel de código los muestra marcados como ejemplo: en la respuesta explica la idea paso a paso sin repetir su código, sin aclarar que no editas archivos y sin mencionar estas instrucciones ni los bloques @@.]]

-- Jev's gate: probability that example code would help. Tuned on 71 labeled questions,
-- learning phrasing included (70 right at 0.3-0.6); low cut because Sonnet still drops
-- unneeded examples.
M.min_example = 0.4
local GATE = "Would example code help answer `question`: the user asks for an example, or to learn or be shown how to do something (use, call, test, fix, change, extend, simplify, refactor or translate code, apply a pattern)? No when they ask to understand existing code: what it does, means or why; where or how it is already used, called or defined in the project; whether it is correct, safe or fast; a summary. `code` is what the user selected in the editor (absent: they asked about the whole `file`); `previous_question` is their earlier question in the same chat, if any."

-- cb(true) when the question may need example code; any Jev failure = no (today's behavior).
function M.wants_example(state, cb)
  ai.judge(state, { gate = { type = "noul", instructions = GATE } }, function(ans)
    local p = ans and type(ans.gate) == "table" and tonumber(ans.gate.noul) or 0
    cb(p >= M.min_example)
  end)
end

-- Splits the panel lines out of the answer: "@@related path:a-b reason", "@@note path:line
-- text" and "@@example title" … "@@end" blocks (code the AI wrote, not in the project).
-- Returns answer_lines, related = { { path, a, b, why } }, notes = { { path, line, text } },
-- examples = { { title, lines } }
function M.parse(answer)
  local out, related, notes, examples, ex = {}, {}, {}, {}, nil
  for _, l in ipairs(vim.split(answer, "\n")) do
    -- shortcut: an example missing its @@end runs to the next @@ line or the end of the answer
    if ex and l:match("^%s*@@%a") then ex = nil end -- @@end, or a directive after an unclosed block
    local p, a, b, why = l:match("^%s*@@related%s+(%S+):(%d+)%-(%d+)%s*(.*)$")
    local np, nl, nt = l:match("^%s*@@note%s+(%S+):(%d+)%s+(.+)$")
    local title = l:match("^%s*@@example%f[%A]%s*(.-)%s*$")
    if ex then
      ex.lines[#ex.lines + 1] = l
    elseif title then
      ex = { title = title, lines = {} }
      examples[#examples + 1] = ex
    elseif p then
      related[#related + 1] = { path = p, a = tonumber(a), b = tonumber(b), why = why }
    elseif np then
      notes[#notes + 1] = { path = np, line = tonumber(nl), text = vim.trim(nt) }
    elseif not l:match("^%s*@@end%s*$") then
      -- removed blocks leave runs of blank lines behind: keep one, none at the top
      if vim.trim(l) ~= "" or vim.trim(out[#out] or "") ~= "" then out[#out + 1] = l end
    end
  end
  while #out > 0 and vim.trim(out[#out]) == "" do out[#out] = nil end
  -- models wrap code in ``` even when told not to; drop fences, edge blank lines, empty blocks
  local kept = {}
  for _, e in ipairs(examples) do
    local l = e.lines
    while #l > 0 and (vim.trim(l[1]) == "" or l[1]:match("^%s*```")) do table.remove(l, 1) end
    while #l > 0 and (vim.trim(l[#l]) == "" or l[#l]:match("^%s*```")) do l[#l] = nil end
    if #l > 0 then kept[#kept + 1] = e end
  end
  return out, related, notes, kept
end

-- Example code for the pane, placed under `base_len` fixed lines: lines, and a tint for
-- each of them (header included) so it's never taken for code read from disk.
local function example_lines(examples, base_len)
  local lines, hl = {}, {}
  for _, e in ipairs(examples) do
    if base_len + #lines > 0 then lines[#lines + 1] = "" end
    lines[#lines + 1] = ("── ejemplo · %s · no está en tu código"):format(e.title ~= "" and e.title or "código sugerido")
    hl[#hl + 1] = { base_len + #lines - 1, "DiffAdd" }
    for _, l in ipairs(e.lines) do
      lines[#lines + 1] = l
      hl[#hl + 1] = { base_len + #lines - 1, "DiffAdd" }
    end
  end
  return lines, hl
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
-- answer, not older ones), examples only by newer ones. path/first let notes land on the
-- fixed lines too.
function M.chat(context, default, pane)
  vim.ui.input({ prompt = "Consulta: ", default = default }, function(q)
    if not q or vim.trim(q) == "" then return end
    -- shortcut: related snippets use the selection's highlighting, even from other languages.
    local m = ai.modal(q, {}, pane)
    local function footer(has_example)
      if not vim.api.nvim_win_is_valid(m.win) then return end
      vim.api.nvim_win_set_config(m.win, { footer_pos = "center", footer = has_example
        and " a: repreguntar · c: copiar ejemplo · q: cerrar " or " a: repreguntar · q: cerrar " })
    end
    footer(false)
    local turns, busy, shown = {}, false, {} -- shown = examples in the pane right now

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
        history[#history + 1] = ("Pregunta anterior: %s\nTu respuesta: %s\n"):format(t.q, table.concat(t.a, "\n"))
        for _, e in ipairs(t.examples or {}) do -- so "explícame el ejemplo" works
          history[#history + 1] = ("Tu ejemplo (%s):\n%s\n"):format(e.title, table.concat(e.lines, "\n"))
        end
        history[#history + 1] = "\n"
      end
      local prev = turns[#turns]
      local turn = { q = question }
      turns[#turns + 1] = turn
      busy = true
      local row = render()
      if vim.api.nvim_win_is_valid(m.win) then vim.api.nvim_win_set_cursor(m.win, { row, 0 }) end
      local gate = { question = question, previous_question = prev and prev.q, file = pane.title, language = pane.ft,
        code = #pane.lines > 0 and require("query_kinds").slice(pane.lines, 1, 60, 3000) or nil }
      -- ~0.4s before the answer starts (max ai.judge_timeout); the modal already shows Pensando…
      M.wants_example(gate, function(example)
        local prompt = context .. table.concat(history) .. "Pregunta: " .. question .. PANEL_HINT .. (example and EXAMPLE_HINT or "")
        ai.ask(prompt, function(answer, err)
          busy = false
          if err then
            turn.a = { "**Error:** " .. err }
          else
            local out, related, notes, examples = M.parse(answer)
            turn.a, turn.examples = out, examples
            local rows = {}
            if pane.path and pane.path ~= "" then
              for i = 0, #pane.lines - 1 do rows[key(pane.path, pane.first + i)] = i end
            end
            -- the last example stays until a new one replaces it: follow-ups often ask about it,
            -- and Jev rightly sees "explain the example" as no-new-code, so it wouldn't come back
            local new = #examples > 0
            if new then shown = examples end
            -- examples right under the selection: they answer the question, related code is reference
            local extra, hl = example_lines(shown, #pane.lines)
            vim.list_extend(extra, snippets(related, #pane.lines + #extra, rows))
            m.set_ctx_extra(extra, place(notes, rows), hl) -- errors keep the previous turn's code
            -- a long selection pushes a new example out of view: bring it up
            if new and m.ctx_win and vim.api.nvim_win_is_valid(m.ctx_win) then
              vim.api.nvim_win_call(m.ctx_win, function()
                if vim.fn.line("w$") < math.min(hl[#hl][1], hl[1][1] + 5) + 1 then
                  -- the cursor moves too, or Neovim scrolls back to where it was
                  vim.fn.winrestview({ topline = hl[1][1] + 1, lnum = hl[1][1] + 1, col = 0 })
                end
              end)
            end
            footer(#shown > 0)
          end
          render()
        end)
      end)
    end

    vim.keymap.set("n", "c", function()
      if #shown == 0 then return vim.notify("Consulta: no hay código de ejemplo en el panel") end
      local l = {}
      for i, e in ipairs(shown) do
        if i > 1 then l[#l + 1] = "" end
        vim.list_extend(l, e.lines)
      end
      vim.fn.setreg(vim.v.register, l, "l") -- v:register follows 'clipboard' and a "x prefix
      vim.notify(("Consulta: ejemplo copiado (%d línea%s)"):format(#l, #l == 1 and "" or "s"))
    end, { buffer = m.buf, nowait = true, desc = "Copiar el código de ejemplo" })

    vim.keymap.set("n", "a", function()
      if busy then return vim.notify("Consulta: espera la respuesta en curso", vim.log.levels.WARN) end
      -- docked at the bottom of the answer pane, full width, like Telescope's prompt (snacks.input)
      local ww, wh = vim.api.nvim_win_get_width(m.win), vim.api.nvim_win_get_height(m.win)
      local input = vim.ui.input({ prompt = "Repregunta", win = { relative = "win", win = m.win,
        row = wh - 3, col = 0, width = ww - 2 } }, function(fq)
        if fq and vim.trim(fq) ~= "" then send(fq) end
      end)
      -- docked to the modal: it goes when the modal does, or it's left floating over the editor
      if type(input) == "table" and input.close then
        vim.api.nvim_create_autocmd("WinClosed", { pattern = tostring(m.win), once = true, callback = function()
          vim.schedule(function() if input:valid() then input:close() end end)
        end })
      end
    end, { buffer = m.buf, nowait = true, desc = "Repreguntar sobre este código" })

    send(q)
  end)
  -- prefilled → start in normal mode (Enter sends, edit with c/w/A...); empty → stay in insert.
  -- The input always starts insert, so undo it once it has.
  if default ~= "" then vim.schedule(function() vim.cmd.stopinsert() end) end
end

return M
