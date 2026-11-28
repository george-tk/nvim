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
          win = {
            input = {
              keys = {
                ['<C-j>'] = {
                  function()
                    vim.cmd 'stopinsert'
                    _G.BottomPanel.toggle_active()
                  end,
                  mode = { 'i', 'n' },
                  desc = 'Bottom Output',
                },
                ['<M-h>'] = {
                  function()
                    _G.smart_resize_width(-3)
                  end,
                  mode = { 'i', 'n' },
                  desc = 'Expand Explorer',
                },
                ['<M-l>'] = {
                  function()
                    _G.smart_resize_width(3)
                  end,
                  mode = { 'i', 'n' },
                  desc = 'Shrink Explorer',
                },
              },
            },
            list = {
              keys = {
                ['<C-j>'] = {
                  function()
                    _G.BottomPanel.toggle_active()
                  end,
                  mode = { 'n' },
                  desc = 'Bottom Output',
                },
                ['<M-h>'] = {
                  function()
                    _G.smart_resize_width(-3)
                  end,
                  mode = { 'n' },
                  desc = 'Expand Explorer',
                },
                ['<M-l>'] = {
                  function()
                    _G.smart_resize_width(3)
                  end,
                  mode = { 'n' },
                  desc = 'Shrink Explorer',
                },
              },
            },
          },
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
