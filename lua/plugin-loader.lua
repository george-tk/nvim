-- plugin_loader.lua: Manages Neovim plugins with lazy.nvim

-- Bootstrap lazy.nvim if it's not already installed.
local lazypath = vim.fn.stdpath 'data' .. '/lazy/lazy.nvim'

if not (vim.uv or vim.loop).fs_stat(lazypath) then
  local lazyrepo = 'https://github.com/folke/lazy.nvim.git'
  local clone_cmd = { 'git', 'clone', '--filter=blob:none', '--branch=stable', lazyrepo, lazypath }
  local success, stderr = pcall(vim.fn.system, clone_cmd)

  if not success or vim.v.shell_error ~= 0 then
    -- Error cloning lazy.nvim (e.g., no git, network issues)
    error('Error cloning lazy.nvim:\n' .. (stderr or 'Unknown error during git clone.'))
  end
end

-- Add lazy.nvim to Neovim's runtime path so it can be `required`.
---@diagnostic disable-next-line: undefined-field
vim.opt.rtp:prepend(lazypath)

---

-- Configure and install plugins using lazy.nvim.
-- Run `:Lazy` to check plugin status.

-- Custom icons for lazy.nvim UI if Nerd Font is not available.
local default_icons = {
  cmd = '⌘',
  config = '🛠 ',
  event = '📅',
  ft = '📂',
  init = '⚙',
  is_pinned = '◍',
  keys = '🗝 ',
  plugin = '🔌',
  runtime = '💻',
  require = '🌙',
  source = '📄',
  start = '🚀',
  task = '📌',
  lazy = '💤 ',
}

require('lazy').setup({
  -- Import all plugin specifications from files in the 'lua/plugins/' directory.
  { import = 'plugins' },
}, {
  ui = {
    icons = vim.g.have_nerd_font and {} or default_icons,
  },
})

-- The line beneath this is called `modeline`. See `:help modeline`
-- vim: ts=2 sts=2 sw=2 et
