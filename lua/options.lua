-- options.lua

-- Aliases for Neovim options
local o = vim.opt
local g = vim.g

---
-- General UI & Editor Basics
-------------------------------------------------------------------------------
o.termguicolors = true -- True colors
o.number = true -- Line numbers
o.relativenumber = true -- Relative line numbers
o.mouse = 'a' -- Mouse support
o.showmode = false -- Hide mode messages
o.cmdheight = 0 -- Command line height
o.pumheight = 10 -- Completion menu height
o.clipboard = 'unnamedplus' -- Allow for copy and pasting
---
-- Indentation
-------------------------------------------------------------------------------
o.expandtab = true -- Spaces for tabs
o.tabstop = 2 -- Tab width
o.shiftwidth = 2 -- Indent width
o.softtabstop = 2 -- Tab key behavior
o.autoindent = true -- Auto-indent

---
-- Editing Enhancements
-------------------------------------------------------------------------------
o.breakindent = true -- Wrapped line indent
o.ignorecase = true -- Case-insensitive search
o.smartcase = true -- Smart case search
o.inccommand = 'split' -- Live substitution preview
o.cursorline = true -- Highlight current line
o.confirm = true -- Confirm unsaved close

---
-- File Handling & History
-------------------------------------------------------------------------------
o.undofile = true -- Save undo history
o.swapfile = false -- Disable swap files (no crash recovery)

---
-- Visual Layout
-------------------------------------------------------------------------------
o.numberwidth = 2 -- Minimum width for line numbers (default 4)
o.signcolumn = 'yes' -- Always show signcolumn
o.splitright = true -- Vertical splits right
o.splitbelow = true -- Horizontal splits below
o.equalalways = false -- Don't auto-resize splits to equal size on open/close
o.splitkeep = 'screen' -- Keep cursor and screen position on split
o.scrolloff = 8 -- Scroll context lines
-- o.list = true -- Show invisible chars
-- o.listchars = { -- Invisible char display
--   tab = '» ',
--   trail = '·',
--   nbsp = '␣',
-- }

---
-- Spelling
-------------------------------------------------------------------------------
o.spell = true -- Enable spell check
o.spelllang = { 'en_gb' } -- British English

---
-- Folding (Tree-sitter based)
-------------------------------------------------------------------------------
o.foldcolumn = '0' -- Disable separate fold column (folds shown in statuscolumn)
o.foldmethod = 'expr' -- Expression folding
o.foldexpr = 'v:lua.vim.treesitter.foldexpr()' -- Treesitter folding
o.foldlevel = 99 -- All folds open
o.foldenable = true -- Enable folding
o.foldtext = '' -- Empty fold text
o.foldopen = 'mark,percent,quickfix,search,tag,undo' -- Auto-open folds (except horizontal movement)
o.fillchars = { -- Fold fill characters
  foldopen = '',
  foldclose = '',
  fold = ' ',
  foldsep = ' ',
  diff = ' ',
  eob = ' ',
}

---
-- Global Flags & Minor Optimizations
-------------------------------------------------------------------------------
g.have_nerd_font = true -- Nerd Font flag
g.markdown_recommended_style = 0 -- prevents rewrite of markdown style

---
-- Custom Window Title
-------------------------------------------------------------------------------
o.title = true -- Enable window title setting
o.titlestring = "%{expand('%:t') == '' ? '[No Name]' : expand('%:p:h:t') . ': ' . expand('%:t')}"
