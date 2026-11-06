-- Live eval (network, needs TYPESAFE_API_KEY) of Jev's routing in the query modal (Q.ROUTE):
-- answer (cs -q), edit (cs -e, a diff to approve) or mix (both, when in doubt). Also re-checks
-- the example gate on the same state.
--   nvim -l nvim/tests/query_route_eval.lua            -- ROUNDS=4 to measure flips between calls
-- Prints, per threshold pair, exact and acceptable routes, the costly crossings (an edit
-- answered, a question turned into an edit), and every case off its wanted route.
package.path = vim.fn.fnamemodify(arg[0], ":p:h:h") .. "/lua/?.lua;" .. package.path
local ai = require("ai")
local Q = require("query")

local CODE = { "function hello(name = \"World\") {", "  console.log(`Hello ${name}!`);", "}", "", "hello();" }

-- { q, edit = wanted route (true edit, false answer) or want = "mix", ok = other acceptable routes,
--   ex = example gate label (answers only), prev = { q, turn }, nocode = no selection, empty file }
-- turn: what the previous turn left on screen. Ambiguous cases are labeled by the modal's
-- purpose (learning first: in doubt, answer; mix when the answer likely ends in a change).
local A, AX, PC, AC = "answer", "answer with example code", "proposed change", "applied change"
local CASES = {
  -- answers: understand, review, opinion
  { q = "Que es eso?", edit = false, ex = false },
  { q = "Como mejorarias esto?", want = "mix", ok = { "answer" }, },
  { q = "¿Qué hace esta función, qué recibe y devuelve, y quién la usa?", edit = false, ex = false },
  { q = "¿Qué hace este fragmento y por qué está aquí?", edit = false, ex = false },
  { q = "¿Qué configura esto y qué cambia si lo modifico?", edit = false, ex = false },
  { q = "¿Qué errores maneja esto, cuáles se le escapan y qué pasa si falla?", edit = false, ok = { "mix" }, ex = false },
  { q = "¿Qué hace esto y cómo encaja con el resto del código?", edit = false, ex = false },
  { q = "tiene algun bug?", want = "mix", ok = { "answer" }, ex = false, },
  { q = "por que no compila?", want = "mix", ok = { "answer" }, ex = false, },
  { q = "es eficiente esto?", want = "mix", ok = { "answer" }, ex = false, },
  { q = "donde se usa hello?", edit = false, ex = false },
  { q = "que cambiarias aqui?", want = "mix", ok = { "answer" }, },
  { q = "qué pasa si name viene vacío?", want = "mix", ok = { "answer" }, ex = false, },
  { q = "que significa ese ${} ?", edit = false, ex = false },
  { q = "esto es idiomático en TypeScript?", want = "mix", ok = { "answer" }, ex = false, },
  { q = "cual es la diferencia entre let y const aqui?", edit = false, ex = false },
  { q = "what does this do?", edit = false, ex = false },
  { q = "should I split this into two functions?", want = "mix", ok = { "answer" }, },
  { q = "hay codigo muerto aqui?", want = "mix", ok = { "answer" }, ex = false, },
  { q = "que tipo devuelve?", edit = false, ex = false },
  { q = "esto podria fallar con null?", want = "mix", ok = { "answer" }, ex = false, },
  { q = "resume este archivo", edit = false, ex = false },
  { q = "qué patrón es este?", edit = false, ex = false },
  { q = "no deberia ser async?", want = "mix", ok = { "answer" }, },
  { q = "se puede hacer esto con reduce?", edit = false },
  -- answers: learn how (the modal teaches; examples, not edits)
  { q = "como hago para que acepte un nombre?", edit = false, ex = true },
  { q = "enséñame a escribir un test para esto", edit = false, ex = true },
  { q = "dame un ejemplo de como llamarla", edit = false, ex = true },
  { q = "como se usaria esto con async/await?", edit = false, ex = true },
  { q = "como lo testearias?", edit = false, ex = true },
  { q = "explicame como se hace un debounce", edit = false, ex = true },
  { q = "how would I make this generic?", edit = false, ex = true },
  { q = "como harias para que reciba un idioma?", edit = false, ex = true, ok = { "mix" } },
  -- answers about an earlier turn
  { settle = "other", q = "por que usaste un for en vez de map?", edit = false, ex = false, prev = { "hazla mas rapida", PC } },
  { settle = "other", q = "explicame el cambio", edit = false, ex = false, prev = { "renombra hello a greet", PC } },
  { q = "y eso es seguro?", edit = false, ok = { "mix" }, ex = false, prev = { "agrega validacion", AC } },
  { q = "por que el ejemplo usa Intl?", edit = false, ex = false, prev = { "como hago que salude segun la hora?", AX } },
  { q = "explicame el ejemplo", edit = false, ex = false, prev = { "dame un ejemplo de uso", AX } },
  { settle = "other", q = "y por qué?", edit = false, ex = false, prev = { "quita el valor por defecto", PC } },
  -- changes: direct requests
  { q = "Añade un hello ts", edit = true },
  { q = "Puedes poner una función para ejecutar eso?", edit = true },
  { q = "Puedes hacer una función mucho más compleja?", edit = true },
  { q = "renombra hello a greet", edit = true },
  { q = "arregla el bug", edit = true },
  { q = "agrega validación para name vacío", edit = true },
  { q = "quita los console.log", edit = true },
  { q = "convierte esto a arrow function", edit = true },
  { q = "hazlo más simple", edit = true },
  { q = "mejóralo", edit = true },
  { q = "pon tipos a los parámetros", edit = true },
  { q = "traduce los comentarios al inglés", edit = true },
  { q = "añade un comentario que explique el template string", edit = true },
  { q = "extrae esto a una función", edit = true },
  { q = "puedes agregar manejo de errores?", edit = true },
  { q = "podrias hacer que reciba un idioma?", edit = true },
  { q = "cambia el saludo a español", edit = true },
  { q = "elimina esta función", edit = true },
  { q = "ordena los imports", edit = true },
  { q = "haz que compile", edit = true },
  { q = "make it async", edit = true },
  { q = "add a test for this", edit = true },
  { q = "rename this to greet", edit = true },
  { q = "completa la función", edit = true },
  { q = "implementa el TODO", edit = true },
  { q = "formatea esto", edit = true },
  { q = "usa const en lugar de let", edit = true },
  { q = "agrega un parámetro opcional lang con valor por defecto es", edit = true },
  { q = "documenta la función con JSDoc", edit = true },
  { q = "Wuuu, ponle un emoji al saludo", edit = true },
  -- changes that lean on an earlier turn
  { q = "aplicalo.", edit = true, prev = { "Puedes hacer una función mucho más compleja?", AX } },
  { q = "aplícalo", edit = true, prev = { "como mejorarias esto?", A } },
  { q = "hazlo", edit = true, prev = { "que cambiarias aqui?", A } },
  { q = "sí, cámbialo", edit = true, prev = { "no deberia ser async?", A } },
  { q = "ok, haz eso", edit = true, prev = { "hay codigo muerto aqui?", A } },
  { settle = "other", q = "y que también valide null", edit = true, prev = { "agrega validación para name vacío", PC } },
  { settle = "other", q = "mejor usa map en vez de for", edit = true, prev = { "hazla mas rapida", PC } },
  { settle = "other", q = "otra vez pero sin la clase", edit = true, prev = { "extrae esto a una clase", PC } },
  { q = "ahora también exporta la función", edit = true, prev = { "renombra hello a greet", AC } },
  { q = "deshaz lo de los tipos", edit = true, prev = { "pon tipos a los parámetros", AC } },
  -- ambiguous: opinions that end in a change, wishes stated as facts, proposals
  { settle = "other", q = "y si lo hacemos con reduce?", want = "mix", ok = { "edit" }, prev = { "hazla mas rapida", PC } },
  { q = "esto deberia lanzar un error si name está vacío", want = "mix", ok = { "edit" } },
  { q = "falta validar que name no sea vacío", want = "mix", ok = { "edit" } },
  { q = "hay alguna forma mas simple de escribir esto?", want = "mix", ok = { "answer" }, },
  -- edge: several intents at once
  { q = "explica qué hace y arréglalo", want = "mix", ok = { "edit" } },
  { q = "¿qué está mal? corrígelo", want = "mix", ok = { "edit" } },
  { q = "explícame por qué falla con null y hazlo más robusto", want = "mix", ok = { "edit" } },
  -- edge: no selection, empty or whole file
  { q = "Añade un hello ts", edit = true, nocode = true },
  { q = "crea una función que sume dos números", edit = true, nocode = true },
  { q = "que hace este archivo?", edit = false, ex = false, nocode = true },
  { q = "como empiezo un servidor express aqui?", edit = false, ex = true, ok = { "mix" }, nocode = true },
  -- edge: the change reaches other files
  { q = "añade esto también en utils.ts", edit = true },
  { q = "como lo importo desde otro archivo?", edit = false, ex = true },
  -- edge: conversation glue
  { q = "aplícalo", edit = true, ok = { "mix" } }, -- nothing before: cs -e still gets the selection
  { q = "gracias!", edit = false, prev = { "renombra hello a greet", AC } },
  -- edge: replies to a change waiting in the diff (settle = Q.PENDING's wanted pick)
  { q = "ok", settle = "approve", prev = { "agrega validación para name vacío", PC } },
  { q = "dale", settle = "approve", prev = { "renombra hello a greet", PC } }, -- in Q.PENDING's criteria (user's dialect)
  { q = "sí, aplícalo", settle = "approve", prev = { "quita los console.log", PC } },
  { q = "perfecto", settle = "approve", prev = { "pon tipos a los parámetros", PC } },
  { q = "aplicalo.", settle = "approve", prev = { "hazlo más simple", PC } },
  { q = "listo, adelante", settle = "approve", prev = { "ordena los imports", PC } },
  { q = "de una", settle = "approve", prev = { "usa const en lugar de let", PC } },
  { q = "sí", settle = "approve", prev = { "hazlo más simple", PC } },
  { q = "cancela", settle = "reject", prev = { "extrae esto a una clase", PC } },
  { q = "no, mejor no", settle = "reject", prev = { "convierte esto a arrow function", PC } },
  { q = "olvídalo", settle = "reject", prev = { "mejóralo", PC } },
  { q = "ok pero sin el comentario", settle = "other", edit = true, prev = { "documenta la función con JSDoc", PC } },
  { q = "aplícalo pero con const", settle = "other", edit = true, prev = { "hazlo más simple", PC } },
  { q = "no, déjalo como estaba", edit = true, prev = { "convierte esto a arrow function", AC } },
  -- edge: long, mixed language, typos
  { q = "oye una pregunta, este hello lo llamo desde el index o desde donde? no encuentro de donde viene", edit = false, ex = false },
  { q = "pls cambia el console.log por un return y que devuelva el string", edit = true },
  { q = "ahcelo async plz", edit = true },
}

-- every suggested first question (query_kinds) must be answered, never routed to an edit
-- review-like ones (failure cases, efficiency, coverage, staleness) may also offer a fix
local REVIEW_KINDS = { errors = true, query = true, test = true, docs = true, async = true }
for _, k in ipairs(require("query_kinds").kinds) do
  CASES[#CASES + 1] = { q = k[3], edit = false, ok = REVIEW_KINDS[k[1]] and { "mix" } or nil }
  if k[4] then CASES[#CASES + 1] = { q = k[4]:format("hello"), edit = false } end
end

for _, c in ipairs(CASES) do -- normalize: want = route name, ok = set of acceptable routes
  if c.settle and c.settle ~= "other" then c.want = c.settle end -- settled in code, no route
  c.want = c.want or (c.edit and "edit" or "answer")
  local ok = { [c.want] = true }
  for _, r in ipairs(c.ok or {}) do ok[r] = true end
  c.ok = ok
end

local function noul(ans, k) return ans and type(ans[k]) == "table" and tonumber(ans[k].noul) end

local function state(c)
  return Q.route_state({ question = c.q, file = "hello.ts", language = "typescript", lines = not c.nocode and CODE or nil,
    prev = c.prev and { q = c.prev[1], kind = c.prev[2] } })
end

-- ROUNDS=n repeats every request n times: Jev's answers vary between calls, so a scorer is
-- judged by its mean accuracy and by how many cases flip sides between rounds.
local ROUNDS = tonumber(vim.env.ROUNDS) or 1
local jobs = {}
for r = 1, ROUNDS do for n = 1, #CASES do jobs[#jobs + 1] = { r = r, n = n } end end
local results, pending, i, MAX_PARALLEL = {}, 0, 0, 8 -- results[r][n] = answers
for r = 1, ROUNDS do results[r] = {} end
local function launch()
  while pending < MAX_PARALLEL and i < #jobs do
    i = i + 1
    local job = jobs[i]
    local qs = { gate = { type = "noul", instructions = Q.GATE } }
    for name, v in pairs(Q.ROUTE) do qs[name] = v end
    qs.pending = Q.PENDING
    pending = pending + 1
    ai.judge(state(CASES[job.n]), qs, function(ans, err)
      pending = pending - 1
      results[job.r][job.n] = ans or { err = err }
      launch()
    end)
  end
end
ai.judge_timeout = 10 -- eval, not the editor: let slow answers count
launch()
vim.wait(600000, function() return pending == 0 and i == #jobs end, 50)

local errs = 0
for r = 1, ROUNDS do for n = 1, #CASES do if not results[r][n] or results[r][n].err then errs = errs + 1 end end end
print(("cases %d × rounds %d · errors %d"):format(#CASES, ROUNDS, errs))

-- what the modal does: a pending proposal may be settled first, then Q.route decides
local function decide(c, ans, t)
  local s = c.prev and c.prev[2] == PC and Q.settle(ans)
  if s then return s end
  local v = Q.route_p(ans)
  return v and Q.route(v, Q.fix_p(ans), t)
end
local function mean_p(n)
  local sum, k = 0, 0
  for r = 1, ROUNDS do
    local v = Q.route_p(results[r][n])
    if v then sum, k = sum + v, k + 1 end
  end
  return k > 0 and sum / k or nil
end
print("mix ≤ p < edit, fix · exact / acceptable · crossings (edit→answer, answer→edit) · clear cases sent to mix · flips")
local live = { mix = Q.min_mix, edit = Q.min_edit, fix = Q.min_fix }
for _, edit in ipairs({ 0.6, 0.65 }) do
  for _, fix in ipairs({ 0.4, 0.5, 0.6, 0.7, 0.8, 2 }) do
    local t = { mix = Q.min_mix, edit = edit, fix = fix }
    local exact, okc, total, ea, ae, tomix, flips = 0, 0, 0, 0, 0, 0, 0
    for n, c in ipairs(CASES) do
      local seen = {}
      for r = 1, ROUNDS do
        local got = decide(c, results[r][n], t)
        if got then
          seen[got] = true
          total = total + 1
          exact = exact + (got == c.want and 1 or 0)
          okc = okc + (c.ok[got] and 1 or 0)
          if c.want == "edit" and got == "answer" and not c.ok.answer then ea = ea + 1 end
          if (c.want == "answer" or c.want == "reject") and (got == "edit" or got == "approve") and not c.ok[got] then ae = ae + 1 end
          if got == "mix" and not c.ok.mix then tomix = tomix + 1 end
        end
      end
      if vim.tbl_count(seen) > 1 then flips = flips + 1 end
    end
    print(("  %.2f–%.2f fix %-4s %5.1f%% / %5.1f%%  crossings %d+%d  to mix %d  flips %d%s"):format(t.mix, edit,
      fix > 1 and "off" or ("%.2f"):format(fix), 100 * exact / total, 100 * okc / total, ea, ae, tomix, flips,
      vim.deep_equal(t, live) and "   ← query.lua" or ""))
  end
end

print(("\noff the wanted route at query.lua's thresholds (p = mean edit, f = mean review):"))
for n, c in ipairs(CASES) do
  local v = mean_p(n)
  local f, k = 0, 0
  for r = 1, ROUNDS do
    local x = Q.fix_p(results[r][n])
    if x then f, k = f + x, k + 1 end
  end
  f = k > 0 and f / k or 0
  local got = decide(c, results[1][n]) -- first round
  if got and got ~= c.want then
    print(("  p %.2f f %.2f %-6s want %-6s%s %q%s"):format(v, f, got, c.want, c.ok[got] and " (ok)" or " ✗  ", c.q,
      c.prev and (" ← " .. c.prev[2]) or ""))
  end
end

local gok, gn, gmiss = 0, 0, {}
for n, c in ipairs(CASES) do
  if c.ex ~= nil then
    for r = 1, ROUNDS do
      local v = noul(results[r][n], "gate")
      if v then
        gn = gn + 1
        if (v >= Q.min_example) == c.ex then gok = gok + 1 else gmiss[#gmiss + 1] = ("  %.2f want %s %q"):format(v, tostring(c.ex), c.q) end
      end
    end
  end
end
print("\nQ.PENDING on replies to a proposed change (mean probability of the wanted pick):")
for n, c in ipairs(CASES) do
  if c.settle then
    local sum, picks = 0, {}
    for r = 1, ROUNDS do
      local a = results[r][n] and results[r][n].pending
      if a and a.probabilities then sum = sum + (tonumber(a.probabilities[c.settle]) or 0); picks[#picks + 1] = a.choice end
    end
    print(("  %.2f %-7s %q  picks: %s"):format(sum / ROUNDS, c.settle, c.q, table.concat(picks, " ")))
  end
end

print(("\nexample gate at %.2f: %d/%d"):format(Q.min_example, gok, gn))
for _, l in ipairs(gmiss) do print(l) end
