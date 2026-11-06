return {
  {
    'nvim-treesitter/nvim-treesitter',
    lazy = false,
    build = ':TSUpdate',
    config = function()
      local ts = require 'nvim-treesitter'
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

      -- Enable Treesitter highlighting and indenting natively in Neovim 0.12+ (with large-file & special-buffer guard)
      vim.api.nvim_create_autocmd('FileType', {
        group = vim.api.nvim_create_augroup('TreesitterAttach', { clear = true }),
        callback = function(args)
          local buf = args.buf
          if not vim.api.nvim_buf_is_valid(buf) then
            return
          end
          local ft = vim.bo[buf].filetype
          local bt = vim.bo[buf].buftype
          if ft == 'bigfile' or ft == 'sqmeow-result' or ft == 'sqmeow-drawer' or ft == 'dbout' or ft == 'dbui' or ft:match '^snacks' then
            return
          end
          if bt ~= '' and not vim.b[buf].sqmeow_editor and not vim.b[buf].is_preview_buffer then
            return
          end
          local name = vim.api.nvim_buf_get_name(buf)
          if name ~= '' then
            local ok, stat = pcall((vim.uv or vim.loop).fs_stat, name)
            if ok and stat and stat.size > 1024 * 1024 then
              vim.schedule(function()
                for _, win in ipairs(vim.fn.win_findbuf(buf)) do
                  if vim.api.nvim_win_is_valid(win) then
                    vim.wo[win].foldmethod = 'manual'
                  end
                end
              end)
              return
            end
          end
          pcall(vim.treesitter.start, buf)
          vim.bo[buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
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
