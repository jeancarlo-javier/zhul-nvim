-- ~/.config/nvim/lua/translate.lua
-- Traductor en línea sin salir de Neovim. Usa translate-shell (`trans`) y muestra
-- el resultado en un float bajo el cursor. Pensado para resolver una palabra suelta
-- (EN<->ES) sin abrir el navegador ni perder el foco del trabajo.
--
-- Requiere el binario `trans`:  brew install translate-shell
--
-- API:
--   require("translate").translate(text, target)  -- target ej: "es", "en", "es+en"
--   require("translate").prompt(target)           -- pide la palabra y traduce
--   require("translate").prompt_lang()            -- pide idioma destino + palabra
--   require("translate").cword(target)            -- traduce la palabra bajo el cursor
--   require("translate").selection(target)        -- traduce la selección visual

local M = {}

-- Idioma(s) destino por defecto. "es+en" pide ambas direcciones en una sola llamada,
-- así nunca tienes que adivinar el sentido: una de las dos líneas es la que buscas.
M.default_target = "es+en"

-- Muestra el resultado en un float bajo el cursor. Se cierra solo al mover el cursor;
-- repite el atajo (o entra al float) para fijarlo y leer con calma.
local function show(lines)
  vim.lsp.util.open_floating_preview(lines, "", {
    border = "rounded",
    focusable = true,
    wrap = true,
    max_width = 80,
    close_events = { "CursorMoved", "CursorMovedI", "BufLeave", "InsertEnter" },
  })
end

-- Traduce `text` hacia `target` de forma asíncrona (no bloquea el editor).
function M.translate(text, target)
  text = vim.trim(text or "")
  if text == "" then
    vim.notify("Traductor: nada que traducir", vim.log.levels.WARN)
    return
  end
  if vim.fn.executable("trans") == 0 then
    vim.notify("Traductor: falta `trans` (brew install translate-shell)", vim.log.levels.ERROR)
    return
  end
  target = target or M.default_target
  vim.system(
    { "trans", "-b", ":" .. target, text },
    { text = true },
    vim.schedule_wrap(function(res)
      if res.code ~= 0 then
        vim.notify("Traductor: " .. vim.trim(res.stderr or "error de `trans`"), vim.log.levels.ERROR)
        return
      end
      local out = vim.split(vim.trim(res.stdout or ""), "\n", { trimempty = true })
      if #out == 0 then out = { "(sin resultado)" } end
      show({ text .. "  →  " .. table.concat(out, "  /  ") })
    end)
  )
end

-- Pide una palabra/frase por el prompt y la traduce (target opcional).
function M.prompt(target)
  local label = target and (" → " .. target) or ""
  vim.ui.input({ prompt = "Traducir" .. label .. ": " }, function(word)
    if word and vim.trim(word) ~= "" then M.translate(word, target) end
  end)
end

-- Primero pide el idioma destino (default es), luego la palabra. Equivale a tu idea
-- de "<leader>tt + lang + palabra" pero con valor por defecto para ir rápido.
function M.prompt_lang()
  vim.ui.input({ prompt = "Idioma destino (es/en/fr/de/…): ", default = "es" }, function(lang)
    if not lang or vim.trim(lang) == "" then return end
    M.prompt(vim.trim(lang))
  end)
end

-- Traduce la palabra bajo el cursor (cero tecleo).
function M.cword(target)
  M.translate(vim.fn.expand("<cword>"), target)
end

-- Traduce la selección visual sin pisar el registro del usuario.
function M.selection(target)
  local reg, regtype = vim.fn.getreg("z"), vim.fn.getregtype("z")
  vim.cmd('noautocmd normal! "zy')
  local text = vim.fn.getreg("z")
  vim.fn.setreg("z", reg, regtype)
  M.translate(text, target)
end

return M
