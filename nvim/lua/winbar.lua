-- ~/.config/nvim/lua/winbar.lua
-- Winbar por ventana: a la IZQUIERDA el archivo abierto (con color de estado tipo
-- VSCode) y a la DERECHA los cambios de git (+a verde, ~c amarillo, -d rojo).
-- Hace falta porque lualine usa globalstatus=true (una sola statusline para todo),
-- así que sin esto no se distingue qué archivo hay en cada split (p.ej. en un diff).

local M = {}

local icon_groups = {} -- caché de grupos de icono (color devicons, fondo transparente)

-- Lee el fg de un grupo de resaltado; si no existe, usa el color de respaldo.
local function fg_of(group, fallback)
  local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = group, link = false })
  if ok and hl and hl.fg then
    return string.format("#%06x", hl.fg)
  end
  return fallback
end

-- Define los grupos del winbar a partir del tema activo: SOLO color de texto (fg),
-- sin fondo, para respetar la transparencia del tema. Se reaplican en cada ColorScheme.
local function setup_highlights()
  icon_groups = {} -- los colores cambian con el tema: invalida la caché
  local defs = {
    WinbarClean    = fg_of("Normal", "#cdd6f4"),          -- archivo sin cambios
    WinbarModified = fg_of("DiagnosticWarn", "#f9e2af"),  -- amarillo: modificado
    WinbarError    = fg_of("DiagnosticError", "#f38ba8"), -- rojo: con errores LSP
    WinbarPath     = fg_of("Comment", "#6c7086"),         -- carpeta padre (tenue)
    WinbarInactive = fg_of("Comment", "#6c7086"),         -- ventana sin foco (tenue)
    WinbarAdd      = fg_of("GitSignsAdd", "#a6e3a1"),      -- verde: +líneas
    WinbarChange   = fg_of("GitSignsChange", "#f9e2af"),  -- amarillo: ~líneas
    WinbarDelete   = fg_of("GitSignsDelete", "#f38ba8"),  -- rojo: -líneas
  }
  for name, color in pairs(defs) do
    vim.api.nvim_set_hl(0, name, { fg = color })
  end
  -- Base del winbar (huecos, padding y el separador %=): fondo transparente.
  vim.api.nvim_set_hl(0, "WinBar",   { fg = fg_of("Normal", "#cdd6f4") })
  vim.api.nvim_set_hl(0, "WinBarNC", { fg = fg_of("Comment", "#6c7086") })
end

-- Grupo para el icono: su color de devicons, sin fondo. Se cachea porque render()
-- corre en cada redibujado.
local function icon_hl_for(base_hl)
  local name = "Winbar_" .. base_hl
  if not icon_groups[name] then
    vim.api.nvim_set_hl(0, name, { fg = fg_of(base_hl, "#cdd6f4") })
    icon_groups[name] = true
  end
  return name
end

-- Escapa los '%' del nombre para que no se lean como formato de statusline.
local function esc(s)
  return (s:gsub("%%", "%%%%"))
end

-- Render del winbar de UNA ventana concreta. El id se "hornea" en la expresión de
-- cada ventana (ver refresh): g:actual_curwin no es fiable en el winbar, así que
-- sin el id explícito todas las ventanas mostrarían el buffer de la ventana activa.
function M.render(winid)
  local win = (winid and vim.api.nvim_win_is_valid(winid)) and winid or vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_win_get_buf(win)
  local active = win == vim.api.nvim_get_current_win()

  local fullname = vim.api.nvim_buf_get_name(buf)
  local filename = fullname ~= "" and vim.fn.fnamemodify(fullname, ":t") or "[Sin nombre]"
  local parent = fullname ~= "" and vim.fn.fnamemodify(fullname, ":h:t") or ""

  -- Estado de git de este buffer (lo provee gitsigns).
  local gs = vim.b[buf].gitsigns_status_dict or {}
  local added, changed, removed = gs.added or 0, gs.changed or 0, gs.removed or 0
  local dirty = vim.bo[buf].modified or (added + changed + removed) > 0

  -- Color del nombre: rojo (error LSP) > amarillo (modificado) > normal (limpio).
  local counts = vim.diagnostic.count(buf)
  local n_err = counts[vim.diagnostic.severity.ERROR] or 0
  local name_hl
  if not active then
    name_hl = "WinbarInactive"
  elseif n_err > 0 then
    name_hl = "WinbarError"
  elseif dirty then
    name_hl = "WinbarModified"
  else
    name_hl = "WinbarClean"
  end

  -- Icono (devicons): con su color si la ventana está activa; tenue si no.
  local icon_seg = ""
  local ok, devicons = pcall(require, "nvim-web-devicons")
  if ok and fullname ~= "" then
    local icon, icon_hl = devicons.get_icon(filename, vim.fn.fnamemodify(filename, ":e"), { default = true })
    if icon then
      icon_seg = string.format("%%#%s#%s %%*", active and icon_hl_for(icon_hl) or "WinbarInactive", icon)
    end
  end

  -- Izquierda: [icono] carpeta/archivo [● si hay cambios sin guardar]
  local left = icon_seg
  if parent ~= "" and parent ~= "." then
    left = left .. string.format("%%#WinbarPath#%s/%%*", esc(parent))
  end
  left = left .. string.format("%%#%s#%s%%*", name_hl, esc(filename))
  if vim.bo[buf].modified then
    left = left .. " %#WinbarModified#●%*"
  end

  -- Derecha: cambios de git.
  local parts = {}
  if added > 0 then parts[#parts + 1] = string.format("%%#WinbarAdd#+%d%%*", added) end
  if changed > 0 then parts[#parts + 1] = string.format("%%#WinbarChange#~%d%%*", changed) end
  if removed > 0 then parts[#parts + 1] = string.format("%%#WinbarDelete#-%d%%*", removed) end
  local right = table.concat(parts, " ")

  return " " .. left .. "%=" .. right .. " "
end

-- ¿La ventana debe llevar winbar? Solo archivos normales: no flotantes ni paneles
-- (nvim-tree, quickfix, terminal, help... todos tienen buftype distinto de "").
local function eligible(win)
  if vim.api.nvim_win_get_config(win).relative ~= "" then return false end
  return vim.bo[vim.api.nvim_win_get_buf(win)].buftype == ""
end

-- Asigna o limpia el winbar de cada ventana, horneando su id en la expresión.
-- Al ser opción global-local, poner "" en la local hace que caiga al valor global
-- (vacío) => sin winbar.
local function refresh()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_is_valid(win) then
      vim.wo[win].winbar = eligible(win)
        and string.format("%%{%%v:lua.require('winbar').render(%d)%%}", win)
        or ""
    end
  end
end

function M.setup()
  setup_highlights()
  local grp = vim.api.nvim_create_augroup("winbar", { clear = true })

  -- Reaplica los colores al cambiar de tema.
  vim.api.nvim_create_autocmd("ColorScheme", { group = grp, callback = setup_highlights })

  -- Asigna/limpia el winbar cuando cambia la ventana o el buffer.
  vim.api.nvim_create_autocmd(
    { "BufWinEnter", "WinEnter", "WinNew", "FileType", "TermOpen", "BufWritePost" },
    { group = grp, callback = refresh }
  )

  -- Refresca al instante cuando cambian diagnósticos o el estado de git.
  vim.api.nvim_create_autocmd("DiagnosticChanged", {
    group = grp,
    callback = function() pcall(vim.cmd, "redrawstatus!") end,
  })
  vim.api.nvim_create_autocmd("User", {
    group = grp,
    pattern = "GitSignsUpdate",
    callback = function() pcall(vim.cmd, "redrawstatus!") end,
  })

  refresh() -- ventanas ya abiertas al iniciar
end

return M
