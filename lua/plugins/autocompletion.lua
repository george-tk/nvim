-- Autocompletion (blink.cmp) — tuned for fast startup, same UX (Tab/snippets, cmdline guards)
return {
  'saghen/blink.cmp',
  version = '1.*', -- prebuilt fuzzy binaries
  event = { 'InsertEnter', 'CmdlineEnter' }, -- load when you actually use completion

  dependencies = {
    -- Snippets (LuaSnip + friendly-snippets)
    {
      'L3MON4D3/LuaSnip',
      version = 'v2.*',
      build = (function()
        if vim.fn.has 'win32' == 0 and vim.fn.executable 'make' == 1 then
          return 'make install_jsregexp'
        end
      end)(),
      dependencies = {
        'rafamadriz/friendly-snippets',
      },
      config = function()
        local ls = require 'luasnip'
        ls.config.setup {
          history = true,
          updateevents = 'TextChanged,TextChangedI',
        }
        -- Lazy-load VSCode snippets from friendly-snippets
        require('luasnip.loaders.from_vscode').lazy_load {
          include = { 'lua', 'markdown' },
        }
      end,
    },

    -- Dictionary source: load only in Markdown to avoid startup cost elsewhere
    { 'Kaiser-Yang/blink-cmp-dictionary', ft = { 'markdown' }, dependencies = { 'nvim-lua/plenary.nvim' } },

    -- lspkind (tiny)
    'onsails/lspkind.nvim',

    -- LazyDev only for Lua (Neovim config/dev typing help)
    { 'folke/lazydev.nvim', ft = { 'lua' } },
  },

  opts = function()
    local dict_path = vim.fn.expand '~/.config/nvim/dict/en.txt'

    ---@type blink.cmp.Config
    return {
      -- Snippet engine
      snippets = { preset = 'luasnip' },

      -- Completion behavior: lighter by default, docs on-demand, clean 2-column UI
      completion = {
        accept = {
          auto_brackets = { enabled = true }, -- () + cursor inside on accept (functions/methods)
        },
        documentation = {
          auto_show = true,
          auto_show_delay_ms = 0,
          update_delay_ms = 50,
          window = {
            border = 'rounded',
          },
        },
        trigger = {
          show_on_keyword = true,
          show_on_trigger_character = true,
          show_on_blocked_trigger_characters = { ' ', '\n', '\t' },
          show_on_x_blocked_trigger_characters = {},
        },
        list = {
          selection = {
            preselect = false,
            auto_insert = false,
          },
        },
        menu = {
          border = 'rounded',
          draw = {
            columns = {
              { 'kind_icon' },
              { 'label', gap = 1 },
            },
            components = {
              kind_icon = {
                ellipsis = false,
                text = function(ctx)
                  local lspkind = require 'lspkind'
                  local icon = lspkind.symbolic(ctx.kind, { mode = 'symbol' })
                  return (icon or '') .. (ctx.icon_gap or ' ')
                end,
              },
              kind = {
                highlight = function(ctx)
                  return 'BlinkCmpKind' .. (ctx.kind or '')
                end,
              },
            },
          },
        },
      },

      -- Fuzzy sorting: prioritize local variables, parameters, and snippets over bare keywords
      fuzzy = {
        sorts = {
          -- 1. Prioritize Variables (6), Parameters (25), Fields (5), Properties (10)
          function(a, b)
            local a_var = a.kind == 6 or a.kind == 25 or a.kind == 5 or a.kind == 10
            local b_var = b.kind == 6 or b.kind == 25 or b.kind == 5 or b.kind == 10
            if a_var ~= b_var then
              return a_var
            end
          end,
          -- 2. Prioritize Snippets (15) over bare language Keywords (14)
          function(a, b)
            local a_snip = a.kind == 15
            local b_snip = b.kind == 15
            local a_kw = a.kind == 14
            local b_kw = b.kind == 14
            if a_snip and b_kw then
              return true
            end
            if b_snip and a_kw then
              return false
            end
          end,
          'exact',
          'score',
          'sort_text',
        },
      },

      -- Sources: keep your defaults; load dictionary only for markdown via plugin ft above
      sources = {
        default = function()
          if vim.bo.filetype == 'opencode_ask' then
            return { 'lsp', 'buffer' }
          elseif vim.bo.filetype == 'sql' or vim.bo.filetype == 'mysql' or vim.bo.filetype == 'plsql' then
            return { 'dadbod', 'lsp', 'snippets', 'buffer' }
          elseif vim.bo.filetype == 'markdown' or vim.bo.filetype == 'text' or vim.bo.filetype == 'gitcommit' then
            local ok, node = pcall(vim.treesitter.get_node)
            if ok and node then
              while node do
                if node:type() == 'pipe_table' or node:type() == 'table' then
                  return {}
                end
                node = node:parent()
              end
            end
            return { 'lsp', 'path', 'snippets', 'buffer', 'dictionary' }
          elseif vim.bo.filetype == 'lua' then
            return { 'lsp', 'path', 'snippets', 'buffer', 'lazydev' }
          end
          return { 'lsp', 'path', 'snippets', 'buffer' }
        end,
        providers = {
          -- LSP: boost variables and in-scope parameters; demote deprecated symbols
          lsp = {
            name = 'LSP',
            module = 'blink.cmp.sources.lsp',
            score_offset = 20,
            transform_items = function(ctx, items)
              for _, item in ipairs(items) do
                if item.kind == 6 or item.kind == 25 or item.kind == 5 or item.kind == 10 then
                  item.score_offset = (item.score_offset or 0) + 100
                end
                if item.deprecated or (item.tags and vim.tbl_contains(item.tags, 1)) then
                  item.score_offset = (item.score_offset or 0) - 100
                end
              end
              return items
            end,
          },

          -- Buffer: quiet fallback (min 3 chars, slight negative offset to prevent noise)
          buffer = {
            name = 'Buffer',
            module = 'blink.cmp.sources.buffer',
            min_keyword_length = 3,
            score_offset = -3,
          },

          -- Path: clean filesystem completion
          path = {
            name = 'Path',
            module = 'blink.cmp.sources.path',
            score_offset = 0,
            opts = {
              trailing_slash = true,
              show_hidden_files_by_default = false,
            },
          },

          -- Database completion via vim-dadbod-completion
          dadbod = {
            name = 'Dadbod',
            module = 'vim_dadbod_completion.blink',
            score_offset = 100,
          },

          -- keep LazyDev provider
          lazydev = { module = 'lazydev.integrations.blink', score_offset = 100 },

          -- dictionary wired to your wordlist
          dictionary = {
            name = 'Dict',
            module = 'blink-cmp-dictionary',
            min_keyword_length = 3,
            opts = {
              dictionary_files = { dict_path },
            },
          },

          -- Snippets provider: clean human-readable names
          snippets = {
            name = 'Snippets',
            module = 'blink.cmp.sources.snippets',
            score_offset = 1,
            opts = {
              use_label_description = false,
            },
            transform_items = function(ctx, items)
              local ok, luasnip = pcall(require, 'luasnip')
              if not ok or not luasnip then
                return items
              end
              for _, item in ipairs(items) do
                if item.data and item.data.snip_id then
                  local snip = luasnip.get_id_snippet(item.data.snip_id)
                  if snip and snip.name and snip.name ~= '' then
                    item.label = snip.name:gsub('-', ' ')
                    item.labelDetails = nil
                  end
                end
              end
              return items
            end,
          },
        },
      },

      -- Cmdline completion with guarded <CR>: only accept if you explicitly selected an item
      cmdline = {
        enabled = true,
        sources = { 'path', 'cmdline', 'buffer' },
        completion = {
          menu = { auto_show = true },
          list = { selection = { preselect = false } },
        },
        keymap = {
          preset = 'none',
          ['<CR>'] = {
            function(cmp)
              if cmp.is_menu_visible and cmp.get_selected_item then
                if cmp.is_menu_visible() and cmp.get_selected_item() then
                  return cmp.accept_and_enter()
                end
              end
            end,
            'fallback',
          },
          ['<Tab>'] = { 'show', 'select_next', 'fallback' },
          ['<S-Tab>'] = { 'show', 'select_prev', 'fallback' },
        },
      },

      -- Insert-mode keymaps: snippet jump first -> select next -> fallback
      keymap = {
        preset = 'none',

        -- Show menu and/or docs on demand
        ['<C-Space>'] = { 'show', 'show_documentation', 'hide_documentation' },

        -- Hide
        ['<C-e>'] = { 'hide', 'fallback' },

        -- Guarded <CR>: accept only when a selection exists; else newline
        ['<CR>'] = {
          function(cmp)
            if cmp.is_menu_visible and cmp.get_selected_item then
              if cmp.is_menu_visible() and cmp.get_selected_item() then
                return cmp.accept()
              end
            end
          end,
          'fallback',
        },

        -- Tab: Menu navigation when popup is visible -> Snippet jumping when popup is closed -> Markdown Table -> Fallback
        ['<Tab>'] = {
          function(cmp)
            if cmp.is_visible() then
              return cmp.select_next()
            end
          end,
          'snippet_forward',
          function()
            if vim.bo.filetype == 'markdown' then
              local ok, node = pcall(vim.treesitter.get_node)
              if ok and node then
                while node do
                  if node:type() == 'pipe_table' or node:type() == 'table' then
                    vim.schedule(function()
                      vim.cmd('MkdnTableNextCell')
                    end)
                    return true
                  end
                  node = node:parent()
                end
              end
            end
          end,
          'fallback',
        },
        ['<S-Tab>'] = {
          function(cmp)
            if cmp.is_visible() then
              return cmp.select_prev()
            end
          end,
          'snippet_backward',
          function()
            if vim.bo.filetype == 'markdown' then
              local ok, node = pcall(vim.treesitter.get_node)
              if ok and node then
                while node do
                  if node:type() == 'pipe_table' or node:type() == 'table' then
                    vim.schedule(function()
                      vim.cmd('MkdnTablePrevCell')
                    end)
                    return true
                  end
                  node = node:parent()
                end
              end
            end
          end,
          'fallback',
        },

        -- Scroll docs if open
        ['<C-b>'] = { 'scroll_documentation_up', 'fallback' },
        ['<C-f>'] = { 'scroll_documentation_down', 'fallback' },

        -- Signature help toggle (handy inside function calls)
        ['<C-k>'] = { 'show_signature', 'hide_signature', 'fallback' },
      },

      -- Signature help (parameter hints) while inside function calls
      signature = {
        enabled = true,
        trigger = {
          enabled = true,
          show_on_keyword = true,
          show_on_trigger_character = true,
          show_on_insert = true,
          show_on_insert_on_trigger_character = true,
          show_on_accept = true,
          show_on_accept_on_trigger_character = true,
        },
        window = {
          border = 'rounded',
          show_documentation = true,
        },
      },

      -- Icon spacing/alignment
      appearance = { nerd_font_variant = 'mono' },
    }
  end,
}
