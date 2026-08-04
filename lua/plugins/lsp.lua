return {
  ---------------------------------------------------------------------------
  -- Lua typing help for Neovim config/plugins (loads only for Lua files)
  ---------------------------------------------------------------------------
  {
    'folke/lazydev.nvim',
    ft = 'lua',
    opts = {
      library = {
        { path = '${3rd}/luv/library', words = { 'vim%.uv' } },
      },
    },
  },

  ---------------------------------------------------------------------------
  -- Main LSP configuration (performance-tuned)
  ---------------------------------------------------------------------------
  {
    'neovim/nvim-lspconfig',
    event = { 'BufReadPre', 'BufNewFile' }, -- start when actually editing files
    dependencies = {
      { 'mason-org/mason.nvim', cmd = 'Mason', opts = {} },
      'mason-org/mason-lspconfig.nvim',
      'WhoIsSethDaniel/mason-tool-installer.nvim',

      -- LSP status UI (defer to first LSP attach to keep startup snappy)
      { 'j-hui/fidget.nvim', opts = {}, event = 'LspAttach' },

      -- Blink is our completion client; we’ll use its capabilities
      'saghen/blink.cmp',
    },

    config = function()
      -----------------------------------------------------------------------
      -- Diagnostics: reasonable defaults, sorted by severity, rounded float
      -----------------------------------------------------------------------
      vim.diagnostic.config {
        severity_sort = true,
        float = { border = 'rounded', source = 'if_many' },
        underline = { severity = vim.diagnostic.severity.ERROR },
        signs = vim.g.have_nerd_font and {
          text = {
            [vim.diagnostic.severity.ERROR] = ' ',
            [vim.diagnostic.severity.WARN] = ' ',
            [vim.diagnostic.severity.INFO] = ' ',
            [vim.diagnostic.severity.HINT] = ' ',
          },
        } or {},
        virtual_text = {
          source = 'if_many',
          spacing = 2,
          format = function(diag)
            return diag.message
          end,
        },
      }

      -----------------------------------------------------------------------
      -- Blink capabilities (full completion features)
      -----------------------------------------------------------------------
      local capabilities = require('blink.cmp').get_lsp_capabilities()

      -----------------------------------------------------------------------
      -- Large-file guard: return true if file < 1 MiB
      -----------------------------------------------------------------------
      local function small_file(buf)
        local name = vim.api.nvim_buf_get_name(buf)
        if name == '' then
          return true
        end
        local ok, stat = pcall(vim.loop.fs_stat, name)
        return not ok or not stat or stat.size < 1024 * 1024
      end

      -----------------------------------------------------------------------
      -- root_dir helpers (avoid starting servers in $HOME, etc.)
      -----------------------------------------------------------------------
      local util = require 'lspconfig.util'
      local function root_with(patterns, fallback)
        return function(fname)
          return util.root_pattern(unpack(patterns))(fname) or util.find_git_ancestor(fname) or fallback
        end
      end

      -----------------------------------------------------------------------
      -- LspAttach: Inlay hints, document highlight, buffer keymaps
      -----------------------------------------------------------------------
      vim.api.nvim_create_autocmd('LspAttach', {
        group = vim.api.nvim_create_augroup('UserLspAttachAutocmd', { clear = true }),
        callback = function(event)
          local client = vim.lsp.get_client_by_id(event.data.client_id)
          if not client then return end
          local bufnr = event.buf

          -- Inlay hints: always automatically enabled
          if client.server_capabilities.inlayHintProvider and small_file(bufnr) then
            vim.lsp.inlay_hint.enable(true, { bufnr = bufnr })
          end

          -- Document highlight (CursorHold only, not in Insert)
          if client.server_capabilities.documentHighlightProvider and small_file(bufnr) then
            local aug = vim.api.nvim_create_augroup('lsp-doc-hl-' .. bufnr, { clear = true })
            vim.api.nvim_create_autocmd('CursorHold', {
              buffer = bufnr,
              group = aug,
              callback = vim.lsp.buf.document_highlight,
            })
            vim.api.nvim_create_autocmd({ 'CursorMoved', 'BufLeave' }, {
              buffer = bufnr,
              group = aug,
              callback = vim.lsp.buf.clear_references,
            })
            vim.api.nvim_create_autocmd('LspDetach', {
              buffer = bufnr,
              group = aug,
              callback = function()
                vim.lsp.buf.clear_references()
                pcall(vim.api.nvim_del_augroup_by_id, aug)
              end,
            })
          end
        end,
      })

      -----------------------------------------------------------------------
      -- Servers
      -----------------------------------------------------------------------
      local servers = {
        marksman = {
          root_dir = root_with({ '.marksman.toml', '.git' }, vim.loop.cwd()),
        },

        lua_ls = {
          root_dir = root_with({ '.luarc.json', '.luarc.jsonc', '.git' }, vim.loop.cwd()),
          settings = {
            Lua = {
              completion = { callSnippet = 'Replace' },
              hint = {
                enable = true,
                paramName = 'All',
                paramType = true,
                setType = true,
              },
              workspace = { checkThirdParty = false },
              telemetry = { enable = false },
            },
          },
        },

        -- Uncomment to enable TypeScript/JavaScript (tsserver via ts_ls)
        -- ts_ls = {
        --   root_dir = root_with({ 'tsconfig.json', 'jsconfig.json', 'package.json', '.git' }, vim.loop.cwd()),
        --   single_file_support = false,
        --   settings = {
        --     completions = { completeFunctionCalls = true }, -- call-site param snippets
        --   },
        --   -- Avoid conflicts with formatters (prettier/conform/biome/etc.)
        --   on_attach = function(client, bufnr)
        --     client.server_capabilities.documentFormattingProvider = false
        --     on_attach(client, bufnr)
        --   end,
        -- },
      }

      -----------------------------------------------------------------------
      -- Ensure tools via Mason (automatically installed on startup)
      -----------------------------------------------------------------------
      local ensure = vim.tbl_keys(servers)
      vim.list_extend(ensure, {
        'stylua',        -- Lua Formatter
        'prettier',      -- Markdown, JSON, HTML, CSS Formatter
        'sql-formatter', -- SQL Formatter
      })

      require('mason-tool-installer').setup {
        ensure_installed = ensure,
        auto_update = false,
        run_on_start = true,
      }

      require('mason-lspconfig').setup {
        ensure_installed = {}, -- we install via mason-tool-installer
        automatic_installation = false,
        handlers = {
          function(server_name)
            local server = servers[server_name] or {}
            server.capabilities = vim.tbl_deep_extend('force', {}, capabilities, server.capabilities or {})
            -- Default flags to reduce churn
            server.flags = vim.tbl_deep_extend('force', {
              debounce_text_changes = 200,
            }, server.flags or {})

            -- Default on_attach unless server overrides it (ts_ls above)
            if not server.on_attach then
              server.on_attach = on_attach
            end

            require('lspconfig')[server_name].setup(server)
          end,
        },
      }
    end,
  },
}
