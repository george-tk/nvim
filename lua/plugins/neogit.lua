return {
  'NeogitOrg/neogit',
  dependencies = {
    'nvim-lua/plenary.nvim', -- required
    'sindrets/diffview.nvim', -- optional - Diff integration
    'folke/snacks.nvim',
  },
  keys = {
    { '<leader>gg', ':Neogit<CR>', desc = 'Status' },
    { '<leader>gs', ':Neogit<CR>', desc = 'Status' },
    { '<leader>gc', ':Neogit commit <CR>', desc = 'Commit' },
    { '<leader>gp', ':Neogit pull <CR>', desc = 'Pull' },
    { '<leader>gP', ':Neogit push <CR>', desc = 'Push' },
    { '<leader>gb', ':Neogit branch <CR>', desc = 'Branch' },
    { '<leader>gd', ':DiffviewOpen <CR>', desc = 'Diff' },
  },
}
