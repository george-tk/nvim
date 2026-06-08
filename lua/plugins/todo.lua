return {
  'george-tk/todo-picker', -- Or local path/repository URL
  dependencies = {
    'folke/snacks.nvim',
  },
  opts = {}, -- This automatically configures and runs setup()
  keys = {
    { '<leader>ft', ':Todo<CR>', desc = 'All TODOs' },
  },
}
