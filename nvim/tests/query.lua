-- Offline self-check for lua/query.lua (no network): nvim -l nvim/tests/query.lua
package.path = vim.fn.fnamemodify(arg[0], ":p:h:h") .. "/lua/?.lua;" .. package.path
local ai = require("ai")
local Q = require("query")
local src = vim.api.nvim_get_current_buf() -- the file being asked about / edited

local out, related, notes, ex = Q.parse(table.concat({
  "Úsalo así:",
  "@@example llamada desde un handler",
  "```lua",
  "local ok = limiter:allow(ip)",
  "",
  "if not ok then return 429 end",
  "```",
  "@@end",
  "Listo.",
  "@@related /x/a.lua:3-9 definición",
  "@@note /x/a.lua:4 ojo con esto",
}, "\n"))
assert(table.concat(out, "|") == "Úsalo así:|Listo.")
assert(#related == 1 and related[1].a == 3 and #notes == 1)
assert(#ex == 1 and ex[1].title == "llamada desde un handler")
assert(table.concat(ex[1].lines, "|") == "local ok = limiter:allow(ip)||if not ok then return 429 end") -- fences off, inner blank kept

-- unclosed block ends at the next directive; empty blocks and stray @@end vanish
out, related, _, ex = Q.parse("a\n@@example sin fin\n  x = 1\n@@related /x/b.lua:1-2 r\n@@example\n@@end\n@@end\nb")
assert(#ex == 1 and ex[1].lines[1] == "  x = 1" and #related == 1)
assert(table.concat(out, "|") == "a|b")
assert(#select(4, Q.parse("@@examples is not a directive")) == 0)
assert(#select(4, Q.parse("sin ejemplos")) == 0)
out = Q.parse("\nuno\n\n@@example e\nx\n@@end\n\n\ndos\n")
assert(table.concat(out, "|") == "uno||dos") -- one blank where the block was, none at the edges

-- gate: threshold, and any Jev failure means no example
local function gate(ans)
  ai.judge = function(_, _, cb) cb(ans) end
  local r
  Q.wants_example({ question = "q" }, function(v) r = v end)
  return r
end
assert(gate({ gate = { noul = 0.9 } }) == true and gate({ gate = { noul = 0.2 } }) == false)
assert(gate(nil) == false and gate({}) == false and gate({ gate = { noul = "x" } }) == false)

-- chat wiring: example under the selection, tinted, `c` copies it, the follow-up sees it
local prompts, noul, answer, m = {}, 0.9, "Mira el ejemplo.\n@@example uso\nfoo(1)\n@@end", nil
ai.judge = function(_, _, cb) cb({ gate = { noul = noul } }) end
ai.ask = function(p, cb) prompts[#prompts + 1] = p; cb(answer) end
local modal = ai.modal
ai.modal = function(...) m = modal(...) return m end
local asked = { "¿Cómo lo uso?", "¿por qué 1?" }
-- types the next queued text into the input box and sends it: `key` = "a" / "e" from the answer pane
local function say(key) vim.api.nvim_feedkeys(key .. "A" .. table.remove(asked, 1) .. "\r", "mx", false) end -- the box opens in normal mode
Q.chat("ctx\n", { lines = { "local function foo(x) end" }, ft = "lua", title = "a.lua:1-1" }, { buf = src })
say("a")
local pbuf
pbuf = vim.api.nvim_win_get_buf(m.ctx_win)
local function pane() return table.concat(vim.api.nvim_buf_get_lines(pbuf, 0, -1, false), "|") end
local function footer() return table.concat(vim.tbl_map(function(c) return c[1] end, vim.api.nvim_win_get_config(m.win).footer)) end
assert(prompts[1]:find("@@example <qué muestra", 1, true))
assert(pane() == "local function foo(x) end||── ejemplo · uso · no está en tu código|foo(1)")
local tinted = vim.tbl_map(function(x) return x[2] end,
  vim.api.nvim_buf_get_extmarks(pbuf, vim.api.nvim_get_namespaces().ai_notes, 0, -1, { details = true }))
assert(table.concat(tinted, ",") == "2,3" and footer():find("c: copiar"))
vim.api.nvim_feedkeys("c", "mx", false)
assert(vim.fn.getreg(vim.v.register) == "foo(1)\n")
noul, answer = 0.1, "Porque sí."
say("a")
assert(prompts[2]:find("Tu ejemplo (uso):\nfoo(1)", 1, true) and not prompts[2]:find("@@example <qué", 1, true))
assert(pane():find("foo(1)", 1, true) and footer():find("copiar")) -- kept: the follow-up may be about it

-- long selection: the pane scrolls so a new example is in view, and stays put on later turns
vim.api.nvim_feedkeys("q", "mx", false)
local long = {}
for i = 1, 100 do long[i] = "x" .. i end
noul, answer, asked = 0.9, "Ver ejemplo.\n@@example e\nfoo(2)\n@@end", { "¿Cómo lo uso?", "¿y?" }
Q.chat("ctx\n", { lines = long, ft = "lua", title = "a.lua:1-100" }, { buf = src })
say("a")
local pwin
pwin = m.ctx_win
local function top() return vim.api.nvim_win_call(pwin, function() return vim.fn.line("w0") end) end
assert(top() == 102, top()) -- 100 lines, blank separator, header
vim.api.nvim_win_call(pwin, function() vim.fn.winrestview({ topline = 1, lnum = 1 }) end) -- user scrolls up
noul, answer = 0.1, "Nada."
say("a")
assert(top() == 1) -- an old example doesn't yank the view back
vim.api.nvim_feedkeys("q", "mx", false)

-- untitled header, two examples copied together, an error keeps the shown example
local fail = false
ai.ask = function(p, cb) prompts[#prompts + 1] = p; if fail then cb(nil, "boom") else cb(answer) end end
noul, answer, asked = 0.9, "Dos.\n@@example\na()\n@@end\n@@example b\nb()\n@@end", { "q1", "q2" }
Q.chat("ctx\n", { lines = {}, ft = "lua", title = "a.lua" }, { buf = src }) -- file mode: empty pane
say("a")
pbuf = vim.api.nvim_win_get_buf(m.ctx_win)
assert(pane() == "── ejemplo · código sugerido · no está en tu código|a()||── ejemplo · b · no está en tu código|b()")
vim.api.nvim_feedkeys("c", "mx", false)
assert(vim.fn.getreg(vim.v.register) == "a()\n\nb()\n")
fail = true
say("a")
assert(pane():find("b()", 1, true) and footer():find("copiar")) -- error: previous example stays
vim.api.nvim_feedkeys("q", "mx", false)

-- modal closed before the answer arrives: the late answer is dropped without errors
local pending
ai.ask = function(_, cb) pending = cb end
asked = { "q" }
Q.chat("ctx\n", { lines = { "x" }, ft = "lua", title = "a.lua:1-1" }, { buf = src })
say("a")
vim.api.nvim_feedkeys("q", "mx", false)
pending("tarde\n@@example e\nz()\n@@end")
-- edit mode, same modal: `e` sends the chat, the buffer and the selection to cs -e; the diff
-- replaces the pane extras; `y` applies it in one undo step; a changed buffer blocks `y`
vim.api.nvim_buf_set_lines(src, 0, -1, false, { "local function add(a, b)", "  return a + b", "end", "", "print(add(1, 2))" })
local calls, proposal = {}, nil
ai.judge = function(_, _, cb) cb(nil, "off") end
ai.ask = function(p, cb, cmd, env)
  calls[#calls + 1] = { p = p, cmd = cmd, env = env }
  if cmd then cb(vim.json.encode({ structured_output = proposal })) else cb("Suma dos números.") end
end
proposal = { summary = "renombra\nen dos líneas", edits = { { old = "add(a, b)", new = "sum(a, b)" }, { old = "add(1", new = "sum(1" } },
  outside = { { file = "other.lua", why = "lo llama" } } }
asked = { "¿qué hace?", "renombra add a sum" }
Q.chat("ctx\n", { lines = { "local function add(a, b)" }, ft = "lua", title = "a.lua:1-1" }, { buf = src, l1 = 1, l2 = 1 })
say("a")
pbuf = vim.api.nvim_win_get_buf(m.ctx_win)
assert(footer():find("a: preguntar o pedir · e: editar", 1, true) and not footer():find("aplicar"))
-- the input box stays under the answer after sending, titled with its mode
vim.wait(20) -- let closed modals' boxes go
local function box()
  local b = vim.tbl_filter(function(w) return w ~= m.win and w ~= m.ctx_win and vim.api.nvim_win_get_config(w).relative ~= "" end, vim.api.nvim_list_wins())
  assert(#b == 1, #b)
  return table.concat(vim.tbl_map(function(c) return c[1] end, vim.api.nvim_win_get_config(b[1]).title))
end
assert(box():find("Auto: Jev decide", 1, true) and vim.api.nvim_get_current_win() == m.win)
assert(not vim.bo[pbuf].modifiable) -- consult: the code pane is read-only
say("e")
assert(vim.bo[pbuf].modifiable) -- a proposed change: editable before `y`
assert(box():find("Auto", 1, true)) -- a forced route (e) is for one send
assert(calls[1].cmd == nil and calls[2].cmd[2] == "-e")
assert(calls[1].env == nil and calls[2].env.CS_EFFORT == "high" and calls[2].env.CS_MODEL == "sonnet") -- queries keep ai.env
assert(calls[2].p:find("Pregunta anterior: ¿qué hace?", 1, true) and calls[2].p:find("Selección: líneas 1-1", 1, true))
assert(pane():find("── cambio propuesto", 1, true) and pane():find("+local function sum(a, b)", 1, true))
local right = table.concat(vim.api.nvim_buf_get_lines(m.buf, 0, -1, false), "|")
assert(right:find("✎ renombra add a sum", 1, true) and right:find("other.lua", 1, true))
assert(footer():find("y: aplicar"))
vim.api.nvim_buf_set_lines(src, 3, 4, false, { "-- touched" }) -- user edits meanwhile
vim.api.nvim_feedkeys("y", "mx", false)
assert(vim.api.nvim_win_is_valid(m.win) and vim.api.nvim_buf_get_lines(src, 0, 1, false)[1] == "local function add(a, b)")
vim.api.nvim_buf_set_lines(src, 3, 4, false, { "" })
asked = { "renombra add a sum" }
say("e")
assert(calls[3].p:find("Pedido de cambio anterior: renombra add a sum\nTu propuesta de cambio (no aplicada)", 1, true))
-- the user tweaks the diff in the left pane and applies from there: their edit wins
local prow = vim.fn.index(vim.api.nvim_buf_get_lines(pbuf, 0, -1, false), "+local function sum(a, b)")
vim.api.nvim_buf_set_lines(pbuf, prow, prow + 1, false, { "+local function sum(a, b) -- Wuuu" })
for _, w in ipairs(vim.api.nvim_list_wins()) do
  if vim.api.nvim_win_get_buf(w) == pbuf then vim.api.nvim_set_current_win(w) end
end
local saved = vim.fn.tempname() .. ".lua" -- `y` also writes the file
vim.api.nvim_buf_set_name(src, saved)
vim.api.nvim_buf_call(src, function() vim.o.undolevels = vim.o.undolevels end) -- a script has no typed keys to close the test's own edits as an undo step
vim.api.nvim_feedkeys("y", "mx", false)
vim.wait(500, function() return vim.api.nvim_buf_get_lines(src, 0, 1, false)[1] ~= "local function add(a, b)" end) -- expr map: applied on schedule
-- applied and saved, the modal stays: the diff is a read-only record and the turn says so
assert(vim.api.nvim_win_is_valid(m.win) and pane():find("── cambio aplicado · guardado", 1, true) and not vim.bo[pbuf].modifiable)
assert(table.concat(vim.api.nvim_buf_get_lines(m.buf, 0, -1, false), "|"):find("Aplicado y guardado (2 bloques", 1, true))
assert(not footer():find("y: aplicar"))
vim.api.nvim_feedkeys("q", "mx", false)
assert(table.concat(vim.api.nvim_buf_get_lines(src, 0, -1, false), "|") == "local function sum(a, b) -- Wuuu|  return a + b|end||print(sum(1, 2))")
assert(table.concat(vim.fn.readfile(saved), "|") == "local function sum(a, b) -- Wuuu|  return a + b|end||print(sum(1, 2))" and not vim.bo[src].modified)
vim.api.nvim_buf_call(src, function() vim.cmd("silent undo") end)
assert(vim.api.nvim_buf_get_lines(src, 0, 1, false)[1] == "local function add(a, b)") -- one undo step

-- a bad proposal (old not in the file) is an error, never a diff
proposal = { summary = "x", edits = { { old = "nope", new = "y" } } }
Q.chat("ctx\n", { lines = {}, ft = "lua", title = "a.lua" }, { buf = src })
assert(vim.api.nvim_get_current_win() == m.win and vim.api.nvim_get_mode().mode == "n") -- opens on the answer, normal mode
-- the suggested question fills the box; `e` drops it unless edited, an edited one stays
vim.api.nvim_feedkeys("q", "mx", false)
Q.chat("ctx\n", { lines = { "x" }, ft = "lua", title = "a.lua:1-1" }, { buf = src }, function(cb) cb("¿Qué hace?") end)
local function boxtext() return vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(vim.fn.win_getid(vim.fn.winnr())), 0, -1, false)[1] end
vim.api.nvim_feedkeys("a", "mx", false)
assert(boxtext() == "¿Qué hace?")
vim.api.nvim_feedkeys("\27e", "mx", false)
assert(boxtext() == "")
vim.api.nvim_feedkeys("q", "mx", false)
Q.chat("ctx\n", { lines = { "x" }, ft = "lua", title = "a.lua:1-1" }, { buf = src }, function(cb) cb("¿Qué hace?") end)
vim.api.nvim_feedkeys("aA y por qué\27\27e", "mx", false)
assert(boxtext() == "¿Qué hace? y por qué")
vim.api.nvim_feedkeys("q", "mx", false)
Q.chat("ctx\n", { lines = {}, ft = "lua", title = "a.lua" }, { buf = src })
-- Ctrl+] / Ctrl+[ (<F13>) loop code pane → answer → box, never leaving the modal
local function key(k) vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(k, true, false, true), "mx", false) end
key("<C-]>")
local boxwin = vim.api.nvim_get_current_win()
assert(boxwin ~= m.win and boxwin ~= m.ctx_win and vim.api.nvim_win_get_config(boxwin).relative ~= "")
key("<C-]>")
assert(vim.api.nvim_get_current_win() == m.ctx_win)
key("<C-]>")
assert(vim.api.nvim_get_current_win() == m.win)
key("<F13>")
assert(vim.api.nvim_get_current_win() == m.ctx_win)
key("<F13>")
assert(vim.api.nvim_get_current_win() == boxwin)
key("<F13>")
assert(vim.api.nvim_get_current_win() == m.win)
assert(footer():find("a: preguntar o pedir", 1, true))
asked = { "algo" }
say("e")
assert(table.concat(vim.api.nvim_buf_get_lines(m.buf, 0, -1, false), "|"):find("Error", 1, true) and not footer():find("aplicar"))
assert(not vim.bo[vim.api.nvim_win_get_buf(m.ctx_win)].modifiable)
vim.api.nvim_feedkeys("q", "mx", false)
-- empty file: old = "" writes the whole content; elsewhere an empty old is rejected
-- Auto: Jev routes what's typed (stubbed answers), the header names its pick
vim.api.nvim_buf_set_lines(src, 0, -1, false, { "local function add(a, b)", "  return a + b", "end" })
local JEV, judged = nil, {}
ai.judge = function(st, qs, cb) judged[#judged + 1] = { st = st, qs = qs }; cb(JEV) end
local function jev(edit, review, pending)
  return { gate = { noul = 0 }, route_edit = { noul = edit }, route_answer = { noul = 1 - edit },
    route_kind = { probabilities = { understand = 1 - review, learn = 0, review = review } },
    pending = pending and { probabilities = pending } }
end
local function right() return table.concat(vim.api.nvim_buf_get_lines(m.buf, 0, -1, false), "|") end
for _, w in ipairs(vim.api.nvim_list_wins()) do -- earlier modals left open
  if vim.api.nvim_win_get_config(w).relative ~= "" then vim.api.nvim_win_close(w, true) end
end
vim.wait(20)
calls, proposal = {}, { summary = "usa sum", edits = { { old = "add(a, b)", new = "sum(a, b)" } } }
Q.chat("ctx\n", { lines = { "local function add(a, b)" }, ft = "lua", title = "a.lua:1-1" }, { buf = src, l1 = 1, l2 = 1 })
pbuf = vim.api.nvim_win_get_buf(m.ctx_win)
assert(box():find("Auto: Jev decide", 1, true))
JEV, asked = jev(0.9, 0), { "renombra add a sum" }
say("a")
assert(#calls == 1 and calls[1].cmd[2] == "-e" and judged[#judged].qs.route_edit and not judged[#judged].qs.pending)
assert(right():find("**✎ renombra add a sum**  _· cambio_", 1, true) and pane():find("cambio propuesto", 1, true))
-- asking about the change: an answer, and the diff stays (Jev also got the pending question)
JEV, asked = jev(0.1, 0.1, { approve = 0, reject = 0, other = 1 }), { "explicame el cambio" }
say("a")
assert(judged[#judged].qs.pending and judged[#judged].st.previous_turn == "proposed change")
assert(#calls == 2 and calls[2].cmd == nil and calls[2].p:find("no menciones cs -p", 1, true) == nil)
assert(calls[2].p:find("ni menciones cs -p", 1, true) and right():find("_· respuesta_", 1, true))
assert(pane():find("cambio propuesto", 1, true) and footer():find("y: aplicar"))
-- a review goes to mix: an answer (told a diff comes) and a change, both shown
JEV, asked = jev(0.2, 0.9), { "tiene algun bug?" }
say("a")
local q_call, e_call = calls[#calls - 1], calls[#calls]
if q_call.cmd then q_call, e_call = e_call, q_call end
assert(q_call.p:find("En paralelo se le propone", 1, true) and e_call.p:find("Pregunta del usuario: tiene algun bug?", 1, true))
assert(right():find("_· respuesta + cambio_", 1, true) and right():find("**Cambio propuesto** (a la izquierda):", 1, true))
-- a review with nothing to change: just the answer, said so
proposal = { summary = "nada que cambiar", edits = {} }
JEV, asked = jev(0.2, 0.9), { "es eficiente?" }
say("a")
assert(right():find("**es eficiente?**  _· respuesta · sin cambio que proponer_", 1, true))
assert(not right():find("nada que cambiar", 1, true) and pane():find("cambio propuesto", 1, true)) -- the earlier diff stays
proposal = { summary = "usa sum", edits = { { old = "add(a, b)", new = "sum(a, b)" } } }
JEV, asked = jev(0.2, 0.9), { "tiene algun bug?" }
say("a") -- a pending change again, for the replies below
-- "cancela" to the change on screen: dropped, no model called
local before = #calls
JEV, asked = jev(0.5, 0, { approve = 0, reject = 0.95, other = 0.05 }), { "cancela" }
say("a")
assert(#calls == before and right():find("Cambio descartado", 1, true))
assert(not pane():find("cambio propuesto", 1, true) and not footer():find("aplicar"))
-- Tab forces a route for one send; Enter on an empty box re-sends the last request that way
vim.api.nvim_feedkeys("a\t\t\t", "mx", false)
assert(box():find("Editar", 1, true))
vim.api.nvim_feedkeys("\r", "mx", false)
assert(calls[#calls].cmd and calls[#calls].p:find("Pedido de cambio: cancela", 1, true))
assert(box():find("Auto", 1, true))
-- "dale" to the change on screen: applied (and saved) as with `y`, no model called
before = #calls
JEV, asked = jev(0.5, 0, { approve = 0.97, reject = 0, other = 0.03 }), { "dale" }
vim.api.nvim_buf_call(src, function() vim.o.undolevels = vim.o.undolevels end)
say("a")
assert(#calls == before and vim.api.nvim_win_is_valid(m.win) and right():find("**dale**", 1, true) and right():find("_Aplicado y guardado", 1, true))
assert(vim.api.nvim_buf_get_lines(src, 0, 1, false)[1] == "local function sum(a, b)" and not vim.bo[src].modified)

local E = require("edit")
assert(E.apply_text("\n", { { old = "", new = "hola\n" } }) == "hola\n")
assert(select(2, E.apply_text("x\n", { { old = "", new = "y" } })):find("no está", 1, true))
-- from_diff: insertion at the top, two hunks, a pure deletion, a line typed without prefix
assert(table.concat(E.from_diff({ "a", "b" }, { "@@ -0,0 +1 @@", "+z" }), "|") == "z|a|b")
local ten = {}
for i = 1, 10 do ten[i] = tostring(i) end
assert(table.concat(E.from_diff(ten, { "@@ -1 +1 @@", "-1", "+uno", "@@ -9,2 +9 @@", " 9", "-10", "nuevo" }), "|") == "uno|2|3|4|5|6|7|8|9|nuevo")
assert(select(2, E.from_diff(ten, { "+x" })):find("@@", 1, true))
print("query ok")
