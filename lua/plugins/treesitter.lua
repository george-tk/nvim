return {
  {
    'nvim-treesitter/nvim-treesitter',
    lazy = false,
    build = ':TSUpdate',
    main = 'nvim-treesitter',
    opts = {
      ensure_installed = { 'bash', 'c', 'diff', 'html', 'lua', 'luadoc', 'markdown', 'markdown_inline', 'query', 'vim', 'vimdoc', 'python' },
      auto_install = true,
      highlight = {
        enable = true,
        additional_vim_regex_highlighting = { 'ruby' },
      },
      indent = { enable = true, disable = { 'ruby' } },
    },
    vim.keymap.set('n', 'gC', function()
      require('treesitter-context').go_to_context(vim.v.count1)
    end, { desc = '[G]o to [C]ontext', silent = true }),
  },

  {
    'nvim-treesitter/nvim-treesitter-textobjects',
    lazy = false,
    dependencies = { 'nvim-treesitter/nvim-treesitter' },
    config = function()
      require('nvim-treesitter-textobjects').setup {
        select = {
          enable = true,
          lookahead = true,
        },
        move = {
          enable = true,
          set_jumps = true,
        },
      }

      -- Define Selection keymaps (visual and operator-pending modes)
      local select = require('nvim-treesitter-textobjects.select')
      local select_maps = {
        ['af'] = '@function.outer',
        ['if'] = '@function.inner',
        ['ac'] = '@class.outer',
        ['ic'] = '@class.inner',
        ['ai'] = '@conditional.outer',
        ['ii'] = '@conditional.inner',
        ['al'] = '@loop.outer',
        ['il'] = '@loop.inner',
      }
      for lhs, rhs in pairs(select_maps) do
        vim.keymap.set({ 'x', 'o' }, lhs, function()
          select.select_textobject(rhs, 'textobjects')
        end, { desc = 'Select ' .. rhs })
      end

      -- Define Move keymaps (normal, visual, and operator-pending modes)
      local move = require('nvim-treesitter-textobjects.move')
      local move_maps = {
        [']f'] = { fn = move.goto_next_start, query = '@function.outer', desc = 'Next function start' },
        [']F'] = { fn = move.goto_next_end, query = '@function.outer', desc = 'Next function end' },
        ['[f'] = { fn = move.goto_previous_start, query = '@function.outer', desc = 'Prev function start' },
        ['[F'] = { fn = move.goto_previous_end, query = '@function.outer', desc = 'Prev function end' },

        [']c'] = { fn = move.goto_next_start, query = '@class.outer', desc = 'Next class start' },
        [']C'] = { fn = move.goto_next_end, query = '@class.outer', desc = 'Next class end' },
        ['[c'] = { fn = move.goto_previous_start, query = '@class.outer', desc = 'Prev class start' },
        ['[C'] = { fn = move.goto_previous_end, query = '@class.outer', desc = 'Prev class end' },

        [']i'] = { fn = move.goto_next_start, query = '@conditional.outer', desc = 'Next conditional start' },
        [']I'] = { fn = move.goto_next_end, query = '@conditional.outer', desc = 'Next conditional end' },
        ['[i'] = { fn = move.goto_previous_start, query = '@conditional.outer', desc = 'Prev conditional start' },
        ['[I'] = { fn = move.goto_previous_end, query = '@conditional.outer', desc = 'Prev conditional end' },

        [']l'] = { fn = move.goto_next_start, query = '@loop.outer', desc = 'Next loop start' },
        [']L'] = { fn = move.goto_next_end, query = '@loop.outer', desc = 'Next loop end' },
        ['[l'] = { fn = move.goto_previous_start, query = '@loop.outer', desc = 'Prev loop start' },
        ['[L'] = { fn = move.goto_previous_end, query = '@loop.outer', desc = 'Prev loop end' },
      }
      for lhs, val in pairs(move_maps) do
        vim.keymap.set({ 'n', 'x', 'o' }, lhs, function()
          val.fn(val.query, 'textobjects')
        end, { desc = val.desc })
      end
    end,
  },

  {
    'nvim-treesitter/nvim-treesitter-context',
    event = 'VeryLazy',
    opts = { multiline_threshold = 1 },
  },
}
