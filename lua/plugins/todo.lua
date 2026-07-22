return {
  'george-tk/todo-picker',
  dependencies = {
    'folke/snacks.nvim',
  },
  opts = {}, -- This automatically configures and runs setup()
  keys = {
    { '<leader>tt', ':TodoList<CR>', desc = 'ToDo List' },
    { '<leader>tb', ':TodoBoard<CR>', desc = 'Todo Board' },
    { '<leader>tn', ':TodoNew<CR>', desc = 'New ToDo' },
    { '<leader>tN', ':TodoLinkNew<CR>', desc = 'New Todo + Refference' },
    { '<leader>tr', ':TodoLink<CR>', desc = 'Refference Todo' },
    { '<leader>tj', ':TodoJump<CR>', desc = 'Jump to Todo' },
    { '<leader>tl', ':TodoLog<CR>', desc = 'Log' },
  },
}
