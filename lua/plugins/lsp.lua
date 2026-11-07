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
    event = { 'BufReadPre', 'BufNewFile', 'VeryLazy' }, -- start when editing files or after dashboard
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
      -- Disable recursive LSP file watcher on Linux/WSL to prevent inotify/9P stalls
      -----------------------------------------------------------------------
      local capabilities = require('blink.cmp').get_lsp_capabilities {
        workspace = {
          didChangeWatchedFiles = {
            dynamicRegistration = false,
          },
        },
      }

      -----------------------------------------------------------------------
      -- Large-file guard: return true if file < 1 MiB
      -----------------------------------------------------------------------
      local function small_file(buf)
        local name = vim.api.nvim_buf_get_name(buf)
        if name == '' then
          return true
        end
        local ok, stat = pcall(vim.uv.fs_stat, name)
        return not ok or not stat or stat.size < 1024 * 1024
      end

      -----------------------------------------------------------------------
      -- root_dir helpers (avoid starting servers in $HOME, etc.)
      -- Supports both Neovim 0.11 `vim.lsp.config` `root_dir(bufnr, on_dir)`
      -- and legacy `lspconfig` `root_dir(fname)` signatures.
      -----------------------------------------------------------------------
      local function root_with(patterns, fallback)
        return function(bufnr_or_fname, on_dir)
          local fname
          if type(bufnr_or_fname) == 'number' then
            fname = vim.api.nvim_buf_get_name(bufnr_or_fname)
          elseif type(bufnr_or_fname) == 'string' then
            fname = bufnr_or_fname
          end

          local root = nil
          if fname and fname ~= '' and not fname:find '^%[' and not fname:find '://' then
            local ok_r, r = pcall(vim.fs.root, fname, patterns)
            if ok_r and r then
              root = r
            else
              local ok_g, g = pcall(vim.fs.root, fname, '.git')
              if ok_g and g then
                root = g
              end
            end
          end
          root = root or fallback or vim.uv.cwd()

          if type(on_dir) == 'function' then
            if root then
              on_dir(root)
            end
          end
          return root
        end
      end

      -----------------------------------------------------------------------
      -- Global diagnostic & code fallbacks so <leader>c* never falls through
      -- to raw Normal-mode `c` commands before an LSP client attaches
      -----------------------------------------------------------------------
      local function notify_no_lsp()
        vim.notify('No active LSP client attached to this buffer', vim.log.levels.INFO, { title = 'LSP' })
      end
      vim.keymap.set('n', '<leader>cd', vim.diagnostic.open_float, { desc = 'Line Diagnostics' })
      vim.keymap.set('n', '<leader>cD', function()
        Snacks.picker.diagnostics()
      end, { desc = 'Workspace Diagnostics' })
      vim.keymap.set('n', 'gl', vim.diagnostic.open_float, { desc = 'Line Diagnostics' })
      vim.keymap.set('n', '[d', function()
        vim.diagnostic.jump { count = -1, float = true }
      end, { desc = 'Previous Diagnostic' })
      vim.keymap.set('n', ']d', function()
        vim.diagnostic.jump { count = 1, float = true }
      end, { desc = 'Next Diagnostic' })
      vim.keymap.set('n', '<leader>cr', notify_no_lsp, { desc = 'Rename Symbol' })
      vim.keymap.set({ 'n', 'v' }, '<leader>ca', notify_no_lsp, { desc = 'Code Action' })
      vim.keymap.set('n', '<leader>cR', notify_no_lsp, { desc = 'References' })
      vim.keymap.set('n', '<leader>cs', notify_no_lsp, { desc = 'Document Symbols' })
      vim.keymap.set('n', '<leader>ci', notify_no_lsp, { desc = 'Implementations' })

      -----------------------------------------------------------------------
      -- LspAttach: Inlay hints, document highlight, buffer keymaps
      -----------------------------------------------------------------------
      vim.api.nvim_create_autocmd('LspAttach', {
        group = vim.api.nvim_create_augroup('UserLspAttachAutocmd', { clear = true }),
        callback = function(event)
          local client = vim.lsp.get_client_by_id(event.data.client_id)
          if not client then
            return
          end
          local bufnr = event.buf

          -- Inlay hints: always automatically enabled
          if client.server_capabilities.inlayHintProvider and small_file(bufnr) then
            vim.lsp.inlay_hint.enable(true, { bufnr = bufnr })
          end

          -- Buffer-local LSP Keymaps (VS Code Parity)
          local function map(keys, func, desc, mode)
            mode = mode or 'n'
            vim.keymap.set(mode, keys, func, { buffer = bufnr, desc = 'LSP: ' .. desc })
          end

          map('gd', function()
            Snacks.picker.lsp_definitions()
          end, 'Goto Definition')
          map('gD', vim.lsp.buf.declaration, 'Goto Declaration')
          map('gr', function()
            Snacks.picker.lsp_references()
          end, 'Goto References')
          map('gi', function()
            Snacks.picker.lsp_implementations()
          end, 'Goto Implementation')
          map('gy', function()
            Snacks.picker.lsp_type_definitions()
          end, 'Type Definition')
          map('K', vim.lsp.buf.hover, 'Hover Documentation')
          map('<C-k>', vim.lsp.buf.signature_help, 'Signature Help', 'i')

          map('<leader>cr', vim.lsp.buf.rename, 'Rename Symbol')
          map('<F2>', vim.lsp.buf.rename, 'Rename Symbol')
          map('<leader>ca', vim.lsp.buf.code_action, 'Code Action', { 'n', 'v' })
          map('<M-.>', vim.lsp.buf.code_action, 'Code Action', { 'n', 'v' })
          map('<leader>cd', vim.diagnostic.open_float, 'Line Diagnostics')
          map('<leader>cD', function()
            Snacks.picker.diagnostics()
          end, 'Workspace Diagnostics')
          map('<leader>cR', function()
            Snacks.picker.lsp_references()
          end, 'References')
          map('<leader>cs', function()
            Snacks.picker.lsp_symbols()
          end, 'Document Symbols')
          map('<leader>ci', function()
            Snacks.picker.lsp_implementations()
          end, 'Implementations')
          map('gl', vim.diagnostic.open_float, 'Line Diagnostics')
          map('[d', function()
            vim.diagnostic.jump { count = -1, float = true }
          end, 'Previous Diagnostic')
          map(']d', function()
            vim.diagnostic.jump { count = 1, float = true }
          end, 'Next Diagnostic')
          map('<leader>cf', function()
            local ok_c, conform = pcall(require, 'conform')
            if ok_c then
              conform.format { async = true, lsp_format = 'fallback' }
            else
              vim.lsp.buf.format { async = true }
            end
          end, 'Format Buffer')

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
          root_dir = root_with({ '.marksman.toml', '.git' }, vim.uv.cwd()),
        },

        lua_ls = {
          root_dir = root_with({ '.luarc.json', '.luarc.jsonc', '.git' }, vim.uv.cwd()),
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

        pyright = {
          root_dir = root_with({ 'pyproject.toml', 'setup.py', 'setup.cfg', 'requirements.txt', 'Pipfile', 'pyrightconfig.json', '.git' }, vim.uv.cwd()),
          settings = {
            python = {
              analysis = {
                autoSearchPaths = true,
                useLibraryCodeForTypes = true,
                diagnosticMode = 'openFilesOnly',
              },
            },
          },
        },

        ruff = {
          root_dir = root_with({ 'pyproject.toml', 'ruff.toml', '.ruff.toml', 'setup.py', 'requirements.txt', '.git' }, vim.uv.cwd()),
        },

        -- Uncomment to enable TypeScript/JavaScript (tsserver via ts_ls)
        -- ts_ls = {
        --   root_dir = root_with({ 'tsconfig.json', 'jsconfig.json', 'package.json', '.git' }, vim.uv.cwd()),
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
      require('mason').setup()

      local ensure = vim.tbl_keys(servers)
      vim.list_extend(ensure, {
        'stylua', -- Lua Formatter
        'prettier', -- Markdown, JSON, YAML, HTML, CSS Formatter
        'sql-formatter', -- SQL Formatter
      })

      local mti = require 'mason-tool-installer'
      mti.setup {
        ensure_installed = ensure,
        auto_update = false,
        run_on_start = true,
      }
      -- Trigger run_on_start explicitly in case LSP loaded on VeryLazy (after VimEnter)
      vim.schedule(function()
        mti.run_on_start()
      end)

      for server_name, server in pairs(servers) do
        server.capabilities = vim.tbl_deep_extend('force', {}, capabilities, server.capabilities or {})
        server.flags = vim.tbl_deep_extend('force', {
          debounce_text_changes = 200,
        }, server.flags or {})
        if vim.lsp and vim.lsp.config then
          vim.lsp.config(server_name, server)
        else
          require('lspconfig')[server_name].setup(server)
        end
      end

      require('mason-lspconfig').setup {
        ensure_installed = {}, -- installed via mason-tool-installer
        automatic_enable = true,
      }
    end,
  },
}
