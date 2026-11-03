-- ~/.config/nvim/lua/ai.lua
-- Base reusable for AI utils: one async call to `cs -q` (read-only Claude, see
-- ~/.local/bin/cs) and a markdown modal to show the answer. Future utils
-- (explain, review, naming...) only build a prompt and call these two.
--
-- API:
--   require("ai").ask(prompt, cb)      -- cb(answer_string | nil, err_string | nil)
--   require("ai").modal(title, lines, ctx?)  -- ctx = { lines, ft, title } → code pane on the left
--                                            -- returns { set = fn(lines), buf, win }

local M = {}

-- Command used to reach the model. cs -q has no Edit/Write/Bash, so utils can't
-- modify anything; runs in Neovim's cwd so it can Read the project for context.
M.cmd = { "cs", "-q" }
-- Speed/quality balance for editor queries (read by cs -q).
M.env = { CS_MODEL = "sonnet", CS_EFFORT = "medium" }

function M.ask(prompt, cb)
  if vim.fn.executable(M.cmd[1]) == 0 then
    return cb(nil, "falta `" .. M.cmd[1] .. "` en PATH")
  end
  local argv = vim.list_extend(vim.deepcopy(M.cmd), { prompt })
  vim.system(argv, { text = true, cwd = vim.fn.getcwd(), env = M.env }, vim.schedule_wrap(function(res)
    if res.code ~= 0 then
      return cb(nil, vim.trim(res.stderr ~= "" and res.stderr or res.stdout or "error"))
    end
    cb(vim.trim(res.stdout or ""))
  end))
end

local function float(lines, ft, title, w, h, row, col, enter)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].filetype = ft
  vim.bo[buf].bufhidden = "wipe"
  local win = vim.api.nvim_open_win(buf, enter, {
    relative = "editor", style = "minimal", border = "rounded",
    width = w, height = h, row = row, col = col,
    title = " " .. title .. " ", title_pos = "center",
  })
  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true
  return buf, win
end

-- Centered markdown float, focused so you can scroll/yank; q / <Esc> close it.
-- Optional ctx = { lines, ft, title } adds a left pane with that code, highlighted;
-- closing either pane closes both.
function M.modal(title, lines, ctx)
  local W = math.min(ctx and 180 or 90, math.floor(vim.o.columns * (ctx and 0.9 or 0.8)))
  local h = math.floor(vim.o.lines * 0.6)
  local row, col = math.floor((vim.o.lines - h) / 2), math.floor((vim.o.columns - W) / 2)
  local wins = {}
  local w = W
  if ctx then
    local lw = math.floor(W * 0.45)
    local _, lwin = float(ctx.lines, ctx.ft or "", ctx.title or "código", lw, h, row, col, false)
    wins[#wins + 1] = lwin
    w, col = W - lw - 2, col + lw + 2 -- +2: borders
  end
  local buf, win = float({}, "markdown", title, w, h, row, col, true)
  wins[#wins + 1] = win
  local function close_all()
    for _, x in ipairs(wins) do
      if vim.api.nvim_win_is_valid(x) then vim.api.nvim_win_close(x, true) end
    end
  end
  for _, x in ipairs(wins) do
    local b = vim.api.nvim_win_get_buf(x)
    for _, k in ipairs({ "q", "<Esc>" }) do
      vim.keymap.set("n", k, close_all, { buffer = b, nowait = true })
    end
    vim.api.nvim_create_autocmd("WinClosed", { pattern = tostring(x), once = true, callback = vim.schedule_wrap(close_all) })
  end
  local function set(l)
    if not vim.api.nvim_buf_is_valid(buf) then return end -- closed while waiting
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, l)
    vim.bo[buf].modifiable = false
  end
  set(lines)
  return { set = set, buf = buf, win = win }
end

return M
