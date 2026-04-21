return {
  'echasnovski/mini.nvim',
  version = false,
  config = function()
    require('mini.files').setup {}

    require('mini.icons').setup()
  end,
  keys = {
    {
      '<leader>e',
      function()
        require('mini.files').open()
      end,
      desc = '[e]xplore',
    },
  },
}
