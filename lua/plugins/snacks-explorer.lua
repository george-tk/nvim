return {
  'folke/snacks.nvim',
  opts = {
    picker = {
      sources = {
        explorer = {
          layout = { layout = { position = 'right', width = 25 } },
          jump = { close = true },
        },
      },
    },
  },
  keys = {
    {
      '<leader>e',
      function()
        if _G.RightPanel then
          _G.RightPanel.open_explorer()
        else
          Snacks.explorer({ layout = { layout = { position = 'right', width = 25 } } })
        end
      end,
      desc = 'File Explorer',
    },
  },
}
