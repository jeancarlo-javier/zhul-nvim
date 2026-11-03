-- Offline self-check for lua/query_kinds.lua (no network): nvim -l nvim/tests/query_kinds.lua
package.path = vim.fn.fnamemodify(arg[0], ":p:h:h") .. "/lua/?.lua;" .. package.path
local K = require("query_kinds")

local function names(text)
  local o = {}
  for _, c in ipairs(K.candidates(text)) do o[#o + 1] = c[1] end
  return table.concat(o, ",")
end
assert(names("if (!isRedisConfigured()) {\n return null }") == "isRedisConfigured")
assert(names("function M.parse(answer)\n local p = l:match('x')") == "M.parse,l:match") -- 1-char names skipped
assert(names("export class RateLimiter {\n allow(key) {") == "RateLimiter,allow")
assert(names("const foo = async (a) => bar(a)") == "foo,bar")
assert(names("export const LoginSchema = z.object({") == "LoginSchema,z.object")
assert(names("type Request struct {") == "Request")

local function kind(probs) return { probabilities = probs } end
assert(K.compose({ kind = kind({ call = 0.9 }), subject = { choice = "f", probabilities = { f = 0.9 } } })
  == "¿Qué hace `f` y por qué se usa aquí?")
assert(K.compose({ kind = kind({ call = 0.9 }), subject = { choice = "f", probabilities = { f = 0.5 } } })
  == "¿Qué hace este fragmento y por qué está aquí?") -- unsure name → nameless
assert(K.compose({ kind = kind({ test = 0.3, docs = 0.25 }) }) == K.fallback) -- spread → generic
assert(K.compose({ kind = kind({ call = 0.6, errors = 0.4 }), kind_rev = kind({ call = 0.3, errors = 0.7 }) })
  :find("errores")) -- both orders averaged
assert(K.compose({}) == K.fallback)

local qs = K.questions({})
assert(#qs.kind.criteria == #K.kinds and qs.kind_rev.criteria[1][1] == "other" and not qs.subject)

local big = K.state({ file = "x.js", ft = "javascript", lines = { ("é"):rep(20000) }, l1 = 1, l2 = 1 }).selection
assert(#big <= 8000 + #" …" and (#big - #" …") % 2 == 0) -- cut on a char boundary
print("query_kinds ok")
