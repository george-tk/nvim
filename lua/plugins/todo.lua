return {
  'george-tk/todo-picker',
  dependencies = {
    'folke/snacks.nvim',
  },
  opts = {}, -- This automatically configures and runs setup()
  keys = {
    { '<leader>TT', ':TodoList<CR>', desc = 'Todo List' },
    { '<leader>Tb', ':TodoBoard<CR>', desc = 'Todo Board' },
    { '<leader>Tn', ':TodoNew<CR>', desc = 'New Todo' },
    { '<leader>TN', ':TodoLinkNew<CR>', desc = 'New Todo Reference' },
    { '<leader>Tr', ':TodoLink<CR>', desc = 'Reference Todo' },
    { '<leader>Tj', ':TodoJump<CR>', desc = 'Jump to Todo' },
    { '<leader>Tl', ':TodoLog<CR>', desc = 'Todo Log' },
  },
}
