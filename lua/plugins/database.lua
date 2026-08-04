local M = {}

local sample_db = vim.fs.normalize(vim.fn.stdpath('config') .. '/assets/local_test.db')

-- Active connection state across all buffers
M.current_db = 'sqlite:' .. sample_db
M.current_db_name = 'Local Test DB'

-- Resolve the active database for the current buffer
function M.get_active_db(buf)
  buf = buf or vim.api.nvim_get_current_buf()

  -- 1. Check buffer-local connection
  if vim.b[buf].db and vim.b[buf].db ~= '' then
    local name = vim.b[buf].db_name or M.current_db_name or 'Database'
    return vim.b[buf].db, name
  end

  -- 2. Use globally active connection
  if M.current_db then
    vim.b[buf].db = M.current_db
    vim.b[buf].db_name = M.current_db_name
    return M.current_db, M.current_db_name
  end

  return nil, nil
end

-- Interactive Database Connection Switcher via Snacks Picker
function M.select_connection(callback)
  local items = {}
  if vim.g.dbs then
    for _, entry in ipairs(vim.g.dbs) do
      local is_current = (entry.url == M.current_db)
      table.insert(items, {
        text = (is_current and '● ' or '○ ') .. entry.name .. ' (' .. entry.url .. ')',
        name = entry.name,
        url = entry.url,
      })
    end
  end

  table.insert(items, {
    text = '+ Add New Database Connection (MSSQL, Postgres, SQLite, MySQL)...',
    action = 'add',
  })

  Snacks.picker.select(items, {
    prompt = 'Switch Database Connection',
    format_item = function(item)
      return item.text
    end,
  }, function(choice)
    if not choice then return end
    if choice.action == 'add' then
      M.add_connection(callback)
      return
    end

    -- Update global active connection & current buffer connection
    M.current_db = choice.url
    M.current_db_name = choice.name

    local cur_buf = vim.api.nvim_get_current_buf()
    vim.b[cur_buf].db = choice.url
    vim.b[cur_buf].db_name = choice.name

    vim.notify('Active database: ' .. choice.name, vim.log.levels.INFO, { title = 'Database' })

    if callback then
      callback(choice.url, choice.name)
    end
  end)
end

-- Interactive Prompt to Add a New Database Connection
function M.add_connection(callback)
  vim.ui.input({
    prompt = 'Connection URL (e.g. sqlserver://user:pass@host:1433/db or postgresql://user:pass@host:5432/db): ',
  }, function(url)
    if not url or url == '' then return end
    vim.ui.input({
      prompt = 'Connection Name (e.g. Production MSSQL, Staging, Dev DB): ',
      default = url:match('([^/:]+)$') or 'Remote DB',
    }, function(name)
      if not name or name == '' then return end

      vim.g.dbs = vim.g.dbs or {}
      table.insert(vim.g.dbs, { name = name, url = url })

      M.current_db = url
      M.current_db_name = name

      local cur_buf = vim.api.nvim_get_current_buf()
      vim.b[cur_buf].db = url
      vim.b[cur_buf].db_name = name

      vim.notify('Added & connected: ' .. name, vim.log.levels.INFO, { title = 'Database' })

      if callback then
        callback(url, name)
      end
    end)
  end)
end

-- Open a 100% clean, blank SQL scratchpad buffer
function M.open_query_scratchpad()
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_set_current_buf(buf)
  vim.bo[buf].filetype = 'sql'
  vim.bo[buf].buftype = ''

  local db_url, db_name = M.get_active_db(buf)
  if not db_url then
    -- Prompt user with the picker immediately if no DB is connected yet
    M.select_connection()
  else
    vim.b[buf].db = db_url
    vim.b[buf].db_name = db_name
    vim.notify('SQL Scratchpad connected to ' .. db_name, vim.log.levels.INFO, { title = 'Database' })
  end
end

-- Execute query on ANY .sql file in repo, scratchpad, or visual selection
function M.run_query()
  local buf = vim.api.nvim_get_current_buf()
  local db_url, db_name = M.get_active_db(buf)

  -- If no connection is active, prompt with the picker and execute immediately once selected
  if not db_url then
    M.select_connection(function()
      M.run_query()
    end)
    return
  end

  local mode = vim.api.nvim_get_mode().mode

  -- 1. If inside a DBUI managed buffer, invoke native DBUI execute
  if vim.fn.exists('*db_ui#query#new') == 1 and vim.b[buf].dbui_db_key_name then
    local key = vim.api.nvim_replace_termcodes('<Plug>(DBUI_ExecuteQuery)', true, false, true)
    vim.api.nvim_feedkeys(key, 'm', false)
    return
  end

  -- 2. Save file if on disk
  if vim.bo[buf].modified and vim.bo[buf].buftype == '' and vim.fn.expand('%') ~= '' then
    vim.cmd('silent! write')
  end

  -- 3. Execute query via vim-dadbod
  if mode:match('[vV\x16]') then
    vim.cmd("'<,'>DB " .. db_url)
  else
    vim.cmd('%DB ' .. db_url)
  end

  vim.notify('Executed on ' .. db_name, vim.log.levels.INFO, { title = 'Database' })
end

_G.DatabaseUtils = M

return {
  -- Core Database Engine (Dadbod)
  {
    'tpope/vim-dadbod',
    cmd = { 'DB', 'DBUI', 'DBUIToggle', 'DBUIAddConnection', 'DBUIFindBuffer' },
    ft = { 'sql', 'mysql', 'plsql' },
  },

  -- Database Completion for Blink.cmp
  {
    'kristijanhusak/vim-dadbod-completion',
    dependencies = { 'tpope/vim-dadbod' },
    ft = { 'sql', 'mysql', 'plsql' },
  },

  -- Database UI Drawer & Results Explorer (Strictly Right Side)
  {
    'kristijanhusak/vim-dadbod-ui',
    dependencies = {
      'tpope/vim-dadbod',
      'kristijanhusak/vim-dadbod-completion',
    },
    cmd = {
      'DBUI',
      'DBUIToggle',
      'DBUIClose',
      'DBUIAddConnection',
      'DBUIFindBuffer',
    },
    init = function()
      local data_path = vim.fn.stdpath('data') .. '/db_ui'
      vim.g.db_ui_save_location = data_path
      vim.g.db_ui_use_nerd_fonts = 1
      vim.g.db_ui_show_database_icon = 1
      vim.g.db_ui_auto_execute_table_helpers = 1
      vim.g.db_ui_winwidth = 25
      vim.g.db_ui_win_position = 'right' -- Strictly Right Side
      vim.g.db_ui_use_nvim_notify = 1
      vim.g.db_ui_default_query = 'SELECT * FROM {table} LIMIT 50;'
      vim.g.db_ui_disable_mappings_sql = 1 -- Disable default uppercase <Leader>W, <Leader>E, <Leader>S mappings

      -- Configured connection list (Local SQLite + MSSQL template)
      vim.g.dbs = {
        {
          name = 'Local Test DB',
          url = 'sqlite:' .. sample_db,
        },
        -- Template for Microsoft SQL Server (MSSQL):
        -- {
        --   name = 'Production MSSQL',
        --   url = 'sqlserver://username:password@localhost:1433/DatabaseName?encrypt=true&trustServerCertificate=true',
        -- },
      }

      -- Table helpers for quick queries in the drawer
      vim.g.db_ui_table_helpers = {
        sqlite = {
          ['Count'] = 'SELECT count(*) FROM {table};',
          ['First 10'] = 'SELECT * FROM {table} LIMIT 10;',
          ['Describe'] = 'PRAGMA table_info({table});',
        },
        sqlserver = {
          ['Count'] = 'SELECT count(*) FROM {optional_schema}{table};',
          ['Top 10'] = 'SELECT TOP 10 * FROM {optional_schema}{table};',
          ['Describe'] = "SELECT COLUMN_NAME, DATA_TYPE, CHARACTER_MAXIMUM_LENGTH FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = '{table}';",
        },
        postgresql = {
          ['Count'] = 'SELECT count(*) FROM {optional_schema}{table};',
          ['First 10'] = 'SELECT * FROM {optional_schema}{table} LIMIT 10;',
        },
      }

      -- Explorer-like navigation in the DBUI drawer: Tab/S-Tab to navigate items, l/CR to open/expand, h to collapse, q to close, <C-j> for bottom output
      vim.api.nvim_create_autocmd('FileType', {
        pattern = 'dbui',
        callback = function(args)
          vim.keymap.set('n', '<Tab>', 'j', { buffer = args.buf, silent = true, desc = 'Next Item' })
          vim.keymap.set('n', '<S-Tab>', 'k', { buffer = args.buf, silent = true, desc = 'Previous Item' })
          vim.keymap.set('n', 'l', '<Plug>(DBUI_SelectLine)', { buffer = args.buf, silent = true, desc = 'Open / Expand Node' })
          vim.keymap.set('n', '<CR>', '<Plug>(DBUI_SelectLine)', { buffer = args.buf, silent = true, desc = 'Open / Expand Node' })
          vim.keymap.set('n', 'h', '<Plug>(DBUI_GotoParentNode)', { buffer = args.buf, silent = true, desc = 'Collapse Node' })
          vim.keymap.set('n', '<C-j>', function() _G.BottomPanel.toggle_active() end, { buffer = args.buf, silent = true, desc = 'Bottom Output' })
          vim.keymap.set('n', 'q', '<cmd>DBUIClose<CR>', { buffer = args.buf, silent = true, desc = 'Close Database Drawer' })
        end,
      })

      -- Confine dbout strictly under Code Editor, preserving full-height DBUI right sidebar
      vim.api.nvim_create_autocmd({ 'FileType', 'BufWinEnter' }, {
        pattern = 'dbout',
        callback = function(args)
          vim.bo[args.buf].buflisted = false
          vim.keymap.set('n', 'q', ':close<CR>', { buffer = args.buf, silent = true, desc = 'Close Query Results' })

          vim.schedule(function()
            for _, win in ipairs(vim.api.nvim_list_wins()) do
              if vim.api.nvim_win_is_valid(win) then
                local buf = vim.api.nvim_win_get_buf(win)
                if vim.bo[buf].filetype == 'dbui' then
                  local cur_win = vim.api.nvim_get_current_win()
                  vim.api.nvim_set_current_win(win)
                  vim.cmd('wincmd L')
                  vim.cmd('vertical resize 25')
                  if vim.api.nvim_win_is_valid(cur_win) then
                    vim.api.nvim_set_current_win(cur_win)
                  end
                  break
                end
              end
            end
          end)
        end,
      })

      -- Automatically bind current active database to any opened .sql file
      vim.api.nvim_create_autocmd('FileType', {
        pattern = { 'sql', 'mysql', 'plsql' },
        callback = function(args)
          local db_url, db_name = M.get_active_db(args.buf)
          if db_url then
            vim.b[args.buf].db = db_url
            vim.b[args.buf].db_name = db_name
          end
        end,
      })
    end,
    keys = {
      {
        '<leader>bt',
        function()
          if _G.RightPanel then
            _G.RightPanel.open_dbui()
          else
            vim.cmd('DBUI')
          end
        end,
        desc = 'Database Explorer',
      },
      {
        '<leader>bq',
        function()
          M.open_query_scratchpad()
        end,
        desc = 'Query Scratchpad',
      },
      {
        '<leader>br',
        function()
          M.run_query()
        end,
        desc = 'Run Query',
        mode = { 'n', 'v' },
      },
      {
        '<leader>bc',
        function()
          M.select_connection()
        end,
        desc = 'Switch Database',
      },
      {
        '<leader>ba',
        function()
          M.add_connection()
        end,
        desc = 'Add Database',
      },
      { '<leader>bs', '<cmd>DBUISaveQuery<CR>', desc = 'Save Query' },
      {
        '<leader>bo',
        function()
          if _G.BottomPanel then
            _G.BottomPanel.open_dbout()
          end
        end,
        desc = 'Query Output',
      },
      {
        '<leader>bl',
        function()
          if _G.BottomPanel then
            _G.BottomPanel.open_dbout()
          end
        end,
        desc = 'Query Info',
      },
      {
        '<leader>bf',
        function()
          if _G.RightPanel then
            _G.RightPanel.open_dbui()
          else
            vim.cmd('DBUI')
          end
        end,
        desc = 'Focus Database',
      },
    },
  },
}
