return {
  'NeogitOrg/neogit',
  dependencies = {
    'nvim-lua/plenary.nvim', -- required
    'sindrets/diffview.nvim', -- optional - Diff integration
    'folke/snacks.nvim',
  },
  keys = {
    { '<leader>gs', ':Neogit<CR>', desc = 'Status' },
    { '<leader>gc', ':Neogit commit <CR>', desc = 'Commit' },
    { '<leader>gp', ':Neogit push <CR>', desc = 'Push' },
    { '<leader>gl', ':Neogit pull <CR>', desc = 'Pull' },
    { '<leader>gb', ':Neogit branch <CR>', desc = 'Branch' },
    { '<leader>gd', ':DiffviewOpen <CR>', desc = 'Diff' },
  },
}
