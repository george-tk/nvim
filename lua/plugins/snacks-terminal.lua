return {
  'folke/snacks.nvim',
  opts = {
    terminal = {
      enabled = true,
      win = {
        position = 'bottom',
        relative = 'win',
        height = 0.38,
        wo = {
          winbar = '',
          winfixheight = true,
          winfixbuf = true,
        },
      },
    },
  },
  keys = {
    {
      '<leader>T',
      function()
        local count = vim.v.count > 0 and vim.v.count or nil
        if _G.BottomPanel then
          _G.BottomPanel.open_terminal(count)
        else
          Snacks.terminal.toggle(nil, { count = count or 1 })
        end
      end,
      desc = 'Terminal',
      mode = { 'n', 't' },
    },
    {
      '<C-/>',
      function()
        local count = vim.v.count > 0 and vim.v.count or nil
        if _G.BottomPanel then
          _G.BottomPanel.open_terminal(count)
        else
          Snacks.terminal.toggle(nil, { count = count or 1 })
        end
      end,
      desc = 'Terminal',
      mode = { 'n', 't' },
    },
  },
}
