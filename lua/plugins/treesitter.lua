return {
  {
    'nvim-treesitter/nvim-treesitter',
    lazy = false,
    build = ':TSUpdate',
    config = function()
      local ts = require('nvim-treesitter')
      ts.setup()

      -- Ensure core parsers are installed
      ts.install {
        'bash',
        'c',
        'diff',
        'html',
        'lua',
        'luadoc',
        'markdown',
        'markdown_inline',
        'query',
        'vim',
        'vimdoc',
        'python',
        'sql',
      }

      -- Enable Treesitter highlighting and indenting natively in Neovim 0.12+
      vim.api.nvim_create_autocmd('FileType', {
        group = vim.api.nvim_create_augroup('TreesitterAttach', { clear = true }),
        callback = function(args)
          pcall(vim.treesitter.start, args.buf)
          vim.bo[args.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
        end,
      })
    end,
  },

  {
    'nvim-treesitter/nvim-treesitter-textobjects',
    lazy = false,
    dependencies = { 'nvim-treesitter/nvim-treesitter' },
    config = function()
      require('nvim-treesitter-textobjects').setup {
        move = {
          enable = true,
          set_jumps = true,
        },
      }

      -- Define Move keymaps (normal, visual, and operator-pending modes)
      local move = require 'nvim-treesitter-textobjects.move'
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

        [']a'] = { fn = move.goto_next_start, query = '@parameter.inner', desc = 'Next parameter start' },
        [']A'] = { fn = move.goto_next_end, query = '@parameter.inner', desc = 'Next parameter end' },
        ['[a'] = { fn = move.goto_previous_start, query = '@parameter.inner', desc = 'Prev parameter start' },
        ['[A'] = { fn = move.goto_previous_end, query = '@parameter.inner', desc = 'Prev parameter end' },
      }
      for lhs, val in pairs(move_maps) do
        vim.keymap.set({ 'n', 'x', 'o' }, lhs, function()
          val.fn(val.query, 'textobjects')
        end, { desc = val.desc })
      end
    end,
  },
}
