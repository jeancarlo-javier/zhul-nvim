-- Offline self-check for lua/query.lua (no network): nvim -l nvim/tests/query.lua
package.path = vim.fn.fnamemodify(arg[0], ":p:h:h") .. "/lua/?.lua;" .. package.path
local ai = require("ai")
local Q = require("query")

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
vim.ui.input = function(_, cb) cb(table.remove(asked, 1)) end
Q.chat("ctx\n", "", { lines = { "local function foo(x) end" }, ft = "lua", title = "a.lua:1-1" })
local pbuf
for _, w in ipairs(vim.api.nvim_list_wins()) do
  if w ~= m.win and vim.api.nvim_win_get_config(w).relative ~= "" then pbuf = vim.api.nvim_win_get_buf(w) end
end
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
vim.api.nvim_feedkeys("a", "mx", false)
assert(prompts[2]:find("Tu ejemplo (uso):\nfoo(1)", 1, true) and not prompts[2]:find("@@example <qué", 1, true))
assert(pane():find("foo(1)", 1, true) and footer():find("copiar")) -- kept: the follow-up may be about it

-- long selection: the pane scrolls so a new example is in view, and stays put on later turns
vim.api.nvim_feedkeys("q", "mx", false)
local long = {}
for i = 1, 100 do long[i] = "x" .. i end
noul, answer, asked = 0.9, "Ver ejemplo.\n@@example e\nfoo(2)\n@@end", { "¿Cómo lo uso?", "¿y?" }
Q.chat("ctx\n", "", { lines = long, ft = "lua", title = "a.lua:1-100" })
local pwin
for _, w in ipairs(vim.api.nvim_list_wins()) do
  if w ~= m.win and vim.api.nvim_win_get_config(w).relative ~= "" then pwin = w end
end
local function top() return vim.api.nvim_win_call(pwin, function() return vim.fn.line("w0") end) end
assert(top() == 102, top()) -- 100 lines, blank separator, header
vim.api.nvim_win_call(pwin, function() vim.fn.winrestview({ topline = 1, lnum = 1 }) end) -- user scrolls up
noul, answer = 0.1, "Nada."
vim.api.nvim_feedkeys("a", "mx", false)
assert(top() == 1) -- an old example doesn't yank the view back
vim.api.nvim_feedkeys("q", "mx", false)

-- untitled header, two examples copied together, an error keeps the shown example
local fail = false
ai.ask = function(p, cb) prompts[#prompts + 1] = p; if fail then cb(nil, "boom") else cb(answer) end end
noul, answer, asked = 0.9, "Dos.\n@@example\na()\n@@end\n@@example b\nb()\n@@end", { "q1", "q2" }
Q.chat("ctx\n", "", { lines = {}, ft = "lua", title = "a.lua" }) -- file mode: empty pane
for _, w in ipairs(vim.api.nvim_list_wins()) do
  if w ~= m.win and vim.api.nvim_win_get_config(w).relative ~= "" then pbuf = vim.api.nvim_win_get_buf(w) end
end
assert(pane() == "── ejemplo · código sugerido · no está en tu código|a()||── ejemplo · b · no está en tu código|b()")
vim.api.nvim_feedkeys("c", "mx", false)
assert(vim.fn.getreg(vim.v.register) == "a()\n\nb()\n")
fail = true
vim.api.nvim_feedkeys("a", "mx", false)
assert(pane():find("b()", 1, true) and footer():find("copiar")) -- error: previous example stays
vim.api.nvim_feedkeys("q", "mx", false)

-- modal closed before the answer arrives: the late answer is dropped without errors
local pending
ai.ask = function(_, cb) pending = cb end
asked = { "q" }
Q.chat("ctx\n", "", { lines = { "x" }, ft = "lua", title = "a.lua:1-1" })
vim.api.nvim_feedkeys("q", "mx", false)
pending("tarde\n@@example e\nz()\n@@end")
print("query ok")
