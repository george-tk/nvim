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
        if vim.fn.has 'win32' == 1 or vim.fn.executable 'make' == 0 then
          return
        end
        return 'make install_jsregexp'
      end)(),
      dependencies = {
        {
          'rafamadriz/friendly-snippets',
          config = function()
            -- Lazy-load VSCode snippets; optionally narrow filetypes to cut load further:
            require('luasnip.loaders.from_vscode').lazy_load {
              include = { 'lua', 'markdown' },
            }
          end,
        },
      },
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

      -- Completion behavior: lighter by default, docs on-demand, same UX
      completion = {
        accept = {
          auto_brackets = { enabled = true }, -- () + cursor inside on accept (functions/methods)
        },
        documentation = {
          auto_show = true, -- open docs when you want (<C-Space> or via keymaps)
          auto_show_delay_ms = 0,
          update_delay_ms = 50,
        },
        trigger = {
          -- keep keyword-triggered menu; disable trigger-character churn
          show_on_keyword = true,
          show_on_trigger_character = false,
        },
        list = {
          selection = {
            -- avoids auto-select & preview insertion churn on first item
            preselect = false,
            auto_insert = false,
          },
        },
        menu = {
          draw = {
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

      -- Sources: keep your defaults; load dictionary only for markdown via plugin ft above
      sources = {
        default = function()
          if vim.bo.filetype == 'markdown' then
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

          -- Optional: show buffer items even when LSP is present (can help in args)
          -- lsp = { fallbacks = {} },
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

        -- Prefer snippet placeholders over menu navigation for Tab
        ['<Tab>'] = {
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
          'select_next',
          'fallback',
        },
        ['<S-Tab>'] = {
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
          'select_prev',
          'fallback',
        },

        -- Scroll docs if open
        ['<C-b>'] = { 'scroll_documentation_up', 'fallback' },
        ['<C-f>'] = { 'scroll_documentation_down', 'fallback' },

        -- Signature help toggle (handy inside function calls)
        ['<C-k>'] = { 'show_signature', 'hide_signature', 'fallback' },
      },

      -- Signature help (parameter hints) while inside function calls
      signature = { enabled = true },

      -- Icon spacing/alignment
      appearance = { nerd_font_variant = 'mono' },
    }
  end,
}
