return {
  'folke/persistence.nvim',
  event = 'BufReadPre', -- this will only start session saving when an actual file was opened
  opts = {
    need = 0,
    -- add any custom options here
  }, -- load the session for the current directory
  -- select a session to load
  vim.keymap.set('n', '<leader>fs', function()
    require('persistence').select()
  end, { desc = 'session' }),
}
