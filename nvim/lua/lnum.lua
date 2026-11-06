-- ~/.config/nvim/lua/lnum.lua
-- Line numbers for panes whose rows aren't one file's lines: the <leader>q code pane (selection,
-- related snippets, proposed diff) and Telescope previews (files, git diffs). Each row shows the
-- line it is on in its file *now*; headers, separators, examples, the diff side that isn't "now",
-- wrapped and virtual lines show none.
--
-- API:
--   require("lnum").set(win, spec) -> gutter width (0 = hidden). spec:
--     nil                            no gutter
--     "plain"                        1..n
--     { spans, diff?, side? }        spans = { { row0, first_line, count } }; rows from `diff`
--                                    (0-based) on are a unified diff, read live, numbered on
--                                    `side` "-" (default: the old side) or "+"
--   require("lnum").diff(lines, side?)  -- { [i] = line on that side } for a unified diff

local M = {}
local specs, cache = {}, {}
local EXPR = "%!v:lua.require'lnum'.column()"

vim.api.nvim_create_autocmd("BufWipeout", { callback = function(ev) specs[ev.buf], cache[ev.buf] = nil, nil end })

function M.diff(lines, side)
  local other = side == "+" and "^%-" or "^%+"
  local pat = side == "+" and "^@@ %-[%d,]+ %+(%d+)" or "^@@ %-(%d+)"
  local out, n = {}, nil
  for i, l in ipairs(lines) do
    local a = l:match(pat)
    if a then
      n = tonumber(a)
    elseif l:match("^diff ") then
      n = nil -- next file's ---/+++ headers aren't lines
    elseif n and l:match("^[ +-]") and not l:match(other) then
      out[i], n = n, n + 1
    end
  end
  return out
end

-- { map = { [lnum] = n } | nil (plain 1..n), width }, cached until the buffer or its spec changes
local function rows(buf)
  local tick = vim.api.nvim_buf_get_changedtick(buf)
  local c = cache[buf]
  if c and c.tick == tick then return c end
  local spec, map = specs[buf], nil
  if spec then
    map = {}
    for _, s in ipairs(spec.spans) do
      for i = 0, s[3] - 1 do map[s[1] + i + 1] = s[2] + i end
    end
    if spec.diff then
      local d = M.diff(vim.api.nvim_buf_get_lines(buf, spec.diff, -1, false), spec.side)
      for i, n in pairs(d) do map[spec.diff + i] = n end
    end
  elseif (vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] or ""):match("^╱") then
    map = {} -- Telescope's placeholder (binary, too big, timed out); shortcut: assumes the default msg_bg_fillchar
  end
  local max = map and 0 or vim.api.nvim_buf_line_count(buf)
  for _, n in pairs(map or {}) do max = math.max(max, n) end
  c = { tick = tick, map = map, width = max > 0 and #tostring(max) or 0 }
  cache[buf] = c
  return c
end

-- 'statuscolumn' expression
function M.column()
  local win = vim.g.statusline_winid
  local c = rows(vim.api.nvim_win_get_buf(win))
  if c.width == 0 then return "" end
  local n = vim.v.virtnum == 0 and (c.map and c.map[vim.v.lnum] or not c.map and vim.v.lnum) or nil
  -- the cursor's row stands out, so the pane says which line you're on
  local hl = n and vim.v.relnum == 0 and "%#CursorLineNr#" or "%#LineNr#"
  return hl .. ("%" .. c.width .. "s "):format(n or "")
end

function M.set(win, spec)
  local buf = vim.api.nvim_win_get_buf(win)
  specs[buf], cache[buf] = type(spec) == "table" and spec or nil, nil
  local on = spec == "plain" or type(spec) == "table" and (#spec.spans > 0 or spec.diff ~= nil)
  -- the column is redrawn on cursor moves only with 'cursorline'; "number" keeps the line itself plain
  vim.wo[win].cursorline = on
  vim.wo[win].cursorlineopt = "number"
  -- set again even if unchanged: the column only shrinks when the option is set
  vim.wo[win].statuscolumn = on and EXPR or ""
  local w = on and rows(buf).width or 0
  return w > 0 and w + 1 or 0
end

return M
