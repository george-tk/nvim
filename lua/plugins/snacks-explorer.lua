return {
  'folke/snacks.nvim',
  opts = {
    explorer = {
      replace_netrw = false,
    },
    picker = {
      sources = {
        explorer = {
          hidden = true,
          ignored = true,
          layout = { layout = { position = 'right', width = 35 } },
          jump = { close = false },
          auto_close = false,
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
          Snacks.explorer {
            hidden = true,
            ignored = true,
            layout = { layout = { position = 'right', width = 35 } },
          }
        end
      end,
      desc = 'File Explorer',
    },
  },
}
