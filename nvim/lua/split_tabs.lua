-- lua/split_tabs.lua
-- A split layout is ONE tab, like a Zed/VSCode tab holding splits. The main tabpage
-- ("home") keeps one editor window and its file tabs are buffers (bufferline). Splitting
-- there moves the whole layout to its own nvim tabpage, shown in the bar as a single tab
-- ("a.ts · b.ts") through a placeholder buffer, so it orders, drags, cycles and closes like
-- any file tab. Closing a split closes its file; one split left folds back into a file tab.
-- Self-check: nvim -l nvim/tests/split_tabs.lua

local M = {}
local api = vim.api

local busy = false -- inside a conversion or a close: ignore the window events it causes
local home_tp      -- the main tabpage
local home_win     -- last focused editor window in home

local function valid_tp(tp) return tp ~= nil and api.nvim_tabpage_is_valid(tp) end

local function in_diffview(tp)
  if not package.loaded["diffview.lib"] then return false end
  for _, view in ipairs(require("diffview.lib").views) do
    if view.tabpage == tp then return true end
  end
  return false
end
M.in_diffview = in_diffview

function M.is_split(tp)
  if not tp or tp == 0 then tp = api.nvim_get_current_tabpage() end
  return valid_tp(tp) and vim.t[tp].split_tab_buf ~= nil
end

-- A window holding a file: not floating, not a panel (tree, quickfix, terminal), not a
-- gitsigns:// or diffview:// revision.
local function is_editor(win)
  if not api.nvim_win_is_valid(win) or api.nvim_win_get_config(win).relative ~= "" then return false end
  local buf = api.nvim_win_get_buf(win)
  return vim.bo[buf].buftype == "" and not api.nvim_buf_get_name(buf):find("^%a[%w+.-]*://")
end

local function editors(tp) return vim.tbl_filter(is_editor, api.nvim_tabpage_list_wins(tp)) end

function M.home()
  if valid_tp(home_tp) and not M.is_split(home_tp) then return home_tp end
  for _, tp in ipairs(api.nvim_list_tabpages()) do
    if not M.is_split(tp) and not in_diffview(tp) then
      home_tp = tp
      return tp
    end
  end
  -- shortcut: home was closed by hand (:tabclose) and only split tabs remain; the first one
  -- stands in, fine until that happens often
  home_tp = api.nvim_list_tabpages()[1]
  return home_tp
end

local function home_editor()
  local tp = M.home()
  if home_win and is_editor(home_win) and api.nvim_win_get_tabpage(home_win) == tp then return home_win end
  return editors(tp)[1]
end

-- Is `buf` on screen in some split tab?
local function in_split(buf)
  for _, w in ipairs(vim.fn.win_findbuf(buf)) do
    if M.is_split(api.nvim_win_get_tabpage(w)) then return true end
  end
  return false
end

-- Should `buf` be a file tab in the bar? Files on screen in a split tab belong to that tab,
-- unless home shows them too.
function M.is_file_tab(buf)
  if vim.b[buf].split_tab then return valid_tp(vim.b[buf].split_tab) end
  local name = api.nvim_buf_get_name(buf)
  if name:find("^%a[%w+.-]*://") then return false end -- a revision (gitsigns <space>hd)
  if in_split(buf) then
    local win = home_editor()
    if not (win and api.nvim_win_get_buf(win) == buf) then return false end
  end
  return name ~= "" or vim.bo[buf].modified or vim.b[buf].empty_tab == true
end

-- Bar label of a split tab: its files, left to right.
function M.label(buf)
  local tp = vim.b[buf].split_tab
  if not valid_tp(tp) then return end
  local names = {}
  for _, w in ipairs(editors(tp)) do
    local n = api.nvim_buf_get_name(api.nvim_win_get_buf(w))
    names[#names + 1] = n ~= "" and vim.fn.fnamemodify(n, ":t") or "Sin nombre"
  end
  -- too long for the bar (max_name_length, lua/plugins/ui.lua): whole names, then "+N"
  local label, max = table.concat(names, " · "), 36
  for n = #names - 1, 1, -1 do
    if vim.fn.strdisplaywidth(label) <= max then break end
    label = table.concat(names, " · ", 1, n) .. " +" .. (#names - n)
  end
  return label
end

-- The bar item that is open now: the split tab's placeholder, or home's file.
function M.current_id()
  local tp = api.nvim_get_current_tabpage()
  if M.is_split(tp) then return vim.t[tp].split_tab_buf end
  local win = home_editor()
  return win and api.nvim_win_get_buf(win)
end

-- Most recently used file to show in home, skipping `skip` and files of split tabs.
local function recent_file(skip)
  local best
  for _, b in ipairs(vim.fn.getbufinfo({ buflisted = 1 })) do
    if not skip[b.bufnr] and vim.bo[b.bufnr].buftype == "" and (b.name ~= "" or b.changed == 1)
      and not in_split(b.bufnr) and (not best or b.lastused > best.lastused) then
      best = b
    end
  end
  return best and best.bufnr
end

local function redraw() pcall(vim.cmd.redrawtabline) end

-- Opens bar item `id`: a split tab, or a file in home's editor.
function M.open(id)
  if not api.nvim_buf_is_valid(id) then return end
  local tp = vim.b[id].split_tab
  if tp then
    if valid_tp(tp) then api.nvim_set_current_tabpage(tp) end
    return
  end
  local h = M.home()
  if api.nvim_get_current_tabpage() ~= h then api.nvim_set_current_tabpage(h) end
  local win = home_editor()
  if win then
    api.nvim_set_current_win(win)
    api.nvim_win_set_buf(win, id)
  else -- only the tree left in home: an editor next to it
    api.nvim_open_win(id, true, { split = "right", win = 0 })
    pcall(function() require("nvim-tree.api").tree.resize() end)
  end
end

-- Bar items in order (bufferline's, after filter and sort). Tests replace it.
function M.ids()
  if not package.loaded["bufferline"] then return {} end
  return vim.tbl_map(function(e) return e.id end, require("bufferline").get_elements().elements)
end

-- Next (+1) / previous (-1) bar item, split tabs included, wrapping around.
function M.cycle(step)
  local ids = M.ids()
  if #ids == 0 then return end
  local i = vim.fn.index(ids, M.current_id()) + 1
  M.open(ids[i > 0 and (i - 1 + step) % #ids + 1 or (step > 0 and 1 or #ids)])
end

-- Opt+t: a new empty file tab in home. It is a preview (lua/config.lua): the next file
-- opened takes its place, and typing in it pins it.
function M.new_tab()
  local buf = api.nvim_create_buf(true, false)
  vim.b[buf].empty_tab = true
  vim.b[buf].preview = true
  M.open(buf)
end

-- nvim-tree's "Pick window" (its window_picker.picker): a letter per split, shown in its
-- statusline like nvim-tree's own, plus n to open the file in a new tab. nil = cancelled.
local PICK_CHARS = "ABCDEFGHIJKLMOPQRSTUVWXYZ" -- no N: n is the new tab
function M.pick_window()
  local wins = vim.tbl_filter(is_editor, api.nvim_tabpage_list_wins(0))
  if #wins <= 1 then return wins[1] or -1 end -- -1: nvim-tree's own fallback
  local laststatus, saved = vim.o.laststatus, {}
  vim.o.laststatus = 2 -- the global statusline (lualine) can't show one letter per split
  for _, w in ipairs(api.nvim_tabpage_list_wins(0)) do -- the tree's gets blank, like nvim-tree's picker
    saved[w] = vim.wo[w].statusline
    vim.wo[w].statusline = " "
  end
  for i, w in ipairs(wins) do
    if i > #PICK_CHARS then break end
    vim.wo[w].statusline = "%#NvimTreeWindowPicker#%=" .. PICK_CHARS:sub(i, i) .. "%="
  end
  vim.cmd.redraw()
  api.nvim_echo({ { "Pick window (n: nuevo tab): " } }, false, {})
  local ok, c = pcall(vim.fn.getcharstr)
  for w, s in pairs(saved) do
    if api.nvim_win_is_valid(w) then vim.wo[w].statusline = s end
  end
  vim.o.laststatus = laststatus
  api.nvim_echo({ { "" } }, false, {})
  if not ok or c == "" then return end
  c = c:upper()
  if c == "N" then -- an empty tab the file then replaces (it's a preview)
    M.new_tab()
    return api.nvim_get_current_win()
  end
  local i = PICK_CHARS:find(c, 1, true)
  return i and wins[i]
end

-- Asks before dropping unsaved changes. false = saved or nothing to save, true = discard,
-- nil = cancelled (or the save failed).
local function confirm_drop(buf)
  if not vim.bo[buf].modified then return false end
  local name = api.nvim_buf_get_name(buf)
  name = name ~= "" and vim.fn.fnamemodify(name, ":~:.") or "Sin nombre"
  local c = vim.fn.confirm(("¿Guardar los cambios de %s?"):format(name), "&Guardar\n&Descartar\n&Cancelar", 1)
  if c == 1 then
    pcall(api.nvim_buf_call, buf, function() vim.cmd.write() end)
    if vim.bo[buf].modified then return nil end
    return false
  end
  if c == 2 then return true end
  return nil
end

local function delete_if_hidden(buf, force)
  if api.nvim_buf_is_valid(buf) and #vim.fn.win_findbuf(buf) == 0 then
    pcall(vim.cmd.bdelete, { args = { buf }, bang = force })
  end
end

local function drop_placeholder(pb)
  if pb and api.nvim_buf_is_valid(pb) then pcall(api.nvim_buf_delete, pb, { force = true }) end
end

local function close_tabpage(tp)
  if api.nvim_get_current_tabpage() == tp then api.nvim_set_current_tabpage(M.home()) end
  pcall(vim.cmd, "tabclose " .. api.nvim_tabpage_get_number(tp))
end

-- Closes file tab `buf` of home: its editor shows the most recent other file (or stays empty).
local function close_file(buf)
  local force = confirm_drop(buf)
  if force == nil then return end
  local win = home_editor()
  if win and api.nvim_win_get_buf(win) == buf then
    api.nvim_win_set_buf(win, recent_file({ [buf] = true }) or api.nvim_create_buf(true, false))
  end
  delete_if_hidden(buf, force)
  redraw()
end

-- Closes split `win` and its file (unless another window shows it).
local function close_split(win)
  local buf = api.nvim_win_get_buf(win)
  local shown = #vim.fn.win_findbuf(buf) > 1
  local force = false
  if not shown then
    force = confirm_drop(buf)
    if force == nil then return end
  end
  pcall(api.nvim_win_close, win, true)
  if not shown then delete_if_hidden(buf, force) end
end

-- Closes a whole split tab and its files; unsaved ones stay, as file tabs.
function M.close_tab(pb)
  local tp = vim.b[pb].split_tab
  local bufs = {}
  if valid_tp(tp) then
    for _, w in ipairs(editors(tp)) do bufs[api.nvim_win_get_buf(w)] = true end
    busy = true
    close_tabpage(tp)
    busy = false
  end
  drop_placeholder(pb)
  for b in pairs(bufs) do
    if api.nvim_buf_is_valid(b) and vim.bo[b].modified then
      vim.notify(vim.fn.fnamemodify(api.nvim_buf_get_name(b), ":t") .. ": cambios sin guardar, queda como tab",
        vim.log.levels.WARN)
    else
      delete_if_hidden(b)
    end
  end
  redraw()
end

-- Closes bar item `id` (the "x" on a tab).
function M.close_item(id)
  if vim.b[id].split_tab then return M.close_tab(id) end
  close_file(id)
end

-- Closes the window's tab: its split in a split tab, its file in home.
function M.close_window(win)
  local tp = api.nvim_win_get_tabpage(win)
  if in_diffview(tp) then return vim.cmd("DiffviewClose") end
  if M.is_split(tp) then return close_split(win) end
  local buf = api.nvim_win_get_buf(win)
  if M.is_file_tab(buf) then close_file(buf) end
end

-- Opt+w: closes the current split (split tab) or file tab (home).
function M.close()
  local tp = api.nvim_get_current_tabpage()
  local win = api.nvim_get_current_win()
  if not is_editor(win) then -- focus on the tree: act on the previous window, else any editor
    local prev = vim.fn.win_getid(vim.fn.winnr("#"))
    win = (prev ~= 0 and is_editor(prev)) and prev or editors(tp)[1]
    if not win then return end
  end
  M.close_window(win)
end

-- Opt+h / Opt+l and drag: moves bar item `id` to where `to` is (renumbers b:tab_order).
function M.move_to(id, to)
  local ids = M.ids()
  local f, t = vim.fn.index(ids, id) + 1, vim.fn.index(ids, to) + 1
  if f == 0 or t == 0 or f == t then return false end
  table.insert(ids, t, table.remove(ids, f))
  for i, b in ipairs(ids) do vim.b[b].tab_order = i end
  redraw()
  return true
end

function M.move(step)
  local ids, id = M.ids(), M.current_id()
  local to = ids[vim.fn.index(ids, id) + 1 + step]
  if id and to then M.move_to(id, to) end
end

-- Layout tree of `wins` (from winlayout), without the other windows.
local function prune(node, wins)
  if node[1] == "leaf" then return wins[node[2]] and node or nil end
  local kids = {}
  for _, c in ipairs(node[2]) do
    local p = prune(c, wins)
    if p then kids[#kids + 1] = p end
  end
  if #kids <= 1 then return kids[1] end
  return { node[1], kids }
end

-- Rebuilds layout `node` inside `win`, each leaf with its file and view; maps old -> new wins.
local function build(node, win, info, map)
  if node[1] == "leaf" then
    local d = info[node[2]]
    api.nvim_win_set_buf(win, d.buf)
    api.nvim_win_call(win, function()
      vim.fn.winrestview(d.view)
      if d.diff then vim.cmd("diffthis") end
    end)
    map[node[2]] = win
    return
  end
  local wins = { win }
  for i = 2, #node[2] do
    wins[i] = api.nvim_open_win(api.nvim_win_get_buf(win), false,
      { split = node[1] == "row" and "right" or "below", win = wins[i - 1] })
  end
  for i, child in ipairs(node[2]) do build(child, wins[i], info, map) end
end

local function is_revision(win) return api.nvim_buf_get_name(api.nvim_win_get_buf(win)):find("^gitsigns://") ~= nil end

-- Home got a second editor window, or a gitsigns diff (<space>hd): move them to a new tab.
local function convert()
  local tp = api.nvim_get_current_tabpage()
  if busy or tp ~= M.home() or M.is_split(tp) or in_diffview(tp) then return end
  local eds, revs = editors(tp), {}
  for _, w in ipairs(api.nvim_tabpage_list_wins(tp)) do
    if is_revision(w) then
      revs[#revs + 1] = w
    elseif vim.wo[w].diff and not is_editor(w) then
      return -- another tool's diff (Claude's proposed change) keeps its windows where they are
    end
  end
  if #eds < 2 and #revs == 0 then return end
  if #eds == 0 then return end
  local moved = vim.list_extend(vim.list_slice(eds), revs)
  local cur = api.nvim_get_current_win()
  local focus = vim.tbl_contains(moved, cur) and cur or eds[#eds]
  local keep = (home_win and vim.tbl_contains(eds, home_win)) and home_win or eds[1]
  local info, set = {}, {}
  for _, w in ipairs(moved) do
    set[w] = true
    info[w] = { buf = api.nvim_win_get_buf(w), view = api.nvim_win_call(w, vim.fn.winsaveview), diff = vim.wo[w].diff }
    vim.b[info[w].buf].preview = false -- a file put in a split is being worked on: pinned (lua/config.lua)
  end
  local layout = prune(vim.fn.winlayout(api.nvim_tabpage_get_number(tp)), set)
  busy = true
  local ok, err = pcall(function()
    api.nvim_set_current_win(keep)
    vim.cmd("tab split")
    local new_tp = api.nvim_get_current_tabpage()
    local w0 = vim.tbl_filter(is_editor, api.nvim_tabpage_list_wins(new_tp))[1]
    local map = {}
    build(layout, w0, info, map)
    vim.cmd("wincmd =")
    local pb = api.nvim_create_buf(true, true) -- listed, nofile, hidden when not shown
    vim.bo[pb].filetype = #revs > 0 and "difftab" or "splittab"
    vim.b[pb].split_tab = new_tp
    vim.b[pb].tab_order = vim.b[info[keep].buf].tab_order -- the tab sits where the split file was
    vim.t[new_tp].split_tab_buf = pb
    -- home back to a single editor, showing the most recent file not in a split
    for _, w in ipairs(moved) do
      if w ~= keep then pcall(api.nvim_win_close, w, true) end
    end
    if vim.wo[keep].diff then api.nvim_win_call(keep, function() vim.cmd("diffoff") end) end
    api.nvim_win_set_buf(keep, recent_file({}) or api.nvim_create_buf(true, false))
    home_win = keep
    api.nvim_set_current_win(map[focus] or w0)
  end)
  busy = false
  if not ok then vim.notify("split tab: " .. tostring(err), vim.log.levels.ERROR) end
  redraw()
end

-- A split closed in split tab `tp`: with one split left the tab folds back into a file tab
-- (in the same slot); with none, it closes.
local function settle(tp, pb)
  if busy then return end
  if not valid_tp(tp) then return drop_placeholder(pb) end
  local eds = editors(tp)
  if #eds > 1 then return redraw() end
  local buf = eds[1] and api.nvim_win_get_buf(eds[1])
  local here = api.nvim_get_current_tabpage() == tp
  if buf and api.nvim_buf_is_valid(pb) then vim.b[buf].tab_order = vim.b[pb].tab_order end
  busy = true
  close_tabpage(tp)
  busy = false
  drop_placeholder(pb)
  if buf and here then M.open(buf) end
  redraw()
end

function M.setup()
  local grp = api.nvim_create_augroup("split_tabs", { clear = true })
  home_tp = api.nvim_get_current_tabpage()
  api.nvim_create_autocmd("WinNew", {
    group = grp,
    callback = function() vim.schedule(convert) end, -- once the new window has its file
  })
  api.nvim_create_autocmd("OptionSet", { -- gitsigns turns diff on after creating its window
    group = grp,
    pattern = "diff",
    callback = function() vim.schedule(convert) end,
  })
  api.nvim_create_autocmd({ "WinEnter", "BufEnter" }, {
    group = grp,
    callback = function()
      local win, buf = api.nvim_get_current_win(), api.nvim_get_current_buf()
      local tp = vim.b[buf].split_tab
      if tp then -- a split tab's placeholder got opened (:bnext, a picker): go to the tab instead
        vim.schedule(function()
          if api.nvim_win_is_valid(win) and api.nvim_win_get_buf(win) == buf then
            api.nvim_win_set_buf(win, recent_file({}) or api.nvim_create_buf(true, false))
          end
          if valid_tp(tp) then api.nvim_set_current_tabpage(tp) end
        end)
      elseif is_editor(win) and api.nvim_win_get_tabpage(win) == M.home() then
        home_win = win
      end
      redraw()
    end,
  })
  api.nvim_create_autocmd("WinClosed", {
    group = grp,
    callback = function(ev)
      local win = tonumber(ev.match)
      if busy or not api.nvim_win_is_valid(win) then return end
      local tp = api.nvim_win_get_tabpage(win)
      if not M.is_split(tp) then return end
      local pb = vim.t[tp].split_tab_buf
      vim.schedule(function() settle(tp, pb) end)
    end,
  })
  api.nvim_create_autocmd("TabClosed", { -- :tabclose by hand: drop placeholders left behind
    group = grp,
    callback = function()
      vim.schedule(function()
        for _, b in ipairs(api.nvim_list_bufs()) do
          if vim.b[b].split_tab and not valid_tp(vim.b[b].split_tab) then drop_placeholder(b) end
        end
        redraw()
      end)
    end,
  })
  api.nvim_create_autocmd("BufDelete", { -- placeholder deleted elsewhere (a picker): close its tab, keep the files
    group = grp,
    callback = function(ev)
      local tp = vim.b[ev.buf].split_tab
      if busy or not valid_tp(tp) then return end
      vim.schedule(function()
        if valid_tp(tp) then
          busy = true
          close_tabpage(tp)
          busy = false
          redraw()
        end
      end)
    end,
  })
end

return M
