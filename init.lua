-- Disable unused runtime plugins FIRST (before anything else loads)
vim.g.loaded_gzip = 1
vim.g.loaded_tar = 1
vim.g.loaded_tarPlugin = 1
vim.g.loaded_zip = 1
vim.g.loaded_zipPlugin = 1
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1
vim.g.loaded_netrwSettings = 1
vim.g.loaded_netrwFileHandlers = 1
vim.g.loaded_matchit = 1
vim.g.loaded_matchparen = 1
vim.g.loaded_2html_plugin = 1
vim.g.loaded_tutor_mode_plugin = 1
vim.g.loaded_spellfile_plugin = 1
vim.g.loaded_rplugin = 1
vim.g.loaded_editorconfig = 1 -- Disable editorconfig for faster startup

if vim.g.vscode then
  vim.keymap.set('n', '<Esc>', '<cmd>nohlsearch<CR>')
else
  -- Remap Keys
  require 'key-mapping'
  -- Core Options
  require 'options'
  -- Plugins
  require 'plugin-loader'
  -- Auto Commands
  require 'auto-commands'
end
