-- Self-check for lua/split_tabs.lua (no plugins): nvim -l nvim/tests/split_tabs.lua
package.path = vim.fn.fnamemodify(arg[0], ":p:h:h") .. "/lua/?.lua;" .. package.path
local S = require("split_tabs")
local api = vim.api
S.setup()

local function settle() vim.wait(50, function() return false end) end -- let scheduled work run
local function file(name)
  local p = vim.fn.tempname() .. "-" .. name
  vim.fn.writefile({ name }, p)
  return p
end
local function tabs() return #api.nvim_list_tabpages() end
local function name(b) return vim.fn.fnamemodify(api.nvim_buf_get_name(b), ":t") end
-- bar order without bufferline: file tabs and split tabs, by b:tab_order then id
S.ids = function()
  local ids = vim.tbl_filter(function(b) return vim.bo[b].buflisted and S.is_file_tab(b) end, api.nvim_list_bufs())
  table.sort(ids, function(a, b)
    local oa, ob = vim.b[a].tab_order or a, vim.b[b].tab_order or b
    if oa ~= ob then return oa < ob end
    return a < b
  end)
  return ids
end

-- a fake tree on the left, like nvim-tree: not an editor
vim.cmd("edit " .. file("a.ts"))
local a = api.nvim_get_current_buf()
vim.cmd("topleft vnew")
vim.bo.buftype = "nofile"
local tree = api.nvim_get_current_win()
vim.cmd("wincmd l")
vim.cmd("edit " .. file("b.ts"))
local b = api.nvim_get_current_buf()
vim.cmd("edit " .. file("c.ts"))
local c = api.nvim_get_current_buf()
local home = api.nvim_get_current_tabpage()
assert(tabs() == 1 and #S.ids() == 3)

-- splitting home moves the layout to a split tab: one bar item instead of two files
vim.cmd("vsplit " .. api.nvim_buf_get_name(a))
settle()
assert(tabs() == 2 and S.is_split(0), "split became its own tab")
local pb = vim.t.split_tab_buf
assert(S.label(pb) == name(a) .. " · " .. name(c), S.label(pb))
assert(api.nvim_buf_get_name(api.nvim_get_current_buf()):find("a.ts$"), "focus stays on the new split")
assert(#vim.tbl_filter(function(w) return api.nvim_win_get_config(w).relative == "" end,
  api.nvim_tabpage_list_wins(home)) == 2, "home keeps the tree and one editor")
local ids = S.ids()
assert(#ids == 2 and vim.tbl_contains(ids, pb) and vim.tbl_contains(ids, b), "bar: b + the split tab")
assert(not S.is_file_tab(a) and not S.is_file_tab(c), "split files are not file tabs")

-- cycling walks file tabs and split tabs alike, wrapping around
assert(S.current_id() == pb)
S.cycle(1)
assert(api.nvim_get_current_tabpage() == home and S.current_id() == ids[(vim.fn.index(ids, pb) + 1) % 2 + 1])
S.cycle(1)
assert(api.nvim_get_current_tabpage() ~= home and S.current_id() == pb, "back to the split tab")

-- moving the split tab in the bar
S.move(-1)
assert(S.ids()[1] == pb)
S.move(1)
assert(S.ids()[2] == pb)

-- Opt+w in a split closes it and its file; with one split left the tab folds into a file tab
vim.cmd("wincmd t") -- leftmost window of the split tab
if not api.nvim_buf_get_name(0):find("%.ts$") then vim.cmd("wincmd l") end
local closing = api.nvim_get_current_buf()
local staying = closing == a and c or a
S.close()
settle()
assert(tabs() == 1 and api.nvim_get_current_tabpage() == home, "folded back home")
assert(not api.nvim_buf_is_valid(pb), "placeholder gone")
assert(not vim.bo[closing].buflisted, "closed split's file deleted")
assert(api.nvim_get_current_buf() == staying and S.is_file_tab(staying), "the other file is a file tab, shown")

-- Opt+n: an empty tab; a file opened over it takes its place
S.new_tab()
local empty = api.nvim_get_current_buf()
assert(vim.b[empty].empty_tab and S.is_file_tab(empty))

-- closing a whole split tab (its "x") closes its files; unsaved ones stay as file tabs
vim.cmd("edit " .. file("d.ts"))
local d = api.nvim_get_current_buf()
vim.cmd("split " .. file("e.ts"))
local e = api.nvim_get_current_buf()
settle()
assert(S.is_split(0))
pb = vim.t.split_tab_buf
api.nvim_buf_set_lines(d, 0, -1, false, { "changed" })
S.close_item(pb)
settle()
assert(tabs() == 1 and not api.nvim_buf_is_valid(pb))
assert(not vim.bo[e].buflisted, "clean file closed with its tab")
assert(vim.bo[d].buflisted and S.is_file_tab(d), "unsaved file kept as a file tab")

-- Opt+w on an unsaved split asks; cancelling keeps everything
vim.cmd("buffer " .. d)
vim.cmd("vsplit " .. api.nvim_buf_get_name(b))
settle()
assert(S.is_split(0))
local confirm = vim.fn.confirm
vim.fn.confirm = function() return 3 end
vim.cmd("wincmd h")
if api.nvim_get_current_buf() ~= d then vim.cmd("wincmd l") end
S.close()
settle()
assert(S.is_split(0) and vim.bo[d].buflisted, "cancel keeps the split and the file")
vim.fn.confirm = confirm

-- a gitsigns diff (<space>hd) becomes its own tab, in the file's slot; leaving it folds back
S.close_item(vim.t.split_tab_buf)
settle()
assert(tabs() == 1)
local f = api.nvim_get_current_buf()
local slot = vim.b[f].tab_order
vim.cmd("diffthis | vnew | file gitsigns:///x//:0:y | diffthis")
settle()
assert(tabs() == 2 and S.is_split(0), "diff became its own tab")
assert(vim.bo[vim.t.split_tab_buf].filetype == "difftab" and vim.b[vim.t.split_tab_buf].tab_order == slot)
local diffs = vim.tbl_filter(function(w) return vim.wo[w].diff end, api.nvim_tabpage_list_wins(0))
assert(#diffs == 2, "both sides still diffed in the new tab")
for _, w in ipairs(api.nvim_tabpage_list_wins(home)) do
  assert(not vim.wo[w].diff, "home left without diff")
end
S.cycle(1)
assert(api.nvim_get_current_tabpage() == home, "cycling leaves the diff behind")
S.cycle(-1)
assert(S.is_split(0), "and comes back to it")
for _, w in ipairs(api.nvim_tabpage_list_wins(0)) do -- Opt+q
  if api.nvim_buf_get_name(api.nvim_win_get_buf(w)):find("^gitsigns://") then api.nvim_win_close(w, true) end
end
vim.cmd("diffoff!")
settle()
assert(tabs() == 1 and api.nvim_get_current_buf() == f and vim.b[f].tab_order == slot, "folded back to the file tab")

-- another tool's diff with a scratch side (Claude's proposed change) stays in place
vim.cmd("diffthis | vnew | setlocal buftype=nofile | diffthis")
settle()
assert(tabs() == 1, "scratch diff stays in home")
assert(api.nvim_win_is_valid(tree))

print("split_tabs: ok")
