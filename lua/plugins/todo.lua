return {
  'george-tk/todo-picker',
  dependencies = {
    'folke/snacks.nvim',
  },
  opts = {}, -- This automatically configures and runs setup()
  keys = {
    { '<leader>tt', ':TodoList<CR>', desc = 'Todo List' },
    { '<leader>tb', ':TodoBoard<CR>', desc = 'Todo Board' },
    { '<leader>tn', ':TodoNew<CR>', desc = 'New Todo' },
    { '<leader>tN', ':TodoLinkNew<CR>', desc = 'New Todo Reference' },
    { '<leader>tr', ':TodoLink<CR>', desc = 'Reference Todo' },
    { '<leader>tj', ':TodoJump<CR>', desc = 'Jump to Todo' },
    { '<leader>tl', ':TodoLog<CR>', desc = 'Todo Log' },
  },
}
