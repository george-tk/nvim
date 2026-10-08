local db = require('utils.database')

return {

  -- UI component library required by sqmeow
  {
    'MunifTanjim/nui.nvim',
    lazy = true,
  },

  -- Modern Rust-powered Database Client with Schema, Views, Routines, and In-Grid Editing
  {
    '2giosangmitom/sqmeow.nvim',
    dependencies = { 'MunifTanjim/nui.nvim' },
    cmd = 'Sqmeow',
    build = function()
      require('sqmeow').install()
    end,
    init = function()
      -- Database UI and result buffers inherit the global spell setting otherwise.
      vim.api.nvim_create_autocmd({ 'FileType', 'BufWinEnter' }, {
        callback = function(args)
          local buf = args.buf or vim.api.nvim_get_current_buf()
          if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
          local ft = vim.bo[buf].filetype
          local name = vim.api.nvim_buf_get_name(buf)
          if ft == 'dbui' or ft == 'dbout' or ft == 'sqmeow-drawer' or ft == 'sqmeow-result'
            or name:find('sqmeow://') ~= nil
          then
            vim.opt_local.spell = false
            for _, win in ipairs(vim.fn.win_findbuf(buf)) do
              if vim.api.nvim_win_is_valid(win) then
                vim.wo[win].spell = false
              end
            end
            local cur_win = vim.api.nvim_get_current_win()
            if vim.api.nvim_win_is_valid(cur_win) and vim.api.nvim_win_get_buf(cur_win) == buf then
              vim.wo[cur_win].spell = false
            end
          end
        end,
      })

      -- Automatically bind active database and enable AI completion for any opened .sql file
      vim.api.nvim_create_autocmd('FileType', {
        pattern = { 'sql', 'mysql', 'plsql' },
        callback = function(args)
          if vim.g.SessionLoad == 1 then return end
          local buf = args.buf
          if not buf or not vim.api.nvim_buf_is_valid(buf) then return end

          local db_url, db_name = db.get_active_db(buf)
          vim.opt_local.spell = false
          if db_url and db.is_accessible(db_url) then
            pcall(function()
              vim.b[buf].db_name = db_name
              vim.b[buf].sqmeow_connection = db_name
            end)
          end
          pcall(function()
            vim.b[buf].neocodeium_enabled = true
            vim.b[buf].neocodeium_allowed_encoding = true
          end)
        end,
      })

      -- Explorer-like navigation in sqmeow drawer: Tab/S-Tab, l/CR, h, q, <C-j>, p, P, K
      vim.api.nvim_create_autocmd({ 'FileType', 'BufWinEnter' }, {
        pattern = 'sqmeow-drawer',
        callback = function(args)
          vim.b[args.buf].panel_zone = 'right'
          vim.b[args.buf].panel_type = 'dbui'
          db.setup_drawer_helpers()
          vim.keymap.set('n', '<Tab>', 'j', { buffer = args.buf, silent = true, desc = 'Next Item' })
          vim.keymap.set('n', '<S-Tab>', 'k', { buffer = args.buf, silent = true, desc = 'Previous Item' })
          vim.keymap.set('n', 'l', '<CR>', { buffer = args.buf, remap = true, silent = true, desc = 'Open / Expand Node' })
          vim.keymap.set('n', 'p', function() require('sqmeow.ui.drawer').actions.preview() end, { buffer = args.buf, silent = true, desc = 'Preview Relation' })
          vim.keymap.set('n', 'K', function() require('sqmeow.ui.drawer').actions.structure() end, { buffer = args.buf, silent = true, desc = 'Table Structure / Schema' })
          vim.keymap.set('n', 'u', function()
            require('sqmeow.ui.drawer').actions.use()
          end, { buffer = args.buf, silent = true, desc = 'Run queries against this connection' })
          vim.keymap.set('n', 'h', function()
            local cur_line = vim.api.nvim_get_current_line()
            if cur_line:match('^%s+') then
              vim.cmd('normal! ^')
              local col = vim.fn.col('.')
              while vim.fn.line('.') > 1 and vim.fn.col('.') >= col do
                vim.cmd('normal! k')
              end
            else
              vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<CR>', true, false, true), 'n', false)
            end
          end, { buffer = args.buf, silent = true, desc = 'Collapse / Parent Node' })
          vim.keymap.set('n', '<C-j>', function() _G.BottomPanel.toggle_active() end, { buffer = args.buf, silent = true, desc = 'Bottom Output' })
          vim.keymap.set('n', 'q', function()
            if _G.RightPanel then
              _G.RightPanel.close_all()
            else
              pcall(function() require('sqmeow.api.view').close_drawer() end)
            end
          end, { buffer = args.buf, silent = true, desc = 'Close Database Drawer' })
        end,
      })

      -- Result window coordination: keymaps, navigation, sticky headers & winbar
      vim.api.nvim_create_autocmd({ 'FileType', 'BufWinEnter' }, {
        pattern = { 'sqmeow-result', 'sqmeow://result*' },
        callback = function(args)
          local buf_ft = vim.bo[args.buf].filetype
          local buf_name = vim.api.nvim_buf_get_name(args.buf)
          -- Guard: Never run on database drawer! sqmeow://drawer is the right sidebar, not query results!
          if buf_ft == 'sqmeow-drawer' or buf_name:find('drawer') then
            return
          end
          if buf_ft ~= 'sqmeow-result' and buf_ft ~= 'dbout' and not buf_name:find('sqmeow://result') then
            return
          end

          vim.b[args.buf].panel_zone = 'bottom'
          vim.b[args.buf].panel_type = 'dbout'
          vim.bo[args.buf].buflisted = false
          for _, w in ipairs(vim.fn.win_findbuf(args.buf)) do
            if vim.api.nvim_win_is_valid(w) then
              vim.wo[w].winfixheight = true
              vim.wo[w].winfixbuf = true
            end
          end
          if _G.BottomPanel then
            _G.BottomPanel.last_dbout_buf = args.buf
            _G.BottomPanel.active_mode = 'dbout'
          end

          -- First/Last column navigation (next/prev column are built-in upstream on <Tab>/<S-Tab> and ]c/[c)
          vim.keymap.set('n', 'g0', function() db.first_result_column() end, { buffer = args.buf, silent = true, desc = 'First Column' })
          vim.keymap.set('n', 'g$', function() db.last_result_column() end, { buffer = args.buf, silent = true, desc = 'Last Column' })

          vim.keymap.set('n', 'q', function()
            pcall(function() require('sqmeow.api.view').close() end)
            if _G.BottomPanel and _G.BottomPanel.ensure_precedence then
              _G.BottomPanel.ensure_precedence()
            end
            local ed = _G.RightPanel and _G.RightPanel.get_editor_win and _G.RightPanel.get_editor_win()
            if ed and vim.api.nvim_win_is_valid(ed) then
              vim.api.nvim_set_current_win(ed)
            end
          end, { buffer = args.buf, silent = true, desc = 'Close Query Results' })
        end,
      })
    end,
    config = function(_, opts)
      require('sqmeow').setup(opts)
      db.setup_drawer_helpers()
    end,
    opts = {
      ui = {
        drawer = {
          position = 'right',
          width = 35,
          preview_in_editor = true,
        },
        result = {
          height = 16,
          page_size = 1000,
          max_column_width = 48,
          column_icons = true,
          null_text = 'NULL',
          sticky_header = true,
          winbar_column_info = true,
        },
      },
      keymaps = {
        drawer = {
          { action = 'toggle', lhs = { '<CR>', 'o', 'l' }, desc = 'Expand or collapse the node' },
          { action = 'close', lhs = 'q', desc = 'Close the drawer' },
          { action = 'preview', lhs = 'p', desc = 'Preview this relation' },
          { action = 'structure', lhs = 'K', desc = 'Show structure of table or key' },
        },
      },
    },
    keys = {
      {
        '<leader>bb',
        function()
          if _G.RightPanel then
            _G.RightPanel.open_dbui()
          else
            db.open_drawer()
          end
        end,
        desc = 'Database Explorer',
      },
      {
        '<leader>bs',
        function()
          db.select_connection()
        end,
        desc = 'Switch / Bind Database',
      },
      {
        '<leader>bw',
        function()
          db.save_query()
        end,
        desc = 'Save Query',
      },
      {
        '<leader>bl',
        function()
          db.select_saved_query()
        end,
        desc = 'Select Saved Query',
      },
      {
        '<leader>br',
        function()
          db.run_query()
        end,
        desc = 'Run Query (Statement / Visual)',
        mode = { 'n', 'v' },
      },
      {
        '<leader>bq',
        function()
          db.open_query_scratchpad()
        end,
        desc = 'Query Scratchpad',
      },
      {
        '<leader>bo',
        function()
          if _G.BottomPanel then
            _G.BottomPanel.open_dbout()
          else
            pcall(function() require('sqmeow.api.view').open() end)
          end
        end,
        desc = 'Query Output',
      },
      {
        '<leader>ba',
        function()
          db.add_connection()
        end,
        desc = 'Add Database',
      },
      {
        '<leader>bd',
        function()
          db.delete_connection()
        end,
        desc = 'Delete Database',
      },
      {
        '<leader>bf',
        function()
          pcall(function() require('sqmeow.api.view').toggle_float() end)
        end,
        desc = 'Toggle Float Result',
      },
      {
        '<leader>bv',
        function()
          pcall(function() require('sqmeow.api.view').review() end)
        end,
        desc = 'Review & Apply In-Grid Edits',
      },
      {
        '<leader>bx',
        function()
          vim.ui.input({ prompt = 'Export Format (csv, json, sql): ', default = 'csv' }, function(fmt)
            if not fmt or fmt == '' then return end
            pcall(function() require('sqmeow.api.export').export({ format = vim.trim(fmt), clipboard = true }) end)
          end)
        end,
        desc = 'Export Results',
      },
    },
  },
}
