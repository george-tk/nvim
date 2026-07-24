return {
  'folke/snacks.nvim',
  opts = {
    zen = {
      -- Keep defaults: centers text, wraps, hides status line, line numbers, etc.
    },
  },
  keys = {
    {
      '<leader>z',
      function()
        Snacks.zen()
      end,
      desc = 'Toggle Zen Mode',
    },
  },
}
