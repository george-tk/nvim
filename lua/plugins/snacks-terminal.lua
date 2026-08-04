return {
  'folke/snacks.nvim',
  opts = {
    terminal = {
      enabled = true,
      win = {
        position = 'bottom',
        relative = 'win',
        height = 0.4,
        wo = {
          winbar = '',
        },
      },
    },
  },
  keys = {
    {
      '<leader>/',
      function()
        if _G.BottomPanel then
          _G.BottomPanel.open_terminal(vim.v.count1)
        else
          Snacks.terminal.toggle(nil, { count = vim.v.count1 })
        end
      end,
      desc = 'Terminal',
      mode = { 'n', 't' },
    },
    {
      '<C-/>',
      function()
        if _G.BottomPanel then
          _G.BottomPanel.open_terminal(vim.v.count1)
        else
          Snacks.terminal.toggle(nil, { count = vim.v.count1 })
        end
      end,
      desc = 'Terminal',
      mode = { 'n', 't' },
    },
  },
}
