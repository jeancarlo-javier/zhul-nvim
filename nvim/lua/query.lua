-- ~/.config/nvim/lua/query.lua
-- One modal to ask about, or edit, a visual selection or, without one, the whole file.
-- `a` asks (cs -q, read-only, chat-like); `e` asks for a change (cs -e): the left pane shows
-- the diff and `y` applies it to the buffer. Both share the chat as context.
-- Left pane: the selection, then related code the AI points to (read from disk, so it's the
-- real code, never AI-written), an example, or the proposed diff. Built on lua/ai.lua and lua/edit.lua.
-- When the question asks for an example or how to do something, the AI may also write
-- example code: it goes under the selection, tinted and labeled as an example (`c` copies
-- it). Jev gates that per question, Sonnet decides real code vs example.
--
-- API:
--   require("query").ask_range(l1, l2, frag?)  -- modal on lines l1..l2 (`a` prefilled to fit the code, see query_kinds)
--   require("query").ask_file()                -- modal on the current file (empty input)

local ai = require("ai")
local edit_mod = require("edit")
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

-- Answers never send the user elsewhere for edits: the modal makes them (`e`, or Auto).
local ASK_HINT = [[

Si la pregunta pide cambiar el código, no digas que no puedes editar ni menciones cs -p: explica qué cambiarías; el usuario lo recibe como cambio aplicable si lo pide con la tecla e.]]
-- In a mix, the change goes to cs -e in parallel and shows as a diff: the answer only talks.
local MIX_HINT = [[

En paralelo se le propone el cambio concreto como un diff, a la izquierda, que el usuario aplica o no: responde y recomienda en el chat sin escribir el código del cambio, sin decir que no puedes editar y sin mencionar estas instrucciones. Responde en el idioma de la pregunta.]]

-- Jev's gate: probability that example code would help. Tuned on 71 labeled questions,
-- learning phrasing included (70 right at 0.3-0.6); low cut because Sonnet still drops
-- unneeded examples.
M.min_example = 0.4
M.GATE = "Would example code help answer `question`: the user asks for an example, or to learn or be shown how to do something (use, call, test, fix, change, extend, simplify, refactor or translate code, apply a pattern)? No when they ask to understand existing code: what it does, means or why; where or how it is already used, called or defined in the project; whether it is correct, safe or fast; a summary. `code` is what the user selected in the editor (absent: they asked about the whole `file`); `previous_question` is their earlier question in the same chat, if any."

-- Jev's route for what's typed in Auto mode: does the user want the code changed now (→ cs -e,
-- a diff to approve) or an answer (→ cs -q)? Asked as a question and its inverse in the same
-- request as the example gate (parallel, ~0.4s total), averaged: steadier than either alone.
-- In between it's a mix: the answer plus a proposed change to take or leave.
-- Tuned with tests/query_route_eval.lua.
M.min_mix, M.min_edit, M.min_fix = 0.45, 0.6, 0.7
local SETTING = "`question` is what the user just typed in the assistant of their code editor, about `code` (their selection; absent: the whole `file`). The assistant either answers in a chat (explains, reviews, gives its opinion, teaches with example code) or writes an edit to this file, which the user reviews as a diff before it is applied. `previous_question` and `previous_turn` describe the exchange just before, if any."
local CHANGE = "Change it: they tell or ask the assistant to modify the code (add, remove, rename, fix, refactor, rewrite, complete, format, translate or improve it), politely or as a question ('¿me lo corriges?', 'agrégale un log'), or to carry out what the previous answer suggested ('dale', 'procede'), or they adjust or redo a change that was just proposed or applied."
local ANSWER = "Answer it: they want text back, not edited code: to understand or judge the code (what it does or means, why, where it is used, whether it is correct, safe or fast; a summary, an explanation or a list), the assistant's opinion or suggestions on what could change, to learn how to do something themselves (how to do it, an example, a walkthrough), or to understand a change or example already shown. Verbs like summarize, explain, list or compare ask for text, not for a change."
M.ROUTE = {
  route_edit = { type = "noul", instructions = "Does the user want the assistant to change their code now? " .. SETTING,
    criteria = { ["true"] = CHANGE, ["false"] = ANSWER } },
  route_answer = { type = "noul", instructions = "Does the user want an answer in the chat rather than their code changed? " .. SETTING,
    criteria = { ["true"] = ANSWER, ["false"] = CHANGE } },
  -- what kind of answer: only "review" asks for a fix to take or leave next to it (mix)
  route_kind = { type = "choice", instructions = "If the assistant answers in the chat, what kind of answer does `question` ask for? " .. SETTING,
    criteria = {
      { "understand", "Understand: what the code does or means, why it is so, where it is used, a summary, or an explanation of a change or example already shown." },
      { "learn", "Learn: how to do something themselves, to then write it on their own: how to do it, how the assistant would go about it, an example or a walkthrough." },
      { "review", "Review: whether the code is right, complete, safe, fast or idiomatic, why it fails or what happens in a bad case, how it could be better or what the assistant would change; a good answer ends in a concrete fix or improvement." },
    } },
}

-- With a change waiting in the diff, typed text may just settle it: approve = same as `y`,
-- reject = drop it; both without calling a model. Only read when a proposal is pending.
M.min_settle = 0.8
M.PENDING = { type = "choice",
  instructions = "The assistant just proposed a change to the user's code: `previous_question` asked for it and it is shown as a diff waiting for the user's approval. What does `question`, the user's reply, do with that proposal?",
  criteria = {
    { "approve", "Only accepts it as it is: agrees, or says to go ahead or apply it ('dale', 'va', 'sale'), asking for nothing new or different." },
    { "reject", "Only drops it: says no, cancel, forget it or leave the code as it was, asking for nothing new." },
    { "other", "Anything else: asks for a different or adjusted change, adds a requirement, or asks a question about the change or the code." },
  } }
function M.settle(ans)
  local a = ans and ans.pending
  local pr = a and type(a.probabilities) == "table" and a.probabilities
  if not pr then return nil end
  for _, k in ipairs({ "approve", "reject" }) do
    if (tonumber(pr[k]) or 0) >= M.min_settle then return k end
  end
end

-- Probability of "change it" from Jev's answers (nil if either is missing), and its route.
function M.route_p(ans)
  local function n(k) return ans and type(ans[k]) == "table" and tonumber(ans[k].noul) end
  local e, a = n("route_edit"), n("route_answer")
  return e and a and (e + 1 - a) / 2
end
-- Probability that the question reviews the code (an answer that ends in a fix), from route_kind.
function M.fix_p(ans)
  local a = ans and ans.route_kind
  return a and type(a.probabilities) == "table" and tonumber(a.probabilities.review)
end
-- answer | mix | edit. p = M.route_p, f = M.fix_p; t = thresholds { mix, edit, fix } (default M.*).
-- Mix = an answer plus a change offered next to it: when unsure between the two, or when the
-- question reviews the code (a good answer ends in a fix). Learning how gets an example to
-- write, not a diff (route_kind "learn"). Jev failing = answer, as before routing.
function M.route(p, f, t)
  t = t or { mix = M.min_mix, edit = M.min_edit, fix = M.min_fix }
  if not p then return "answer" end
  if p >= t.edit then return "edit" end
  if p >= t.mix or (f or 0) >= t.fix then return "mix" end
  return "answer"
end

-- The state both Jev questions read. s = { question, file, language, lines?, prev? = { q, kind } };
-- kind: "answer" | "answer with example code" | "proposed change" | "applied change".
function M.route_state(s)
  return { question = s.question, previous_question = s.prev and s.prev.q, previous_turn = s.prev and s.prev.kind,
    file = s.file, language = s.language,
    code = s.lines and #s.lines > 0 and require("query_kinds").slice(s.lines, 1, 60, 3000) or nil }
end

-- cb(true) when the question may need example code; any Jev failure = no (today's behavior).
function M.wants_example(state, cb)
  ai.judge(state, { gate = { type = "noul", instructions = M.GATE } }, function(ans)
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
-- snippet rows added (existing entries, e.g. the selection, win). Also returns lnum spans.
local function snippets(related, base_len, rows)
  local lines, spans = {}, {}
  for _, r in ipairs(related) do
    local ok, file = pcall(vim.fn.readfile, r.path)
    local a = math.max(r.a, 1) -- the AI may answer 0-based
    local b = ok and math.min(r.b, #file, a + M.max_related_lines - 1) or 0
    if b >= a then
      if base_len + #lines > 0 then lines[#lines + 1] = "" end -- separator, not at the very top
      lines[#lines + 1] = ("── %s:%d-%d · %s"):format(vim.fn.fnamemodify(r.path, ":~:."), a, b, r.why)
      spans[#spans + 1] = { base_len + #lines, a, b - a + 1 }
      for n = a, b do
        local k = key(r.path, n)
        if rows[k] == nil then rows[k] = base_len + #lines end
        lines[#lines + 1] = file[n]
      end
    end
  end
  return lines, spans
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

-- Selection (lines l1..l2): code goes in the prompt and the left pane.
-- `frag` = exact text of a charwise selection; ignored when it is the whole lines anyway.
function M.ask_range(l1, l2, frag)
  local buf = vim.api.nvim_get_current_buf()
  local sel = vim.api.nvim_buf_get_lines(buf, l1 - 1, l2, false)
  if frag and vim.trim(frag) == vim.trim(table.concat(sel, "\n")) then frag = nil end
  local file = vim.fn.expand("%:p")
  local ft = vim.bo.filetype
  local context = ("Archivo: %s (líneas %d-%d). Puedes leerlo si necesitas más contexto.\n\n```%s\n%s\n```\n\n")
    :format(file ~= "" and file or "[sin nombre]", l1, l2, ft, table.concat(sel, "\n"))
  if frag then context = context .. ("Seleccionado dentro de esas líneas: `%s`\n\n"):format(vim.trim(frag)) end
  -- everything read now: the buffer may change while the default question is picked
  local pane = { lines = sel, ft = ft, title = ("%s:%d-%d"):format(vim.fn.expand("%:t"), l1, l2), path = file, first = l1 }
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  M.chat(context, pane, { buf = buf, l1 = l1, l2 = l2 }, function(cb)
    require("query_kinds").pick({ file = file, ft = ft, lines = lines, l1 = l1, l2 = l2, frag = frag }, cb)
  end)
end

-- No selection: questions and edits about the whole file. The AI reads it from disk for
-- questions; the left pane starts empty and fills with related code or the diff.
-- shortcut: unsaved edits aren't seen by questions (AI reads disk), send the buffer if that bites.
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
  M.chat(context, { lines = {}, ft = ft, title = vim.fn.expand("%:t") ~= "" and vim.fn.expand("%:t") or "[sin nombre]" },
    { buf = vim.api.nvim_get_current_buf() })
end

-- Edit request for `target` = { buf, l1?, l2? }: the buffer content (unsaved edits count, the
-- 'old' snippets come from it), the selection and the chat so far.
local function edit_prompt(target, history, instr, mix)
  local b = target.buf
  local file, ft = vim.api.nvim_buf_get_name(b), vim.bo[b].filetype
  local lines = vim.api.nvim_buf_get_lines(b, 0, -1, false)
  local p = ("Archivo: %s (%s). Contenido actual del buffer, con cambios sin guardar; los 'old' salen de aquí:\n\n```%s\n%s\n```\n\n")
    :format(file ~= "" and file or "[sin nombre]", ft, ft, table.concat(lines, "\n"))
  if target.l1 then
    p = p .. ("Selección: líneas %d-%d:\n```%s\n%s\n```\n\n")
      :format(target.l1, target.l2, ft, table.concat(vim.list_slice(lines, target.l1, target.l2), "\n"))
  else
    p = p .. "Sin selección: el cambio puede ir en cualquier parte de este archivo.\n\n"
  end
  if mix then -- an answer goes to the chat in parallel; a change here is an offer, maybe none
    return p .. history .. "Pregunta del usuario: " .. instr .. "\nTambién recibe una respuesta en el chat. Propón un cambio en este archivo solo si responder bien lleva a uno (un arreglo, una mejora, lo que recomendarías); si no hace falta ninguno, devuelve edits vacío.", lines
  end
  return p .. history .. "Pedido de cambio: " .. instr, lines
end

-- One modal, one chat. What's typed goes, by default, where Jev routes it (M.route): an answer
-- (cs -q, read-only), a change (cs -e: the left pane shows it as a diff, `y` applies it to
-- target.buf in one undo step and saves; other files are listed, never touched) or a mix of
-- both. A reply to a pending change may just approve or drop it (M.PENDING). Tab in the box
-- forces a route; `e` opens it on Editar.
-- `pane` is the left pane ({ lines, ft, title, path?, first? }): its lines stay fixed; the
-- related code, example or diff under them and all notes are replaced each turn.
-- `pick(cb)`, optional, suggests the first question: it fills the input box once ready.
function M.chat(context, pane, target, pick)
  -- shortcut: related snippets use the selection's highlighting, even from other languages.
  local m = ai.modal("Consulta", {}, pane)
  local turns, busy, shown, prop = {}, false, {}, nil -- shown = examples in the pane; prop = diff in the pane
  local cbuf = m.ctx_win and vim.api.nvim_win_get_buf(m.ctx_win)

  -- code pane gutter: the selection's file lines, then `spans` (related code) or the diff from
  -- row `diff` on; no gutter while nothing in the pane is a real file line (lua/lnum.lua)
  -- Returns the gutter width.
  local function numbers(spans, diff)
    -- the pane may now show another buffer (<C-o> in it): never number that one
    if not vim.api.nvim_win_is_valid(m.ctx_win) or vim.api.nvim_win_get_buf(m.ctx_win) ~= cbuf then return 0 end
    local s = pane.first and #pane.lines > 0 and { { 0, pane.first, #pane.lines } } or {}
    return require("lnum").set(m.ctx_win, { spans = vim.list_extend(s, spans or {}), diff = diff })
  end
  numbers()

  local function footer()
    if not vim.api.nvim_win_is_valid(m.win) then return end
    -- the code pane is editable only while it shows a proposed change, to tweak it before `y`
    vim.bo[cbuf].modifiable = not busy and prop ~= nil
    local keys = { "a: preguntar o pedir", "e: editar" }
    if prop then keys[#keys + 1] = "y: aplicar" end
    if #shown > 0 then keys[#keys + 1] = "c: copiar ejemplo" end
    keys[#keys + 1] = "q: cerrar"
    vim.api.nvim_win_set_config(m.win, { footer_pos = "center", footer = " " .. table.concat(keys, " · ") .. " " })
  end

  -- Whole transcript, each turn under its request (✎ = it brings a change). Auto-routed turns
  -- name Jev's pick, so a wrong route is easy to spot and redo (Tab in the box).
  local ROUTED = { answer = "respuesta", mix = "respuesta + cambio", edit = "cambio" }
  local function render()
    local lines, head = {}, 1
    for i, t in ipairs(turns) do
      if i > 1 then vim.list_extend(lines, { "", "---", "" }) end
      head = #lines + 1
      local c = t.change
      local none = t.kind == "mix" and c and c.edits and #c.edits == 0 -- reviewed, nothing to change
      local tag = none and "respuesta · sin cambio que proponer" or t.auto and ROUTED[t.kind]
      local brings = t.kind == "edit" or (t.kind == "mix" and not none)
      vim.list_extend(lines, { "**" .. (brings and "✎ " or "") .. t.q .. "**" .. (tag and ("  _· " .. tag .. "_") or ""), "" })
      if not t.kind then
        lines[#lines + 1] = "_Pensando…_"
      elseif t.kind ~= "edit" then
        vim.list_extend(lines, t.a or { "_Pensando…_" })
      end
      if c and not none then -- a mix whose change came back empty shows only the answer
        if t.kind == "mix" then vim.list_extend(lines, { "", "**Cambio propuesto** (a la izquierda):" }) end
        vim.list_extend(lines, c.lines or { "_Preparando el cambio…_" })
      end
    end
    -- buffer lines can't hold "\n": summaries, errors and requests may be multi-line
    m.set(vim.split(table.concat(lines, "\n"), "\n", { plain = true }))
    return head
  end

  -- cs -q / cs -e keep no session, so earlier turns ride along in the prompt.
  local function history()
    local h = {}
    for _, t in ipairs(turns) do
      if t.kind == "settle" then
        h[#h + 1] = ("El usuario respondió a tu propuesta: %s\n\n"):format(t.q)
      else
        if t.a then
          h[#h + 1] = ("Pregunta anterior: %s\nTu respuesta: %s\n"):format(t.q, table.concat(t.a, "\n"))
          for _, e in ipairs(t.examples or {}) do -- so "explícame el ejemplo" works
            h[#h + 1] = ("Tu ejemplo (%s):\n%s\n"):format(e.title, table.concat(e.lines, "\n"))
          end
        end
        local c = t.change
        if c and c.edits and #c.edits > 0 then
          if not t.a then h[#h + 1] = ("Pedido de cambio anterior: %s\n"):format(t.q) end
          h[#h + 1] = ("Tu propuesta de cambio (%s): %s\n%s\n"):format(
            c.applied and "aplicada" or c.dropped and "descartada" or "no aplicada",
            table.concat(c.lines or {}, "\n"), vim.json.encode(c.edits))
        end
        h[#h + 1] = "\n"
      end
    end
    return table.concat(h)
  end

  -- what a turn left on screen, for Jev's `previous_turn`
  local function turn_kind(t)
    local c = t.change
    if c and c.applied then return "applied change" end
    if c and c.edits and #c.edits > 0 and not c.dropped then return "proposed change" end
    if t.examples and #t.examples > 0 then return "answer with example code" end
    return "answer"
  end

  local function start(turn)
    local h = history()
    turns[#turns + 1] = turn
    busy = true
    footer()
    local row = render()
    if vim.api.nvim_win_is_valid(m.win) then vim.api.nvim_win_set_cursor(m.win, { row, 0 }) end
    return h
  end

  -- a long selection pushes what's new under it out of view: bring up rows first..last (0-based)
  local function reveal(first, last)
    if not (m.ctx_win and vim.api.nvim_win_is_valid(m.ctx_win)) then return end
    vim.api.nvim_win_call(m.ctx_win, function()
      if vim.fn.line("w$") < math.min(last, first + 5) + 1 then
        -- the cursor moves too, or Neovim scrolls back to where it was
        vim.fn.winrestview({ topline = first + 1, lnum = first + 1, col = 0 })
      end
    end)
  end

  -- a turn may wait on Jev, an answer and a change at once; busy until all are back
  local function finish(turn)
    turn.waiting = turn.waiting - 1
    busy = turn.waiting > 0
  end

  local function consult(turn, h, opts)
    local hint = opts.mix and MIX_HINT or PANEL_HINT .. (opts.example and EXAMPLE_HINT or "") .. ASK_HINT
    turn.waiting = turn.waiting + 1
    ai.ask(context .. h .. "Pregunta: " .. turn.q .. hint, function(answer, err)
      finish(turn)
      if err then
        turn.a = { "**Error:** " .. err }
      else
        local out, related, notes, examples = M.parse(answer)
        turn.a, turn.examples = out, examples
        -- the pane gets examples and related code, unless a change waits there: asking about
        -- a proposal must not lose it (and in a mix, the diff is the pane's)
        if turn.kind == "answer" and not prop then
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
          local snip, spans = snippets(related, #pane.lines + #extra, rows)
          vim.list_extend(extra, snip)
          -- gutter first: notes wrap to the width it leaves
          local gutter = numbers(spans)
          m.set_ctx_extra(extra, place(notes, rows), hl, gutter) -- errors keep the previous turn's code
          if new then reveal(hl[1][1], hl[#hl][1]) end
        end
      end
      render()
      footer()
    end)
  end

  local function change(turn, h, mix)
    turn.change = {}
    if not vim.api.nvim_buf_is_valid(target.buf) then
      turn.change.lines = { "**Error:** el buffer ya no existe" }
      return
    end
    local prompt, lines = edit_prompt(target, h, turn.q, mix)
    local tick = vim.b[target.buf].changedtick
    turn.waiting = turn.waiting + 1
    ai.ask(prompt, function(out, err)
      finish(turn)
      local p
      if not err then p, err = edit_mod.proposal(lines, out) end
      if err then
        turn.change.lines = { "**Error:** " .. err }
      else
        p.tick, p.turn, p.old = tick, turn, lines
        turn.change.lines, turn.change.edits = { p.summary }, p.edits
        if #p.outside > 0 then
          vim.list_extend(turn.change.lines, { "", "**Fuera de este archivo** (no se aplica):" })
          for _, o in ipairs(p.outside) do turn.change.lines[#turn.change.lines + 1] = ("- `%s`: %s"):format(o.file, o.why) end
        end
        if #p.edits == 0 then
          vim.list_extend(turn.change.lines, { "", "_Sin cambios propuestos._" })
        else
          -- the diff replaces related code, examples and any older proposal under the selection
          prop, shown = p, {}
          local base = #pane.lines
          local extra, hl = {}, {}
          if base > 0 then extra[1] = "" end
          extra[#extra + 1] = "── cambio propuesto · editable · y: aplicar"
          hl[#hl + 1] = { base + #extra - 1, "Title" }
          p.row = base + #extra -- 0-based row of the first @@: `y` reads the diff back from here
          for _, l in ipairs(vim.split(p.diff, "\n", { trimempty = true })) do
            extra[#extra + 1] = l
            local g = l:match("^%+") and "DiffAdd" or l:match("^%-") and "DiffDelete" or l:match("^@@") and "Comment"
            if g then hl[#hl + 1] = { base + #extra - 1, g } end
          end
          m.set_ctx_extra(extra, {}, hl)
          numbers(nil, p.row) -- read live: the diff is editable until `y`
          reveal(base + (base > 0 and 1 or 0), base + #extra - 1)
        end
      end
      render()
      footer()
    end, edit_mod.cmd, edit_mod.env)
  end

  local apply -- below: `y`, also reached by typing an approval

  -- forced: nil (Auto: Jev routes) | "consulta" | "mix" | "editar"
  local function send(text, forced)
    local prev = turns[#turns]
    local turn = { q = text, auto = not forced, waiting = 0, kind = forced == "editar" and "edit" or nil }
    local h = start(turn)
    if forced == "editar" then return change(turn, h, false) end
    local qs = { gate = { type = "noul", instructions = M.GATE } }
    if not forced then
      for k, v in pairs(M.ROUTE) do qs[k] = v end
      if prop and prop.turn == prev then qs.pending = M.PENDING end -- a reply to the change on screen
    end
    local st = M.route_state({ question = text, file = pane.title, language = pane.ft, lines = pane.lines,
      prev = prev and { q = prev.q, kind = turn_kind(prev) } })
    turn.waiting = 1
    -- ~0.4s (max ai.judge_timeout) before anything else starts; the turn shows Pensando…
    ai.judge(st, qs, function(ans)
      if not vim.api.nvim_win_is_valid(m.win) then return end -- closed meanwhile
      local settle = qs.pending and M.settle(ans)
      if settle then
        turn.kind, turn.waiting, busy = "settle", 0, false
        if settle == "approve" then
          turn.a = { apply() or "_No se pudo aplicar: mira el aviso._" }
          render()
          footer()
          return
        end
        prop.turn.change.dropped, prop = true, nil
        m.set_ctx_extra({})
        numbers()
        turn.a = { "_Cambio descartado: el código queda como estaba._" }
        render()
        footer()
        return
      end
      local ex = ans and type(ans.gate) == "table" and tonumber(ans.gate.noul) or 0
      turn.kind = forced == "consulta" and "answer" or forced == "mix" and "mix" or M.route(M.route_p(ans), M.fix_p(ans))
      if turn.kind ~= "answer" then change(turn, h, turn.kind == "mix") end
      if turn.kind ~= "edit" then consult(turn, h, { example = turn.kind == "answer" and ex >= M.min_example, mix = turn.kind == "mix" }) end
      finish(turn) -- Jev's share
      render()
      footer()
    end)
  end

  local function idle()
    if busy then vim.notify("Consulta: espera la respuesta en curso", vim.log.levels.WARN) end
    return not busy
  end

  -- Input box fixed under the answer pane, always visible; its title is the route. Auto lets
  -- Jev pick; Tab forces one (Solo consulta / Consulta + cambio / Editar) for one send.
  local MODES = { "auto", "consulta", "mix", "editar" }
  local NAMES = { auto = "Auto: Jev decide", consulta = "Solo consulta", mix = "Consulta + cambio", editar = "Editar" }
  local mode, suggested = "auto", nil -- suggested = the prefilled first question
  local cfg = vim.api.nvim_win_get_config(m.win)
  vim.api.nvim_win_set_config(m.win, { relative = "editor", row = cfg.row, col = cfg.col, height = cfg.height - 3 })
  local ibuf = vim.api.nvim_create_buf(false, true)
  vim.bo[ibuf].bufhidden = "wipe"
  local iwin = vim.api.nvim_open_win(ibuf, false, { relative = "editor", style = "minimal", border = "rounded",
    row = cfg.row + cfg.height - 1, col = cfg.col, width = cfg.width, height = 1, title = " " .. NAMES.auto .. " ", title_pos = "left" })
  -- the box and the modal go together, whichever is closed first
  vim.api.nvim_create_autocmd("WinClosed", { pattern = tostring(m.win), once = true, callback = vim.schedule_wrap(function()
    if vim.api.nvim_win_is_valid(iwin) then vim.api.nvim_win_close(iwin, true) end
  end) })
  vim.api.nvim_create_autocmd("WinClosed", { pattern = tostring(iwin), once = true, callback = vim.schedule_wrap(function()
    if vim.api.nvim_win_is_valid(m.win) then vim.api.nvim_win_close(m.win, true) end
  end) })

  local function set_mode(md)
    mode = md
    -- the suggestion is a question, not a change: Editar drops it unless it was edited
    if md == "editar" and suggested and vim.api.nvim_buf_get_lines(ibuf, 0, -1, false)[1] == suggested then
      vim.api.nvim_buf_set_lines(ibuf, 0, -1, false, {})
    end
    if not vim.api.nvim_win_is_valid(iwin) then return end
    vim.api.nvim_win_set_config(iwin, { title = (" %s · Tab: modo · Enter: enviar "):format(NAMES[md]), title_pos = "left" })
  end

  local function focus_box(md)
    if not vim.api.nvim_win_is_valid(iwin) then return end
    set_mode(md)
    vim.api.nvim_set_current_win(iwin)
    -- normal mode, cursor at the end: Enter sends a suggested question as is, i / A to type
    vim.api.nvim_win_set_cursor(iwin, { 1, #(vim.api.nvim_buf_get_lines(ibuf, 0, 1, false)[1] or "") })
  end

  local function submit()
    local text = vim.trim(table.concat(vim.api.nvim_buf_get_lines(ibuf, 0, -1, false), " "))
    -- empty in a forced route: the last request again, that way (Jev routed it wrong)
    if text == "" and mode ~= "auto" and #turns > 0 then text = turns[#turns].q end
    if text == "" or not idle() then return end
    vim.api.nvim_buf_set_lines(ibuf, 0, -1, false, {})
    vim.cmd.stopinsert()
    vim.api.nvim_set_current_win(m.win)
    send(text, mode ~= "auto" and mode or nil)
    set_mode("auto") -- a forced route is for one send
  end
  for _, md in ipairs({ "i", "n" }) do
    vim.keymap.set(md, "<CR>", submit, { buffer = ibuf, desc = "Enviar" })
    vim.keymap.set(md, "<Tab>", function()
      set_mode(MODES[(vim.fn.index(MODES, mode) + 1) % #MODES + 1]) -- index() is 0-based
    end, { buffer = ibuf, desc = "Cambiar el modo: Auto, Solo consulta, Consulta + cambio, Editar" })
  end
  vim.keymap.set("n", "<Esc>", function() vim.api.nvim_set_current_win(m.win) end, { buffer = ibuf, desc = "Volver a la respuesta" })
  vim.keymap.set("n", "q", function() vim.api.nvim_win_close(m.win, true) end, { buffer = ibuf, nowait = true, desc = "Cerrar" })

  vim.keymap.set("n", "a", function() focus_box("auto") end, { buffer = m.buf, nowait = true, desc = "Preguntar o pedir un cambio (Jev decide)" })
  vim.keymap.set("n", "e", function() focus_box("editar") end, { buffer = m.buf, nowait = true, desc = "Pedir un cambio a este código" })

  -- applies the diff as it is in the left pane: lines edited, added or removed there count
  function apply()
    if busy or not prop then return vim.notify("Editar: no hay cambio listo para aplicar") end
    if not vim.api.nvim_buf_is_valid(target.buf) then return vim.notify("Editar: el buffer ya no existe", vim.log.levels.WARN) end
    if vim.b[target.buf].changedtick ~= prop.tick then
      return vim.notify("Editar: el archivo cambió desde la propuesta; pide el cambio otra vez (e)", vim.log.levels.WARN)
    end
    local new, err = edit_mod.from_diff(prop.old, vim.api.nvim_buf_get_lines(cbuf, prop.row, -1, false))
    if not new then return vim.notify("Editar: " .. err, vim.log.levels.ERROR) end
    local n = edit_mod.apply_lines(target.buf, prop.old, new)
    local done = prop
    done.turn.change.applied, prop = true, nil
    -- saved too; an unnamed or special buffer has nowhere to go, so it stays modified
    local saved, status = false, "sin guardar: el buffer no tiene archivo"
    if vim.api.nvim_buf_get_name(target.buf) ~= "" and vim.bo[target.buf].buftype == "" then
      local ok, werr = pcall(vim.api.nvim_buf_call, target.buf, function() vim.cmd("silent write") end)
      saved, status = ok, ok and "guardado" or ("no se pudo guardar: " .. tostring(werr))
    end
    -- the modal stays (q / Esc close it): the diff stays as a record, read-only, and the turn says so
    local head = done.row - 1 -- the "── cambio propuesto" line above the first @@
    local line = vim.api.nvim_buf_get_lines(cbuf, head, head + 1, false)[1] or ""
    vim.bo[cbuf].modifiable = true
    vim.api.nvim_buf_set_text(cbuf, head, 0, head, #line, { "── cambio aplicado · " .. status })
    local note = ("_Aplicado%s (%d bloque%s; u deshace en el archivo)._"):format(saved and " y guardado" or ": " .. status,
      n, n == 1 and "" or "s")
    vim.list_extend(done.turn.change.lines, { "", note })
    render()
    footer()
    vim.notify(("Editar: %d bloque%s aplicado%s, %s (u deshace)"):format(n, n == 1 and "" or "s", n == 1 and "" or "s", status),
      saved and vim.log.levels.INFO or vim.log.levels.WARN)
    return note
  end
  vim.keymap.set("n", "y", apply, { buffer = m.buf, nowait = true, desc = "Aplicar el cambio propuesto" })
  -- in the code pane `y` stays yank unless there's a change to apply
  vim.keymap.set("n", "y", function()
    if busy or not prop then return "y" end
    vim.schedule(apply)
    return ""
  end, { buffer = cbuf, nowait = true, expr = true, desc = "Aplicar el cambio propuesto (o yank)" })

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

  -- Ctrl+] / Ctrl+[ (<F13> via Karabiner), the global split cycling, loop only inside the modal:
  -- code pane → answer → input box
  local ring = { m.ctx_win, m.win, iwin }
  local function cycle(d)
    local cur = vim.api.nvim_get_current_win()
    for i, w in ipairs(ring) do
      if w == cur then return vim.api.nvim_set_current_win(ring[(i - 1 + d) % #ring + 1]) end
    end
  end
  for _, b in ipairs({ cbuf, m.buf, ibuf }) do
    vim.keymap.set("n", "<C-]>", function() cycle(1) end, { buffer = b, desc = "Siguiente panel del modal" })
    vim.keymap.set("n", "<F13>", function() cycle(-1) end, { buffer = b, desc = "Panel anterior del modal" })
  end

  -- the answer pane is read-only and always in normal mode, so `a` / `e` work right away:
  -- insert started there, or carried in from the box (a click, a window switch), is ended
  local function no_insert()
    if vim.api.nvim_get_mode().mode:find("[iR]") then vim.cmd.stopinsert() end -- i, R, niI (<C-o>)…
  end
  vim.api.nvim_create_autocmd({ "InsertEnter", "WinEnter", "BufEnter" }, { buffer = m.buf, callback = no_insert })
  -- insert resumed in the answer after a <C-o> command or a click lands here as a mode change
  vim.api.nvim_create_autocmd("ModeChanged", { pattern = "*:[iR]*", callback = function()
    if not vim.api.nvim_buf_is_valid(m.buf) then return true end -- modal gone: drop this autocmd
    if vim.api.nvim_get_current_buf() == m.buf then vim.cmd.stopinsert() end
  end })
  footer()
  set_mode("auto")
  vim.api.nvim_set_current_win(m.win)
  -- the suggested first question lands in the box once ready (Jev), unless something was typed
  if pick then
    pick(function(def)
      if not def or def == "" or #turns > 0 or not vim.api.nvim_buf_is_valid(ibuf) then return end
      if vim.trim(table.concat(vim.api.nvim_buf_get_lines(ibuf, 0, -1, false), "")) ~= "" then return end
      vim.api.nvim_buf_set_lines(ibuf, 0, -1, false, { def })
      suggested = def
    end)
  end
end

return M
