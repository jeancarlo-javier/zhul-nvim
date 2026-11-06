-- Offline self-check for lua/lnum.lua: nvim -l nvim/tests/lnum.lua
package.path = vim.fn.fnamemodify(arg[0], ":p:h:h") .. "/lua/?.lua;" .. package.path
local L = require("lnum")

-- diff, old side: context and removed lines get their line; header, @@, + and a bare "" none
-- ("" is what a user types into the editable diff, and applying it adds a line)
local d = L.diff({ "--- a/x", "+++ b/x", "@@ -11,3 +11,4 @@", " a", "-b", "+B", "+C", "", " c", "@@ -20,1 +21,1 @@", "-z", "+Z" })
assert(d[1] == nil and d[2] == nil and d[3] == nil)
assert(d[4] == 11 and d[5] == 12 and d[6] == nil and d[7] == nil and d[8] == nil and d[9] == 13)
assert(d[11] == 20 and d[12] == nil)
-- new side (a git diff of HEAD vs the file now): context and added lines
d = L.diff({ "@@ -1,2 +6,3 @@", " a", "-b", "+B", "+C", "\\ No newline at end of file" }, "+")
assert(d[2] == 6 and d[3] == nil and d[4] == 7 and d[5] == 8 and d[6] == nil)
-- the next file's headers in a multi-file diff aren't lines
d = L.diff({ "@@ -1 +1 @@", " a", "diff --git a/y b/y", "--- a/y", "+++ b/y", "@@ -4 +4 @@", "-q" })
assert(d[2] == 1 and d[4] == nil and d[5] == nil and d[7] == 4)

-- the gutter as drawn: a selection at line 14, a header row, a diff from row 4 on
local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "s1", "s2", "", "@@ -98,2 +98,2 @@", " k", "-old", "+new" })
local win = vim.api.nvim_open_win(buf, true, { relative = "editor", row = 0, col = 0, width = 40, height = 10, style = "minimal" })
assert(L.set(win, { spans = { { 0, 14, 2 } }, diff = 3 }) == 3) -- "99" + a space
assert(vim.wo[win].cursorline, "the cursor row's number must follow j/k")
local function col(lnum)
  return vim.api.nvim_eval_statusline(vim.wo[win].statuscolumn, { winid = win, use_statuscol_lnum = lnum }).str
end
assert(col(1) == "14 " and col(2) == "15 " and col(3) == "   ", col(1))
assert(col(4) == "   " and col(5) == "98 " and col(6) == "99 " and col(7) == "   ")
-- editing the diff renumbers it, and the gutter widens to fit
vim.api.nvim_buf_set_lines(buf, 4, 4, false, { " k0" })
assert(col(1) == " 14 " and col(6) == " 99 " and col(7) == "100 ")

-- nothing that is a real line: no gutter
assert(L.set(win, { spans = {} }) == 0)
assert(vim.wo[win].statuscolumn == "" and not vim.wo[win].cursorline)
assert(L.set(win, nil) == 0 and vim.wo[win].statuscolumn == "")

-- Telescope previews: a file 1..n; its placeholder (binary, too big) none
local b2 = vim.api.nvim_create_buf(false, true)
vim.api.nvim_win_set_buf(win, b2)
vim.api.nvim_buf_set_lines(b2, 0, -1, false, { "diff --git a/x b/x", "@@ -7,1 +7,1 @@", " x" }) -- a .patch file
L.set(win, "plain")
assert(col(1) == "1 " and col(3) == "3 ")
vim.api.nvim_buf_set_lines(b2, 0, -1, false, { "╱╱╱╱", "╱╱ Binary cannot be previewed ╱╱" })
assert(col(1) == "" and col(2) == "")
print("lnum: ok")
