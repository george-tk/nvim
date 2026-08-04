return {
  'folke/snacks.nvim',
  priority = 1000,
  lazy = false,
  opts = {
    picker = {
      enabled = true,
      win = {
        input = {
          keys = {
            ['<Tab>'] = { 'list_down', mode = { 'i', 'n' } },
            ['<S-Tab>'] = { 'list_up', mode = { 'i', 'n' } },
            ['<C-j>'] = { function() vim.cmd('stopinsert'); _G.BottomPanel.toggle_active() end, mode = { 'i', 'n' }, desc = 'Bottom Output' },
            ['<M-h>'] = { function() _G.smart_resize_width(-3) end, mode = { 'i', 'n' }, desc = 'Expand Explorer' },
            ['<M-l>'] = { function() _G.smart_resize_width(3) end, mode = { 'i', 'n' }, desc = 'Shrink Explorer' },
          },
        },
        list = {
          keys = {
            ['<Tab>'] = { 'list_down', mode = { 'n', 'x' } },
            ['<S-Tab>'] = { 'list_up', mode = { 'n', 'x' } },
            ['<C-j>'] = { function() _G.BottomPanel.toggle_active() end, mode = { 'n' }, desc = 'Bottom Output' },
            ['<M-h>'] = { function() _G.smart_resize_width(-3) end, mode = { 'n' }, desc = 'Expand Explorer' },
            ['<M-l>'] = { function() _G.smart_resize_width(3) end, mode = { 'n' }, desc = 'Shrink Explorer' },
          },
        },
      },
      sources = {
        files = { hidden = true, ignored = true },
        grep = { hidden = true, ignored = true },
      },
    },
    explorer = { enabled = true },
    dashboard = { enabled = true },
    terminal = { enabled = true },
  },
  keys = {
    -- Meta Picker & Notifications
    {
      '<leader>fa',
      function()
        Snacks.picker.pickers()
      end,
      desc = 'All Pickers',
    },
    {
      '<leader>fn',
      function()
        Snacks.picker.notifications()
      end,
      desc = 'Notifications',
    },

    -- Core File & Buffer Pickers
    {
      '<leader>ff',
      function()
        Snacks.picker.files()
      end,
      desc = 'Find Files',
    },
    {
      '<leader>fb',
      function()
        Snacks.picker.buffers()
      end,
      desc = 'Open Buffers',
    },
    {
      '<leader>fr',
      function()
        Snacks.picker.recent()
      end,
      desc = 'Recent Files',
    },
    {
      '<leader>fc',
      function()
        Snacks.picker.files { cwd = vim.fn.stdpath 'config' }
      end,
      desc = 'Neovim Config',
    },
    {
      '<leader>fp',
      function()
        Snacks.picker.projects()
      end,
      desc = 'Projects',
    },
    {
      '<leader>fh',
      function()
        Snacks.picker.help()
      end,
      desc = 'Help Tags',
    },
    {
      '<leader>fk',
      function()
        Snacks.picker.keymaps()
      end,
      desc = 'Keymaps',
    },

    -- Word & Grep Pickers (All Uniform 2-Key Length, Zero Prefix Collisions)
    {
      '<leader>fg',
      function()
        Snacks.picker.grep()
      end,
      desc = 'Word in Workspace',
    },
    {
      '<leader>fl',
      function()
        Snacks.picker.lines()
      end,
      desc = 'Word in Current Buffer',
    },
    {
      '<leader>fo',
      function()
        Snacks.picker.grep_buffers()
      end,
      desc = 'Word in Open Buffers',
    },
    {
      '<leader>fw',
      function()
        Snacks.picker.grep_word()
      end,
      desc = 'Word Under Cursor',
    },

    -- Diagnostics Picker
    {
      '<leader>fd',
      function()
        Snacks.picker.diagnostics()
      end,
      desc = 'Diagnostics',
    },

    -- Spelling Picker (Autocomplete-style clean dropdown at cursor with zero prompt icons or counts)
    {
      '<leader>ss',
      function()
        Snacks.picker.spelling {
          title = '',
          prompt = '',
          icon = '',
          layout = {
            backdrop = false,
            layout = {
              box = 'vertical',
              backdrop = false,
              relative = 'cursor',
              row = 1,
              col = 0,
              width = 22,
              min_width = 18,
              height = 7,
              min_height = 5,
              border = 'none',
              { win = 'input', height = 1, border = 'none', title = '', footer = '' },
              { win = 'list', border = 'none' },
            },
          },
        }
      end,
      desc = 'Spelling Suggestions',
    },
  },
}
