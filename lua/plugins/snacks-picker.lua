return {
  'folke/snacks.nvim',
  ---@type snacks.Config
  opts = {
    picker = {
      win = {
        input = {
          keys = {
            -- to close the picker on ESC instead of going to normal mode,
            ['<Esc>'] = { 'close', mode = { 'n', 'i' } },
            ['<Tab>'] = { 'list_down', mode = { 'i', 'n' } },
            ['<S-Tab>'] = { 'list_up', mode = { 'i', 'n' } },
          },
        },
      },
    },
  },
  keys = {
    {
      '<leader>ff',
      function()
        Snacks.picker.files {
          filter = {
            paths = {
              [vim.fn.getcwd()] = true,
            },
          },
        }
      end,
      desc = 'files',
    },
    {
      '<leader>fb',
      function()
        Snacks.picker.buffers()
      end,
      desc = 'buffers',
    },
    {
      '<leader>ss',
      function()
        Snacks.picker.spelling {
          layout = { layout = { relative = 'cursor', height = 5, min_height = 10, min_width = 18, width = 0.1 }, backdrop = false },
        }
      end,
      desc = 'spelling suggestion',
    },
    {
      '<leader>fr',
      function()
        Snacks.picker.resume()
      end,
      desc = 'resume',
    },
    {
      '<leader>fh',
      function()
        Snacks.picker.help()
      end,
      desc = 'help',
    },
    {
      '<leader>fk',
      function()
        Snacks.picker.keymaps { layout = { preview = false } }
      end,
      desc = 'keymaps',
    },
    {
      '<leader>fp',
      function()
        Snacks.picker.pickers()
      end,
      desc = 'pickers',
    },
    {
      '<leader>fwb',
      function()
        Snacks.picker.lines()
      end,
      desc = 'current buffer',
    },
    {
      '<leader>fwB',
      function()
        Snacks.picker.grep_buffers()
      end,
      desc = 'buffers',
    },
    {
      '<leader>fwd',
      function()
        Snacks.picker.grep()
      end,
      desc = 'directory',
    },
    {
      '<leader>fcw',
      function()
        Snacks.picker.grep_word()
      end,
      desc = 'word',
      mode = { 'n', 'x' },
    },
    {
      '<leader>fcd',
      function()
        Snacks.picker.lsp_definitions()
      end,
      desc = 'definition',
    },
    {
      '<leader>fcD',
      function()
        Snacks.picker.lsp_declarations()
      end,
      desc = 'declaration',
    },
    {
      '<leader>fcr',
      function()
        Snacks.picker.lsp_references()
      end,
      nowait = true,
      desc = 'references',
    },
    {
      '<leader>fci',
      function()
        Snacks.picker.lsp_implementations()
      end,
      desc = 'implimentation',
    },
    {
      '<leader>fct',
      function()
        Snacks.picker.lsp_type_definitions()
      end,
      desc = 'type',
    },
  },
}
