-- lua/plugins/claude.lua
-- Integración Neovim x Claude CLI: el bridge MCP (WebSocket) arranca con Neovim y
-- emite SIEMPRE la selección. Quién la escucha lo decide cada sesión de Claude con
-- `/ide` (opt-in por sesión); sin auto-connect, las demás sesiones del mismo
-- directorio no se enteran. El lockfile ~/.claude/ide/<port>.lock declara
-- workspaceFolders = cwd de Neovim y Claude solo lo lista si su cwd cae dentro.

local function lockfile_path(port)
  local dir = os.getenv("CLAUDE_CONFIG_DIR") or (vim.fn.expand("~") .. "/.claude")
  return dir .. "/ide/" .. tostring(port) .. ".lock"
end

-- Claude CLI reinicia su estado de selección cada vez que (re)conecta o refresca
-- la lista de clientes MCP; la extensión oficial de VS Code compensa reenviando la
-- selección vigente ~500ms tras cada conexión. claudecode.nvim no lo hace, así que
-- envolvemos tcp.create_server para encadenar ese reenvío en on_connect.
-- Imprescindible aquí: con /ide la conexión siempre llega tarde.
local function patch_resend_on_connect()
  local tcp = require("claudecode.server.tcp")
  if tcp._resend_patched then
    return
  end
  tcp._resend_patched = true
  local orig = tcp.create_server
  tcp.create_server = function(config, callbacks, auth_token)
    local user_on_connect = callbacks.on_connect
    callbacks.on_connect = function(client)
      if user_on_connect then
        user_on_connect(client)
      end
      vim.defer_fn(function()
        local ok, selection = pcall(require, "claudecode.selection")
        if not ok or not selection.state.tracking_enabled then
          return
        end
        local latest = selection.get_latest_selection()
        if latest and latest.text and latest.text ~= "" then
          selection.send_selection_update(latest)
        end
      end, 500)
    end
    return orig(config, callbacks, auth_token)
  end
end

local title = { title = "Claude Code" }

local function start_bridge()
  local cc = require("claudecode")
  patch_resend_on_connect()

  local ok, port_or_err = cc.start(false)
  if not ok then
    vim.notify("Claude Bridge: error al iniciar: " .. tostring(port_or_err), vim.log.levels.ERROR, title)
    return
  end

  local lock = lockfile_path(port_or_err)
  if vim.fn.filereadable(lock) == 0 then
    vim.notify("Claude Bridge: servidor en :" .. port_or_err .. " pero falta lockfile " .. lock, vim.log.levels.ERROR, title)
    return
  end

  vim.notify(("Claude Bridge listo en :%d — en Claude: /ide para seguir la selección"):format(port_or_err), vim.log.levels.INFO, title)
end


return {
  {
    "coder/claudecode.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
    event = "VeryLazy",
    keys = {
      { "<leader>cs", "<cmd>ClaudeCodeSend<cr>", mode = "v", desc = "Enviar selección a Claude (@mention)" },
      { "<leader>ca", "<cmd>ClaudeCodeDiffAccept<cr>", desc = "Aceptar diff de Claude" },
      { "<leader>cx", "<cmd>ClaudeCodeDiffDeny<cr>", desc = "Rechazar diff de Claude" },
    },
    opts = {
      auto_start = false,
      track_selection = true,
      -- Claude corre en terminal externo (cs); Neovim no abre terminal propio
      terminal = { provider = "none" },
    },
    config = function(_, opts)
      require("claudecode").setup(opts)
      start_bridge()
    end,
  },
}
