-- ~/.config/nvim/lua/ai.lua
-- Base reusable for AI utils: one async call to `cs -q` (read-only Claude, see
-- ~/.local/bin/cs) and a markdown modal to show the answer. Future utils
-- (explain, review, naming...) only build a prompt and call these two.
--
-- API:
--   require("ai").ask(prompt, cb)      -- cb(answer_string | nil, err_string | nil)
--   require("ai").judge(state, questions, cb)  -- fast typed judgment (~0.4s), see M.judge
--   require("ai").modal(title, lines, ctx?)  -- ctx = { lines, ft, title } → code pane on the left
--                                            -- returns { set = fn(lines), set_ctx_extra = fn(lines, notes?, hl?), buf, win, ctx_win }
--   notes = { { row = <0-based pane row>, text = "..." }, ... } → shown as virtual lines above
--   that row, so code in the pane stays the real code.
--   hl = { { <0-based pane row>, <highlight group> }, ... } → whole-line highlight.

local M = {}
local NS = vim.api.nvim_create_namespace("ai_notes")

local function wrap(text, width)
  local out, cur = {}, ""
  for word in text:gmatch("%S+") do
    if cur ~= "" and vim.fn.strdisplaywidth(cur .. " " .. word) > width then
      out[#out + 1], cur = cur, word
    else
      cur = cur == "" and word or (cur .. " " .. word)
    end
  end
  if cur ~= "" then out[#out + 1] = cur end
  return out
end

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
      local msg = vim.trim(res.stderr or "")
      if msg == "" then msg = vim.trim(res.stdout or "") end -- "" is truthy in Lua, so no `or` chain
      return cb(nil, msg ~= "" and msg or ("cs salió con código " .. res.code))
    end
    cb(vim.trim(res.stdout or ""))
  end))
end

-- Typed judgments through TypeSafe System One (Jev): no text, just a choice/score/yes-no
-- with probabilities, fast enough to run before a prompt opens. Needs TYPESAFE_API_KEY.
-- Docs: https://docs.typesafe.ai/api.md
M.judge_model = "jev-latest"
M.judge_timeout = 1.5 -- seconds; callers fall back to a default, so keep it short

-- A Choice's options in the given order (Lua tables have none, and option order can
-- sway the model): criteria = { { name, description }, ... }.
local function encode_question(q)
  local parts = {}
  for k, v in pairs(q) do
    local val = vim.json.encode(v)
    if k == "criteria" and vim.islist(v) then
      local opts = {}
      for _, o in ipairs(v) do opts[#opts + 1] = vim.json.encode(o[1]) .. ":" .. vim.json.encode(o[2]) end
      val = "{" .. table.concat(opts, ",") .. "}"
    end
    parts[#parts + 1] = vim.json.encode(k) .. ":" .. val
  end
  return "{" .. table.concat(parts, ",") .. "}"
end

-- questions = { id = { type = "choice"|"noul"|"score", instructions, criteria } }
-- cb(answers_by_id | nil, err | nil, raw_response)
function M.judge(state, questions, cb)
  local key = vim.env.TYPESAFE_API_KEY
  if not key or key == "" then return cb(nil, "falta TYPESAFE_API_KEY") end
  local qs = {}
  for id, q in pairs(questions) do qs[#qs + 1] = vim.json.encode(id) .. ":" .. encode_question(q) end
  local body = ('{"model":%s,"state":%s,"questions":{%s}}')
    :format(vim.json.encode(M.judge_model), vim.json.encode(state), table.concat(qs, ","))
  -- the key goes in through stdin (curl -K -) so it never shows up in `ps`
  local ok, err = pcall(vim.system, {
    "curl", "-sS", "--max-time", tostring(M.judge_timeout), "-K", "-",
    "-H", "Content-Type: application/json", "--data-binary", body,
    "-w", "\n%{http_code}", "https://api.typesafe.ai/v1/systemone",
  }, { text = true, stdin = ('header = "Authorization: Bearer %s"\n'):format(key) }, vim.schedule_wrap(function(res)
    if res.code ~= 0 then
      local msg = vim.trim(res.stderr or "")
      return cb(nil, msg ~= "" and msg or ("curl salió con código " .. res.code))
    end
    local out, status = (res.stdout or ""):match("^(.*)\n(%d+)$")
    local okj, data = pcall(vim.json.decode, out or "")
    if status ~= "200" or not okj or type(data) ~= "table" or type(data.answers) ~= "table" then
      return cb(nil, ("TypeSafe %s: %s"):format(status or "?", vim.trim(out or ""):sub(1, 200)))
    end
    cb(data.answers, nil, data)
  end))
  if not ok then cb(nil, tostring(err)) end -- e.g. curl missing
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
  local cbuf, lwin
  if ctx then
    local lw = math.floor(W * 0.45)
    cbuf, lwin = float(ctx.lines, ctx.ft or "", ctx.title or "código", lw, h, row, col, false)
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
  -- Replace what's shown under ctx.lines in the code pane (ctx.lines always stay on top),
  -- all notes and line highlights. No-op without ctx or once closed.
  local function set_ctx_extra(l, notes, hl)
    if not (cbuf and vim.api.nvim_buf_is_valid(cbuf)) then return end
    vim.api.nvim_buf_clear_namespace(cbuf, NS, 0, -1)
    vim.api.nvim_buf_set_lines(cbuf, #ctx.lines, -1, false, l)
    for _, h in ipairs(hl or {}) do
      vim.api.nvim_buf_set_extmark(cbuf, NS, h[1], 0, { line_hl_group = h[2] })
    end
    local width = vim.api.nvim_win_is_valid(lwin) and vim.api.nvim_win_get_width(lwin) or 60
    local top_fill = 0
    for _, n in ipairs(notes or {}) do
      if n.row < vim.api.nvim_buf_line_count(cbuf) then
        local ind = vim.api.nvim_buf_call(cbuf, function() return vim.fn.indent(n.row + 1) end)
        local vl = {}
        for i, s in ipairs(wrap(n.text, math.max(20, width - ind - 2))) do
          vl[#vl + 1] = { { (" "):rep(ind) .. (i == 1 and "◆ " or "  ") .. s, "DiagnosticHint" } }
        end
        vim.api.nvim_buf_set_extmark(cbuf, NS, n.row, 0, { virt_lines = vl, virt_lines_above = true })
        if n.row == 0 then top_fill = top_fill + #vl end
      end
    end
    -- virt_lines above row 0 stay hidden unless the view has filler on top
    if top_fill > 0 and vim.api.nvim_win_is_valid(lwin) then
      vim.api.nvim_win_call(lwin, function() vim.fn.winrestview({ topline = 1, topfill = top_fill }) end)
    end
  end
  return { set = set, set_ctx_extra = set_ctx_extra, buf = buf, win = win, ctx_win = lwin }
end

return M
