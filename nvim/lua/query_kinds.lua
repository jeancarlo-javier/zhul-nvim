-- ~/.config/nvim/lua/query_kinds.lua
-- Picks the default question for a selection: one ai.judge call (~0.4s) classifies the
-- code and picks the name it is about, then a template turns that into the question.
-- Any failure (no key, timeout, API error) falls back to the generic question.
--
-- API:
--   require("query_kinds").pick({ file, ft, lines, l1, l2 }, cb)  -- lines = whole buffer; cb(question)

local ai = require("ai")
local M = {}

M.fallback = "¿Qué hace esto y cómo encaja con el resto del código?"
M.max_lines = 150 -- selection lines sent; the start is what tells the kind apart
M.context_lines = 5 -- around the selection, only to disambiguate
M.min_kind = 0.45 -- below this the code is a mix (e.g. a whole file): generic question
M.min_subject = 0.7 -- below this the question stays nameless (a wrong name misleads)

-- { id, description for the model, question, question with `name` (%s) }. Sent in both
-- orders and averaged (see M.questions). Tuned on 77 labeled selections: 76 right.
M.kinds = {
  { "symbol", "Only a name or short piece picked out of a line, not whole statements: an identifier, a type in an implements/extends clause, a decorator, an argument.",
    "¿Qué significa esto aquí y de dónde viene?",
    "¿Qué es `%s`, de dónde viene y qué aporta aquí?" },
  { "test", "Test code: test cases or suites, assertions, mocks, fixtures, test setup or test helpers.",
    "¿Qué comportamiento verifica esta prueba y qué casos importantes no cubre?" },
  { "endpoint", "An HTTP route or API handler: registers a path and method, or handles a request and builds the response.",
    "¿Qué hace este endpoint: qué recibe, qué valida y qué responde?" },
  { "ui", "UI markup or a UI component: JSX, HTML, Vue/Svelte templates, or a component that mainly renders markup.",
    "¿Qué muestra esto en pantalla y de qué estado o props depende?" },
  { "styles", "CSS, SCSS or other style rules and design tokens.",
    "¿A qué elementos afectan estos estilos y qué efecto visual tienen?" },
  { "query", "A data query that reads or writes rows: SQL SELECT/INSERT/UPDATE/DELETE, ORM query builders, GraphQL, search filters.",
    "¿Qué datos lee o modifica esta consulta y es eficiente?" },
  { "schema", "A database schema or migration: CREATE/ALTER TABLE, indexes, constraints, ORM or Prisma models.",
    "¿Qué estructura de datos define esto y qué código o consultas dependen de ella?" },
  { "type", "Declarations of the shape of data with no behavior: types, interfaces, structs, enums, validation schemas (zod, JSON schema). Database tables are schema.",
    "¿Qué representa este tipo, qué campos importan y dónde se usa?",
    "¿Qué representa `%s`, qué campos importan y dónde se usa?" },
  { "class", "A class or module object that keeps its own state and has several methods.",
    "¿Qué responsabilidad tiene esta clase, qué estado guarda y quién la usa?",
    "¿Qué responsabilidad tiene `%s`, qué estado guarda y quién lo usa?" },
  { "function", "One complete function or method definition, from its signature to its end.",
    "¿Qué hace esta función, qué recibe y devuelve, y quién la usa?",
    "¿Qué hace `%s`, qué recibe y devuelve, y quién lo usa?" },
  { "async", "Statements whose main concern is concurrency or async flow: promises, await chains, callbacks, threads, goroutines, channels, locks, timers, event listeners.",
    "¿En qué orden se ejecuta esto y qué puede salir mal con la concurrencia?" },
  { "errors", "Statements mainly about catching or propagating failures: try/catch/except blocks, error returns and wrapping, retries, fallbacks. A plain guard such as `if (!ready()) return` is call.",
    "¿Qué errores maneja esto, cuáles se le escapan y qué pasa si falla?" },
  { "expression", "One dense expression worth decoding: a regular expression or string pattern (also inside a match/replace call), bit manipulation, a long chained one-liner, a formula.",
    "Explícame paso a paso qué hace esta expresión, con un ejemplo de entrada y salida." },
  { "call", "A few statements inside a function body that call or use something defined elsewhere, including guard clauses and conditions around that call.",
    "¿Qué hace este fragmento y por qué está aquí?",
    "¿Qué hace `%s` y por qué se usa aquí?" },
  { "imports", "Only import, require, include or use statements.",
    "¿Para qué se usa cada una de estas dependencias en el archivo?" },
  { "config", "Configuration: settings files (JSON, YAML, TOML, .env, Dockerfile, compose), option tables, keymaps, plugin setup, CI or build config.",
    "¿Qué configura esto y qué cambia si lo modifico?" },
  { "script", "Shell commands or scripts, Makefile targets, build or deployment steps.",
    "¿Qué hace este comando paso a paso y qué efectos tiene en el sistema?" },
  { "docs", "Comments, docstrings, Markdown or prose rather than code.",
    "¿Qué explica este texto y sigue siendo cierto en el código actual?" },
  { "other", "None of the above, or a mix of unrelated pieces.", M.fallback },
}

local STOP = {}
for w in ([[if elseif else for while switch return catch function func fn def and or not
  typeof sizeof in of do then end local const let var new await async implements extends
  public private protected readonly static export import from]]):gmatch("%S+") do STOP[w] = true end

local DEFINE = { "function", "def", "func", "fn", "class", "struct", "interface", "type", "enum", "trait" }

-- Names the selection may be about, in order: what it defines first, then what it calls.
-- Code finds them so the model only picks one, it never invents a name.
-- `bare`: also every plain identifier (for a short piece of a line, any name may be the point).
function M.candidates(text, max, bare)
  local out, seen = {}, {}
  local function add(name, how)
    name = name:gsub("[%.:]+$", "")
    if #name >= 2 and not STOP[name] and not seen[name] and #out < (max or 20) then
      seen[name] = true
      out[#out + 1] = { name, how }
    end
  end
  for _, kw in ipairs(DEFINE) do
    for n in text:gmatch("%f[%w_]" .. kw .. "%s+([%a_][%w_%.:]*)") do add(n, "defined in the selection") end
  end
  for n in text:gmatch("%f[%w_]([%a_][%w_%.]*)%s*=%s*function") do add(n, "defined in the selection") end
  for _, kw in ipairs({ "const", "let", "var", "local" }) do
    for n in text:gmatch("%f[%w_]" .. kw .. "%s+([%a_][%w_]*)%s*=") do add(n, "assigned in the selection") end
  end
  for n in text:gmatch("%f[%w_]([%a_][%w_]*)%s*=%s*async%f[%W]") do add(n, "defined in the selection") end
  for n in text:gmatch("%f[%w_]([%a_][%w_]*)%s*=%s*%b()%s*=>") do add(n, "defined in the selection") end
  for n in text:gmatch("%f[%w_]([%a_][%w_%.:]*)%s*%(") do add(n, "called in the selection") end
  if bare then
    for n in text:gmatch("%f[%w_]([%a_][%w_%.]*)") do add(n, "appears in the selection") end
  end
  return out
end

-- Lines a..b joined, at most `max` bytes (minified code has huge lines); the cut drops a
-- trailing partial UTF-8 char so the JSON stays valid.
local function slice(lines, a, b, max)
  local t = table.concat(vim.list_slice(lines, math.max(a, 1), b), "\n")
  return #t > max and (t:sub(1, max):gsub("[\192-\255][\128-\191]*$", "") .. " …") or t
end

-- What the model sees. Path and language weigh a lot (tests, config), so they go first.
function M.state(s)
  local last = math.min(s.l2, s.l1 + M.max_lines - 1)
  local sel = slice(s.lines, s.l1, last, 8000)
  -- shortcut: long selections are cut to their first M.max_lines lines, enough to tell the kind
  if last < s.l2 then sel = sel .. "\n… (" .. (s.l2 - last) .. " more lines)" end
  return {
    file = vim.fn.fnamemodify(s.file ~= "" and s.file or "[unsaved]", ":~:."),
    language = s.ft ~= "" and s.ft or "unknown",
    context_before = slice(s.lines, s.l1 - M.context_lines, s.l1 - 1, 1000),
    -- charwise selection: the exact piece, plus the lines it was cut from
    selection = s.frag and slice({ s.frag }, 1, 1, 8000) or sel,
    selected_from = s.frag and slice(s.lines, s.l1, last, 2000) or nil,
    context_after = slice(s.lines, s.l2 + 1, s.l2 + M.context_lines, 1000),
  }
end

local KIND = "What is the code in `selection` mainly? `context_before` and `context_after` are surrounding lines, only to tell where `selection` sits; `file` and `language` say what kind of file it is."

function M.questions(cands, frag)
  local instr = KIND .. (frag and " `selected_from` is the full line the `selection` was picked out of." or "")
  -- Same question twice, options in opposite orders: option order sways borderline cases
  -- (measured: 8/77 flipped), compose averages both. Runs in parallel, no extra latency.
  local fwd, rev = {}, {}
  for _, k in ipairs(M.kinds) do
    if frag or k[1] ~= "symbol" then fwd[#fwd + 1] = { k[1], k[2] } end -- symbol: pieces of a line only
  end
  for i, o in ipairs(fwd) do rev[#fwd - i + 1] = o end
  local qs = {
    kind = { type = "choice", instructions = instr, criteria = fwd },
    kind_rev = { type = "choice", instructions = instr, criteria = rev },
  }
  if #cands > 0 then
    local opts = {}
    for _, c in ipairs(cands) do opts[#opts + 1] = { c[1], "`" .. c[1] .. "`, " .. c[2] } end
    opts[#opts + 1] = { "none", "No single name stands out: the selection mixes several things, or it is data, config, markup or prose." }
    qs.subject = { type = "choice", criteria = opts,
      instructions = "Which name is the code in `selection` about? If it is a short piece of a line, the name that piece is about. If it defines a function, class or type, the name it defines. If it is statements, the called function or method whose behavior matters most to understand them. Skip language built-ins and generic standard-library helpers (pcall, print, len, map, filter, console.log, fmt.Errorf...): choose none when only those are called." }
  end
  return qs
end

-- answers → question. Kept apart from pick so it can be tested without the network.
function M.compose(answers)
  local runs, p, kind = {}, {}, nil
  for _, id in ipairs({ "kind", "kind_rev" }) do
    local a = answers[id]
    if type(a) == "table" and type(a.probabilities) == "table" then runs[#runs + 1] = a.probabilities end
  end
  for _, probs in ipairs(runs) do
    for o, v in pairs(probs) do p[o] = (p[o] or 0) + v / #runs end
  end
  for o, v in pairs(p) do
    if not kind or v > p[kind] then kind = o end
  end
  for _, k in ipairs(M.kinds) do
    if k[1] == kind and p[kind] >= M.min_kind then
      local sub = answers.subject
      local ps = sub and sub.probabilities and sub.probabilities[sub.choice] or 0
      if k[4] and ps >= M.min_subject and sub.choice ~= "none" then return k[4]:format(sub.choice) end
      return k[3]
    end
  end
  return M.fallback
end

local warned = false
function M.pick(s, cb)
  local state = M.state(s)
  if not state.selection:find("[%w_]") then return cb(M.fallback) end -- only braces/blank lines
  local frag = state.selected_from ~= nil
  ai.judge(state, M.questions(M.candidates(state.selection, nil, frag), frag), function(answers, err)
    if not answers then
      -- missing key = feature off, stay quiet; anything else, say it once per session
      if not warned and not err:find("TYPESAFE_API_KEY", 1, true) then
        warned = true
        vim.notify("Consulta: pregunta genérica (" .. err .. ")", vim.log.levels.WARN)
      end
      return cb(M.fallback)
    end
    cb(M.compose(answers))
  end)
end

return M
