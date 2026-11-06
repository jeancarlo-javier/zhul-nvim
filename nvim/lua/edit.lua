-- ~/.config/nvim/lua/edit.lua
-- Inline AI edit helpers for query.lua's `e` (cs -e): validate the AI's proposal against the
-- buffer, build its diff, apply it. The modal and the approval live in query.lua.
--
-- API:
--   require("edit").proposal(lines, cs_e_output)  -- { summary, outside, edits, new_lines, diff } | nil, err
--   require("edit").from_diff(old, diff_lines)     -- new lines from a (hand-edited) unified diff | nil, err
--   require("edit").apply_lines(buf, old, new)     -- replaces only changed lines; returns hunk count

local M = {}

M.cmd = { "cs", "-e" }
-- The code it writes must quote the buffer exactly and hold together: more effort than a query
-- (ai.env). Chosen by the user 2026-11-06 (Sonnet 5.5, high).
M.env = { CS_MODEL = "sonnet", CS_EFFORT = "high" }

-- `text` with `edits` ({ old, new }, in order) applied, or nil, err. Exact and unique
-- matches only, like Claude's Edit tool, so a misquoted snippet never lands somewhere else.
function M.apply_text(text, edits)
  for i, e in ipairs(edits) do
    if e.old == "" and vim.trim(text) == "" then -- empty file: nothing to quote, write it whole
      text = e.new
      goto continue
    end
    local s, f = text:find(e.old, 1, true)
    if e.old == "" or not s then
      return nil, ("cambio %d: su texto original no está en el archivo: `%s`"):format(i, vim.trim(e.old):sub(1, 60):gsub("\n", "⏎"))
    end
    if text:find(e.old, f + 1, true) then return nil, ("cambio %d: su texto original aparece más de una vez"):format(i) end
    text = text:sub(1, s - 1) .. e.new .. text:sub(f + 1)
    ::continue::
  end
  return text
end

-- Replaces only the changed lines of `buf` (old → new line lists), bottom-up so earlier
-- hunks keep their line numbers; marks and folds elsewhere survive.
function M.apply_lines(buf, old, new)
  local a, b = table.concat(old, "\n") .. "\n", table.concat(new, "\n") .. "\n"
  local hunks = vim.text.diff(a, b, { result_type = "indices" })
  for i = #hunks, 1, -1 do
    local sa, ca, sb, cb = unpack(hunks[i])
    local repl = vim.list_slice(new, sb, sb + cb - 1)
    if ca == 0 then -- pure insertion after line sa
      vim.api.nvim_buf_set_lines(buf, sa, sa, false, repl)
    else
      vim.api.nvim_buf_set_lines(buf, sa - 1, sa - 1 + ca, false, repl)
    end
  end
  return #hunks
end

-- New lines from `old` and a unified diff of it, as the user left it in the pane: each hunk
-- swaps the old range in its @@ header for its context and + lines; - lines and "\ No
-- newline" markers drop; a line typed without a prefix counts as new. nil, err if malformed.
function M.from_diff(old, diff)
  local out, pos, hunk = {}, 1, false
  for _, l in ipairs(diff) do
    local a, b = l:match("^@@ %-(%d+),?(%d*) %+%d+,?%d* @@")
    if a then
      a, b = tonumber(a), b == "" and 1 or tonumber(b)
      local start = b == 0 and a + 1 or a -- count 0: the header names the line before
      if start < pos then return nil, "los bloques @@ del diff están desordenados" end
      vim.list_extend(out, old, pos, start - 1)
      pos, hunk = start + b, true
    elseif not hunk then
      return nil, "el diff debe empezar con una línea @@"
    else
      local c = l:sub(1, 1)
      if c == " " or c == "+" then out[#out + 1] = l:sub(2)
      elseif c ~= "-" and c ~= "\\" then out[#out + 1] = l end
    end
  end
  vim.list_extend(out, old, pos, #old)
  return out
end

-- Proposal for `lines` from cs -e's JSON output: { summary, outside, new_lines, diff } or nil, err.
function M.proposal(lines, out)
  local ok, res = pcall(vim.json.decode, out)
  if not ok or type(res) ~= "table" then return nil, "respuesta no es JSON: " .. out:sub(1, 200) end
  local p = res.structured_output
  if res.is_error or type(p) ~= "table" then return nil, tostring(res.result or "sin propuesta") end
  local old = table.concat(lines, "\n") .. "\n"
  local new, err = M.apply_text(old, p.edits or {})
  if not new then return nil, err end
  if new:sub(-1) ~= "\n" then new = new .. "\n" end
  local new_lines = vim.split(new:sub(1, -2), "\n", { plain = true })
  return { summary = p.summary or "", outside = p.outside or {}, edits = p.edits or {}, new_lines = new_lines,
    diff = vim.text.diff(old, new, { ctxlen = 3 }) }
end

return M
