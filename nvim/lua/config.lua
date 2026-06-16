-- ~/.config/nvim/lua/config.lua
-- Core Neovim settings and keymaps

local opt = vim.opt
local g = vim.g
local keymap = vim.keymap

-- Leader key
g.mapleader = " "
g.maplocalleader = " "

-- Desactivar netrw (usamos nvim-tree como explorador; debe ir ANTES de cargar plugins)
g.loaded_netrw = 1
g.loaded_netrwPlugin = 1

-- Basic settings
opt.number = true
opt.relativenumber = true
opt.tabstop = 2
opt.shiftwidth = 2
opt.expandtab = true
opt.autoindent = true
opt.wrap = false
opt.ignorecase = true
opt.smartcase = true
opt.cursorline = true
opt.termguicolors = true
opt.background = "dark"
opt.signcolumn = "yes"
opt.backspace = "indent,eol,start"
opt.clipboard:append("unnamedplus")
opt.splitright = true
opt.splitbelow = true
opt.swapfile = false
opt.backup = false
opt.undofile = true
opt.scrolloff = 8
opt.sidescrolloff = 8
opt.mouse = "a"
opt.smartindent = true

-- Quality of life (Neovim 0.11)
opt.winborder = "rounded"   -- bordes redondeados en ventanas flotantes (hover, etc.)
opt.confirm = true          -- preguntar al salir con cambios sin guardar (en vez de fallar)
opt.inccommand = "split"    -- vista previa en vivo de :substitute
opt.updatetime = 250        -- diagnósticos / gitsigns más ágiles
opt.timeoutlen = 400        -- ventana para atajos compuestos (which-key)
opt.completeopt = "menu,menuone,noselect"

-- Search settings
opt.hlsearch = false
opt.incsearch = true

-- Limpiar el resaltado de búsqueda con <Esc>
keymap.set("n", "<Esc>", "<cmd>nohlsearch<CR>", { desc = "Clear search highlight" })

-- Toggle números: absoluto (real en todas las líneas) <-> híbrido (real solo en el cursor)
-- Aplica a la ventana actual y a los archivos que abras después (vim.opt = global + local).
keymap.set("n", "<leader>un", function()
  local hybrid = not vim.opt.relativenumber:get()
  vim.opt.relativenumber = hybrid -- number queda siempre ON
  vim.notify("Números: " .. (hybrid and "híbrido (real solo en cursor)" or "absoluto (real en todas)"))
end, { desc = "Toggle números: absoluto/híbrido" })

-- Essential keymaps
keymap.set("i", "jk", "<ESC>", { desc = "Exit insert mode with jk" })

-- Clear search highlights
keymap.set("n", "<leader>nh", ":nohl<CR>", { desc = "Clear search highlights" })

-- Window management
keymap.set("n", "<leader>sv", "<C-w>v", { desc = "Split window vertically" })
keymap.set("n", "<leader>sh", "<C-w>s", { desc = "Split window horizontally" })
keymap.set("n", "<leader>se", "<C-w>=", { desc = "Make splits equal size" })
keymap.set("n", "<leader>sx", "<cmd>close<CR>", { desc = "Close current split" })

-- Navegar entre ventanas con Ctrl + h/j/k/l (1 pulsación).
-- <C-h> hace focus a la barra lateral (está a la izquierda); <C-l> vuelve al archivo.
keymap.set("n", "<C-h>", "<C-w>h", { desc = "Ir a ventana izquierda (sidebar)" })
keymap.set("n", "<C-j>", "<C-w>j", { desc = "Ir a ventana inferior" })
keymap.set("n", "<C-k>", "<C-w>k", { desc = "Ir a ventana superior" })
keymap.set("n", "<C-l>", "<C-w>l", { desc = "Ir a ventana derecha" })

-- Ciclar entre splits con Ctrl + ] (sin pensar en la dirección): salta al siguiente
-- split y, al llegar al último, vuelve al primero (loop). Útil porque aquí no hay j/k.
-- Nota: Ctrl+[ NO se puede usar; el terminal lo envía idéntico a <Esc>, así que
-- pisaría la tecla Escape. Por eso el ciclo va con una sola tecla.
keymap.set("n", "<C-]>", "<C-w>w", { desc = "Siguiente split (ciclar/loop)" })
-- Ciclo hacia atrás. Ctrl+[ es imposible en la terminal (== <Esc>), así que
-- Karabiner-Elements lo remapea a F13 (solo en Warp/Ghostty) y aquí mapeamos F13.
keymap.set("n", "<F13>", "<C-w>W", { desc = "Split anterior (ciclar/loop, viene de Ctrl+[)" })

-- Redimensionar splits con Ctrl + flecha (en terminal ⌘ no se puede capturar).
keymap.set("n", "<C-Up>", "<cmd>resize +2<CR>", { desc = "Más alto" })
keymap.set("n", "<C-Down>", "<cmd>resize -2<CR>", { desc = "Más bajo" })
keymap.set("n", "<C-Left>", "<cmd>vertical resize -2<CR>", { desc = "Más angosto" })
keymap.set("n", "<C-Right>", "<cmd>vertical resize +2<CR>", { desc = "Más ancho" })

-- Tab management
keymap.set("n", "<leader>to", "<cmd>tabnew<CR>", { desc = "Open new tab" })
keymap.set("n", "<leader>tx", "<cmd>tabclose<CR>", { desc = "Close current tab" })
keymap.set("n", "<leader>tn", "<cmd>tabn<CR>", { desc = "Go to next tab" })
keymap.set("n", "<leader>tp", "<cmd>tabp<CR>", { desc = "Go to previous tab" })

-- Traductor (translate-shell) — resolver una palabra sin salir de Neovim.
-- Convive con los atajos de pestañas de arriba (to/tx/tn/tp). El resultado sale en
-- un float bajo el cursor. Por defecto traduce EN<->ES en ambos sentidos a la vez.
keymap.set("n", "<leader>tt", function() require("translate").prompt() end,
  { desc = "Traducir: pedir palabra (ES+EN)" })
keymap.set("n", "<leader>tw", function() require("translate").cword() end,
  { desc = "Traducir palabra bajo el cursor (ES+EN)" })
keymap.set("n", "<leader>ts", function() require("translate").prompt("es") end,
  { desc = "Traducir → español" })
keymap.set("n", "<leader>te", function() require("translate").prompt("en") end,
  { desc = "Traducir → inglés" })
keymap.set("n", "<leader>tl", function() require("translate").prompt_lang() end,
  { desc = "Traducir: elegir idioma destino" })
keymap.set("x", "<leader>tt", function() require("translate").selection() end,
  { desc = "Traducir selección (ES+EN)" })

-- Buffer navigation
keymap.set("n", "<S-h>", "<cmd>bprevious<CR>", { desc = "Previous buffer" })
keymap.set("n", "<S-l>", "<cmd>bnext<CR>", { desc = "Next buffer" })

-- Better up/down
keymap.set("n", "j", "v:count == 0 ? 'gj' : 'j'", { expr = true, silent = true })
keymap.set("n", "k", "v:count == 0 ? 'gk' : 'k'", { expr = true, silent = true })

-- Move text up and down
keymap.set("v", "J", ":m '>+1<CR>gv=gv", { desc = "Move text down" })
keymap.set("v", "K", ":m '<-2<CR>gv=gv", { desc = "Move text up" })

-- Mover líneas como un pro: <leader>m + j/k
-- Por defecto mueve 1 línea. Si antepones un número, mueve esa cantidad:
--   <space>mj        -> baja 1 línea
--   3<space>mj       -> baja 3 líneas
--   5<space>mk       -> sube 5 líneas
-- El número escrito antes del atajo queda en vim.v.count1 (=1 si no escribes nada).
-- Se recorta a los bordes del buffer para que nunca falle el comando :move,
-- y se reindenta la línea movida (==) igual que J/K en modo visual.
local function move_line(direction)
  local count = vim.v.count1
  local cur = vim.fn.line(".")
  local last = vim.fn.line("$")
  if direction == "down" then
    local target = math.min(cur + count, last) -- no pasar del final
    if target == cur then return end           -- ya está abajo del todo
    vim.cmd("move " .. target)
  else
    local target = math.max(cur - count, 1)     -- no pasar del principio
    if target == cur then return end            -- ya está arriba del todo
    vim.cmd("move " .. (target - 1))            -- :move 0 = al principio del buffer
  end
  vim.cmd("normal! ==") -- reindentar la línea en su nueva posición
end

keymap.set("n", "<leader>mj", function() move_line("down") end, { desc = "Mover línea abajo (N opcional)" })
keymap.set("n", "<leader>mk", function() move_line("up") end, { desc = "Mover línea arriba (N opcional)" })

-- Better indenting
keymap.set("v", "<", "<gv")
keymap.set("v", ">", ">gv")

-- ¿Arrancamos en modo directorio? (nvim . / nvim carpeta, NO nvim archivo)
do
  local args = vim.fn.argv()
  g.started_in_dir = (#args == 1 and vim.fn.isdirectory(args[1]) == 1)
end

-- Si arrancaste con `nvim .`, la barra lateral está cerrada y cierras el último
-- archivo con :q/:q!, volver al explorador (a pantalla completa) en vez de salir
-- de nvim. Con `nvim archivo` o con varias ventanas, :q se comporta normal.
vim.api.nvim_create_autocmd("QuitPre", {
  group = vim.api.nvim_create_augroup("dir_mode_tree_fallback", { clear = true }),
  callback = function()
    if not g.started_in_dir then return end
    local ok, api = pcall(require, "nvim-tree.api")
    if not ok or api.tree.is_visible() then return end -- el árbol ya está abierto
    if vim.bo.buftype ~= "" then return end            -- solo archivos normales
    local normal_wins = vim.tbl_filter(function(w)
      return vim.api.nvim_win_get_config(w).relative == "" -- ignora flotantes
    end, vim.api.nvim_list_wins())
    if #normal_wins ~= 1 then return end -- solo si es la última ventana
    local file_win = vim.api.nvim_get_current_win()
    api.tree.open()                        -- abre el árbol (queda como única ventana => full screen)
    vim.api.nvim_set_current_win(file_win) -- vuelve al archivo para que :q cierre a ESE
  end,
})

-- :Q cierra nvim por completo (qall). :Q! fuerza (descarta cambios sin guardar).
-- Útil porque en modo `nvim .` un :q normal vuelve al explorador en vez de salir.
vim.api.nvim_create_user_command("Q", function(o)
  vim.cmd("qa" .. (o.bang and "!" or ""))
end, { bang = true, desc = "Cerrar nvim por completo (:Q! fuerza)" })