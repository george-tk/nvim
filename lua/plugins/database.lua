local M = {}

local db_ui_dir = vim.fs.normalize(vim.fn.stdpath('data') .. '/db_ui')
local conn_file = db_ui_dir .. '/connections.json'
local active_file = db_ui_dir .. '/last_active.json'

-- Active connection state across all buffers (nil until a connection is active)
M.current_db = nil
M.current_db_name = nil

-------------------------------------------------------------------------------
-- Persistent Connection Storage & DBUI Synchronization
-------------------------------------------------------------------------------

-- Save connections list to connections.json (Single Source of Truth)
function M.save_connections(connections)
  if vim.fn.isdirectory(db_ui_dir) == 0 then
    vim.fn.mkdir(db_ui_dir, 'p')
  end
  local json_str = vim.fn.json_encode(connections)
  vim.fn.writefile({ json_str }, conn_file)
  vim.g.dbs = nil
end

-- Read all persistent connections from connections.json
function M.get_all_connections()
  local connections = {}
  local seen = {}

  -- 1. Read persistent connections.json
  if vim.fn.filereadable(conn_file) == 1 then
    local ok, lines = pcall(vim.fn.readfile, conn_file)
    if ok and lines and #lines > 0 then
      local ok_json, parsed = pcall(vim.fn.json_decode, table.concat(lines, ''))
      if ok_json and type(parsed) == 'table' then
        for _, conn in ipairs(parsed) do
          if type(conn) == 'table' and conn.name and conn.url and not seen[conn.name] then
            seen[conn.name] = true
            table.insert(connections, { name = conn.name, url = conn.url })
          end
        end
      end
    end
  end

  -- 2. Merge any extra connections from vim.g.dbs if defined
  if vim.g.dbs and type(vim.g.dbs) == 'table' then
    local updated = false
    for _, entry in ipairs(vim.g.dbs) do
      if type(entry) == 'table' and entry.name and entry.url and not seen[entry.name] then
        seen[entry.name] = true
        table.insert(connections, { name = entry.name, url = entry.url })
        updated = true
      end
    end
    if updated then
      M.save_connections(connections)
    else
      vim.g.dbs = nil
    end
  else
    vim.g.dbs = nil
  end

  return connections
end

-- Save last active connection so it persists across sessions and restarts
function M.save_active_connection(name, url)
  if vim.fn.isdirectory(db_ui_dir) == 0 then
    vim.fn.mkdir(db_ui_dir, 'p')
  end
  vim.fn.writefile({ vim.fn.json_encode({ name = name, url = url }) }, active_file)
end

-- Check if a database connection URL is currently accessible/online
function M.is_accessible(url)
  if not url or url == '' then return false end
  if url:match('^sqlite:') then
    local path = url:gsub('^sqlite:', '')
    return vim.fn.filereadable(path) == 1
  end

  local host, port = url:match('://[^@]*@?([^:/]+):?(%d*)')
  if not host or host == '' then
    host, port = url:match('://([^:/]+):?(%d*)')
  end
  if not host or host == '' then return false end
  if host == 'localhost' then host = '127.0.0.1' end
  port = tonumber(port)
  if not port then
    if url:match('^postgres') then port = 5432
    elseif url:match('^mysql') then port = 3306
    elseif url:match('^sqlserver') then port = 1433
    else port = 5432 end
  end

  local accessible = false
  local done = false
  local tcp = vim.uv.new_tcp()
  if not tcp then return false end
  local ok = pcall(tcp.connect, tcp, host, port, function(cerr)
    if not cerr then accessible = true end
    tcp:close()
    done = true
  end)
  if not ok then
    pcall(function() tcp:close() end)
    return false
  end
  vim.wait(80, function() return done end, 5)
  if not done then
    pcall(function() tcp:close() end)
  end
  return accessible
end

-- Restore last active connection (with online verification)
function M.load_active_connection()
  local conns = M.get_all_connections()
  if #conns == 0 then
    M.current_db = nil
    M.current_db_name = nil
    return nil, nil
  end

  if vim.fn.filereadable(active_file) == 1 then
    local ok, lines = pcall(vim.fn.readfile, active_file)
    if ok and lines and #lines > 0 then
      local ok_json, parsed = pcall(vim.fn.json_decode, table.concat(lines, ''))
      if ok_json and type(parsed) == 'table' and parsed.name and parsed.url then
        local found = false
        for _, c in ipairs(conns) do
          if c.name == parsed.name and c.url == parsed.url then
            found = true
            break
          end
        end
        if found and M.is_accessible(parsed.url) then
          M.current_db = parsed.url
          M.current_db_name = parsed.name
          return parsed.url, parsed.name
        end
      end
    end
  end

  M.current_db = nil
  M.current_db_name = nil
  return nil, nil
end

-- Set active connection across global state, disk persistence, and all open SQL buffers
function M.set_active_connection(name, url)
  M.current_db = url
  M.current_db_name = name
  M.save_active_connection(name, url)

  -- Update all active SQL buffers
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) then
      local ft = vim.bo[buf].filetype
      if ft == 'sql' or ft == 'mysql' or ft == 'plsql' then
        vim.b[buf].db = url
        vim.b[buf].db_name = name
      end
    end
  end

  M.redraw_dbui()
end

-- Redraw the DBUI drawer if currently open, or reset state for next open
function M.redraw_dbui()
  pcall(function()
    if vim.fn.exists('*db_ui#drawer#get') == 1 then
      local drawer = vim.fn['db_ui#drawer#get']()
      if type(drawer) == 'table' and drawer.is_opened and drawer.is_opened() == 1 then
        if drawer.render then
          drawer.render({ dbs = 1, queries = 1 })
          return
        end
      end
    end
    if vim.fn.exists('*db_ui#reset_state') == 1 then
      vim.fn['db_ui#reset_state']()
    end
  end)
end

-- Initialize persistent connections & state
function M.init()
  M.get_all_connections()
  M.load_active_connection()
end

-- Run initialization immediately on load
M.init()

-- Resolve the active database for any buffer
function M.get_active_db(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return nil, nil
  end

  -- 1. Buffer already has an assigned database
  local ok_db, db_val = pcall(function() return vim.b[buf].db end)
  local ok_name, db_name_val = pcall(function() return vim.b[buf].db_name end)
  if ok_db and db_val and db_val ~= '' then
    local name = (ok_name and db_name_val) or M.current_db_name or 'Database'
    return db_val, name
  end

  -- 2. Buffer is inside db_ui folder for a specific database (e.g. ~/.local/share/nvim/db_ui/<dbname>/...)
  local bname = vim.api.nvim_buf_get_name(buf)
  if bname and bname ~= '' and bname:find('/db_ui/') then
    local conns = M.get_all_connections()
    for _, c in ipairs(conns) do
      if bname:find('/db_ui/' .. c.name .. '/') then
        if M.is_accessible(c.url) then
          pcall(function()
            vim.b[buf].db = c.url
            vim.b[buf].db_name = c.name
          end)
          return c.url, c.name
        end
      end
    end

    -- Scratchpad inside db_ui directory
    if bname:find('scratchpad.sql') and M.current_db and M.is_accessible(M.current_db) then
      pcall(function()
        vim.b[buf].db = M.current_db
        vim.b[buf].db_name = M.current_db_name
      end)
      return M.current_db, M.current_db_name
    end
  end

  return nil, nil
end

-------------------------------------------------------------------------------
-- Interactive Connection Switcher & Connection Management (<leader>bc, <leader>ba)
-------------------------------------------------------------------------------

function M.select_connection(callback)
  local connections = M.get_all_connections()
  local items = {}

  for _, entry in ipairs(connections) do
    local is_current = (entry.name == M.current_db_name or entry.url == M.current_db)
    table.insert(items, {
      text = (is_current and '● ' or '○ ') .. entry.name .. '  (' .. entry.url .. ')',
      name = entry.name,
      url = entry.url,
      action = 'select',
    })
  end

  table.insert(items, {
    text = '+ Add New Database Connection (Postgres, MSSQL, SQLite, MySQL)...',
    action = 'add',
  })

  if #connections > 0 then
    table.insert(items, {
      text = '- Remove a Database Connection...',
      action = 'delete',
    })
  end

  Snacks.picker.select(items, {
    prompt = 'Database Connection [Active: ' .. (M.current_db_name or 'None') .. ']',
    format_item = function(item)
      return item.text
    end,
  }, function(choice)
    if not choice then return end

    if choice.action == 'add' then
      M.add_connection(callback)
      return
    end

    if choice.action == 'delete' then
      M.delete_connection()
      return
    end

    M.set_active_connection(choice.name, choice.url)
    local cur_buf = vim.api.nvim_get_current_buf()
    vim.b[cur_buf].db = choice.url
    vim.b[cur_buf].db_name = choice.name

    vim.notify('Active database: ' .. choice.name, vim.log.levels.INFO, { title = 'Database' })

    if callback then
      callback(choice.url, choice.name)
    end
  end)
end

function M.add_connection(callback)
  vim.ui.input({
    prompt = 'Connection URL (e.g. postgresql://user:pass@host:5432/db or sqlite:/path/db or sqlserver://...): ',
  }, function(url)
    if not url or url:match('^%s*$') then return end
    url = vim.trim(url)

    local default_name = url:match('([^/:]+)$') or 'Remote DB'
    vim.ui.input({
      prompt = 'Connection Name: ',
      default = default_name,
    }, function(name)
      if not name or name:match('^%s*$') then return end
      name = vim.trim(name)

      local connections = M.get_all_connections()
      local updated = false
      for i, conn in ipairs(connections) do
        if conn.name == name then
          connections[i].url = url
          updated = true
          break
        end
      end

      if not updated then
        table.insert(connections, { name = name, url = url })
      end

      M.save_connections(connections)
      M.set_active_connection(name, url)

      vim.notify('Added & connected: ' .. name, vim.log.levels.INFO, { title = 'Database' })

      if callback then
        callback(url, name)
      end
    end)
  end)
end

function M.delete_connection()
  local connections = M.get_all_connections()
  local items = {}
  for _, conn in ipairs(connections) do
    table.insert(items, {
      text = conn.name .. ' (' .. conn.url .. ')',
      name = conn.name,
    })
  end

  if #items == 0 then
    vim.notify('No database connections to remove.', vim.log.levels.INFO, { title = 'Database' })
    return
  end

  Snacks.picker.select(items, {
    prompt = 'Select Connection to Remove',
    format_item = function(item) return item.text end,
  }, function(choice)
    if not choice then return end

    local remaining = {}
    for _, conn in ipairs(connections) do
      if conn.name ~= choice.name then
        table.insert(remaining, conn)
      end
    end

    M.save_connections(remaining)

    if M.current_db_name == choice.name then
      pcall(vim.fn.delete, active_file)
      M.current_db = nil
      M.current_db_name = nil
      M.load_active_connection()
    end

    local conn_dir = db_ui_dir .. '/' .. choice.name
    if vim.fn.isdirectory(conn_dir) == 1 then
      local files = vim.fn.glob(conn_dir .. '/*', true, true)
      if #files == 0 then
        pcall(vim.fn.delete, conn_dir, 'd')
      end
    end

    M.redraw_dbui()
    vim.notify('Removed database connection: ' .. choice.name, vim.log.levels.INFO, { title = 'Database' })
  end)
end

-------------------------------------------------------------------------------
-- Query Scratchpad, Execution, and Save Management (<leader>bq, <leader>br, <leader>bw)
-------------------------------------------------------------------------------

function M.open_query_scratchpad()
  local scratch_file = vim.fs.normalize(db_ui_dir .. '/scratchpad.sql')
  if vim.fn.isdirectory(db_ui_dir) == 0 then
    vim.fn.mkdir(db_ui_dir, 'p')
  end
  if vim.fn.filereadable(scratch_file) == 0 then
    vim.fn.writefile({ '-- SQL Query Scratchpad', '-- Press <leader>br to execute, <leader>bs to switch DB, <leader>bw to save', '' }, scratch_file)
  end

  local cur_buf = vim.api.nvim_get_current_buf()
  if vim.api.nvim_buf_is_valid(cur_buf) and vim.api.nvim_buf_get_name(cur_buf) == scratch_file then
    return
  end

  local ok, _ = pcall(vim.cmd, 'edit ' .. vim.fn.fnameescape(scratch_file))
  if not ok then
    pcall(vim.cmd, 'split ' .. vim.fn.fnameescape(scratch_file))
  end

  local buf = vim.api.nvim_get_current_buf()
  if vim.api.nvim_buf_is_valid(buf) then
    vim.bo[buf].buflisted = false
    vim.b[buf].neocodeium_enabled = true
    vim.b[buf].neocodeium_allowed_encoding = true

    local db_url, db_name = M.get_active_db(buf)
    if not db_url then
      M.select_connection(function(new_url, new_name)
        pcall(function()
          vim.b[buf].db = new_url
          vim.b[buf].db_name = new_name
        end)
        vim.notify('SQL Scratchpad connected to ' .. (new_name or 'Database'), vim.log.levels.INFO, { title = 'Database' })
      end)
    else
      pcall(function()
        vim.b[buf].db = db_url
        vim.b[buf].db_name = db_name
      end)
      vim.notify('SQL Scratchpad connected to ' .. db_name, vim.log.levels.INFO, { title = 'Database' })
    end
  end
end

function M.save_query()
  local buf = vim.api.nvim_get_current_buf()
  local current_name = vim.api.nvim_buf_get_name(buf)
  local is_on_disk = current_name ~= '' and vim.fn.filereadable(current_name) == 1

  -- 1. If already an existing file on disk, simply write changes
  if is_on_disk and vim.bo[buf].buftype == '' then
    local ok, err = pcall(vim.cmd, 'write')
    if ok then
      vim.notify('Query file saved: ' .. vim.fn.fnamemodify(current_name, ':t'), vim.log.levels.INFO, { title = 'Database' })
      M.redraw_dbui()
    else
      vim.notify('Error saving query: ' .. tostring(err), vim.log.levels.ERROR, { title = 'Database' })
    end
    return
  end

  -- 2. If inside a DBUI managed temporary query buffer with <Plug>(DBUI_SaveQuery) available
  if vim.b[buf].dbui_db_key_name and vim.fn.maparg('<Plug>(DBUI_SaveQuery)', 'n') ~= '' then
    local key = vim.api.nvim_replace_termcodes('<Plug>(DBUI_SaveQuery)', true, false, true)
    vim.api.nvim_feedkeys(key, 'm', false)
    return
  end

  -- 3. Scratchpad or unnamed buffer: save into DBUI's saved queries for active database
  local _, db_name = M.get_active_db(buf)
  db_name = db_name or M.current_db_name or 'Database'

  vim.ui.input({
    prompt = 'Save Query Name (for ' .. db_name .. '): ',
    default = 'query_' .. os.date('%Y%m%d_%H%M%S'),
  }, function(input_name)
    if not input_name or input_name:match('^%s*$') then return end
    input_name = vim.trim(input_name)
    if not input_name:match('%.sql$') then
      input_name = input_name .. '.sql'
    end

    local save_dir = db_ui_dir .. '/' .. db_name
    if vim.fn.isdirectory(save_dir) == 0 then
      vim.fn.mkdir(save_dir, 'p')
    end

    local full_path = save_dir .. '/' .. input_name
    local ok, err = pcall(function()
      vim.cmd('write! ' .. vim.fn.fnameescape(full_path))
      vim.cmd('file ' .. vim.fn.fnameescape(full_path))
      vim.bo[buf].filetype = 'sql'
      vim.bo[buf].buftype = ''
      vim.b[buf].db = M.current_db
      vim.b[buf].db_name = db_name
    end)

    if ok then
      vim.notify('Saved query to ' .. db_name .. ': ' .. input_name, vim.log.levels.INFO, { title = 'Database' })
      M.redraw_dbui()
    else
      vim.notify('Failed to save query: ' .. tostring(err), vim.log.levels.ERROR, { title = 'Database' })
    end
  end)
end

function M.run_query()
  local buf = vim.api.nvim_get_current_buf()
  local db_url, db_name = M.get_active_db(buf)

  if not db_url then
    if M.current_db and M.is_accessible(M.current_db) then
      pcall(function()
        vim.b[buf].db = M.current_db
        vim.b[buf].db_name = M.current_db_name
      end)
      db_url = M.current_db
      db_name = M.current_db_name
    else
      M.select_connection(function(new_url, new_name)
        pcall(function()
          vim.b[buf].db = new_url
          vim.b[buf].db_name = new_name
        end)
        M.run_query()
      end)
      return
    end
  end

  local mode = vim.api.nvim_get_mode().mode
  local is_visual = mode:match('[vV\x16]') ~= nil
  if is_visual then
    -- Exit visual mode immediately so marks '< and '> are set
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'x', false)
  end

  -- 1. If inside DBUI managed buffer, trigger native DBUI execute
  if vim.fn.exists('*db_ui#query#new') == 1 and vim.b[buf].dbui_db_key_name then
    local plug_name = is_visual and '<Plug>(DBUI_ExecuteQuery)' or '<Plug>(DBUI_ExecuteQuery)'
    local key = vim.api.nvim_replace_termcodes(plug_name, true, false, true)
    vim.api.nvim_feedkeys(key, 'm', false)
    return
  end

  -- 2. Save file if on disk
  if vim.bo[buf].modified and vim.bo[buf].buftype == '' and vim.fn.expand('%') ~= '' then
    vim.cmd('silent! write')
  end

  -- 3. Execute query via vim-dadbod
  if is_visual then
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
      vim.g.db_ui_tmp_query_location = data_path .. '/tmp'
      vim.g.db_ui_use_nerd_fonts = 1
      vim.g.db_ui_show_database_icon = 1
      vim.g.db_ui_auto_execute_table_helpers = 1
      vim.g.db_ui_winwidth = 35
      vim.g.db_ui_win_position = 'right' -- Strictly Right Side
      vim.g.db_ui_use_nvim_notify = 1
      vim.g.db_ui_default_query = 'SELECT * FROM {optional_schema}"{table}" LIMIT 50;'
      vim.g.db_ui_disable_mappings_sql = 1 -- Disable default uppercase <Leader>W, <Leader>E, <Leader>S mappings

      -- Generate query buffer names ending in .sql so Treesitter, Blink.cmp, and NeoCodeium AI recognize them
      vim.g.Db_ui_buffer_name_generator = function(opts)
        local time = os.date('%Y%m%d_%H%M%S')
        local suffix = (opts.table and opts.table ~= '') and (opts.table .. '_' .. (opts.label or 'query')) or 'query'
        return string.format('%s_%s.sql', suffix, time)
      end

      -- Automatically recognize any query file inside db_ui directory as SQL
      vim.filetype.add({
        pattern = {
          ['.*/db_ui/.*'] = function(path)
            if path:match('%.json$') then return 'json' end
            return 'sql'
          end,
        },
      })

      -- Initialize persistent connections & state from connections.json
      M.init()

      -- Table helpers for quick queries in the drawer
      vim.g.db_ui_table_helpers = {
        sqlite = {
          ['Count'] = 'SELECT count(*) FROM {table};',
          ['First 10'] = 'SELECT * FROM {table} LIMIT 10;',
          ['List'] = 'SELECT * FROM {table} LIMIT 50;',
          ['Describe'] = 'PRAGMA table_info({table});',
        },
        sqlserver = {
          ['Count'] = 'SELECT count(*) FROM [{table}];',
          ['Top 10'] = 'SELECT TOP 10 * FROM [{table}];',
          ['First 10'] = 'SELECT TOP 10 * FROM [{table}];',
          ['List'] = 'SELECT TOP 50 * FROM [{table}];',
          ['Describe'] = "SELECT COLUMN_NAME, DATA_TYPE, CHARACTER_MAXIMUM_LENGTH FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = '{table}';",
        },
        postgresql = {
          ['Count'] = 'SELECT count(*) FROM {optional_schema}"{table}";',
          ['First 10'] = 'SELECT * FROM {optional_schema}"{table}" LIMIT 10;',
          ['List'] = 'SELECT * FROM {optional_schema}"{table}" LIMIT 50;',
        },
        postgres = {
          ['Count'] = 'SELECT count(*) FROM {optional_schema}"{table}";',
          ['First 10'] = 'SELECT * FROM {optional_schema}"{table}" LIMIT 10;',
          ['List'] = 'SELECT * FROM {optional_schema}"{table}" LIMIT 50;',
        },
        mysql = {
          ['Count'] = 'SELECT count(*) FROM {table};',
          ['First 10'] = 'SELECT * FROM {table} LIMIT 10;',
          ['List'] = 'SELECT * FROM {table} LIMIT 50;',
          ['Describe'] = 'DESCRIBE {table};',
        },
        mariadb = {
          ['Count'] = 'SELECT count(*) FROM {table};',
          ['First 10'] = 'SELECT * FROM {table} LIMIT 10;',
          ['List'] = 'SELECT * FROM {table} LIMIT 50;',
          ['Describe'] = 'DESCRIBE {table};',
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

          -- Smart SQL Table Cell Navigation
          local function get_segments(l)
            local pipes = {}
            local p = 0
            while true do
              p = l:find('|', p + 1)
              if not p then break end
              table.insert(pipes, p - 1)
            end
            if #pipes == 0 then return nil end
            local segs = {}
            table.insert(segs, { from = 0, to = pipes[1] - 1 })
            for i = 1, #pipes - 1 do
              table.insert(segs, { from = pipes[i] + 1, to = pipes[i + 1] - 1 })
            end
            table.insert(segs, { from = pipes[#pipes] + 1, to = #l - 1 })
            return segs
          end

          local function jump_cell(direction, wrap)
            local cur_line = vim.fn.line('.')
            local total_lines = vim.fn.line('$')
            local line = vim.api.nvim_get_current_line()
            local cur_col = vim.api.nvim_win_get_cursor(0)[2]

            local segments = get_segments(line)
            if not segments then return end

            local cur_seg = 1
            for i, seg in ipairs(segments) do
              if cur_col >= seg.from and cur_col <= seg.to then
                cur_seg = i
                break
              end
            end

            local target_idx = cur_seg + direction
            if target_idx >= 1 and target_idx <= #segments then
              local target_seg = segments[target_idx]
              local seg_text = line:sub(target_seg.from + 1, target_seg.to + 1)
              local non_space = seg_text:find('%S')
              local target_col = target_seg.from + (non_space and (non_space - 1) or 0)
              vim.api.nvim_win_set_cursor(0, { cur_line, target_col })
            elseif wrap and direction > 0 and cur_line < total_lines then
              local next_lnum = cur_line + 1
              while next_lnum <= total_lines do
                local nl = vim.fn.getline(next_lnum)
                if nl:find('|') and not nl:match('^[%s%-%+|=]+$') then
                  local next_segs = get_segments(nl)
                  if next_segs and #next_segs > 0 then
                    local seg_text = nl:sub(next_segs[1].from + 1, next_segs[1].to + 1)
                    local non_space = seg_text:find('%S')
                    local target_col = next_segs[1].from + (non_space and (non_space - 1) or 0)
                    vim.api.nvim_win_set_cursor(0, { next_lnum, target_col })
                    return
                  end
                end
                next_lnum = next_lnum + 1
              end
            elseif wrap and direction < 0 and cur_line > 1 then
              local prev_lnum = cur_line - 1
              while prev_lnum >= 1 do
                local pl = vim.fn.getline(prev_lnum)
                if pl:find('|') and not pl:match('^[%s%-%+|=]+$') then
                  local prev_segs = get_segments(pl)
                  if prev_segs and #prev_segs > 0 then
                    local last_seg = prev_segs[#prev_segs]
                    local seg_text = pl:sub(last_seg.from + 1, last_seg.to + 1)
                    local non_space = seg_text:find('%S')
                    local target_col = last_seg.from + (non_space and (non_space - 1) or 0)
                    vim.api.nvim_win_set_cursor(0, { prev_lnum, target_col })
                    return
                  end
                end
                prev_lnum = prev_lnum - 1
              end
            end
          end

          local function jump_row(direction)
            local cur_line = vim.fn.line('.')
            local total_lines = vim.fn.line('$')
            local cur_col = vim.api.nvim_win_get_cursor(0)[2]
            local target_lnum = cur_line + direction

            while target_lnum >= 1 and target_lnum <= total_lines do
              local line = vim.fn.getline(target_lnum)
              if line:find('|') and not line:match('^[%s%-%+|=]+$') then
                vim.api.nvim_win_set_cursor(0, { target_lnum, math.min(cur_col, #line - 1) })
                return
              end
              target_lnum = target_lnum + direction
            end
          end

          vim.keymap.set('n', '<Tab>', function() jump_cell(1, true) end, { buffer = args.buf, silent = true, desc = 'Next Cell' })
          vim.keymap.set('n', '<S-Tab>', function() jump_cell(-1, true) end, { buffer = args.buf, silent = true, desc = 'Previous Cell' })
          vim.keymap.set('n', 'L', function() jump_cell(1, false) end, { buffer = args.buf, silent = true, desc = 'Next Column' })
          vim.keymap.set('n', 'H', function() jump_cell(-1, false) end, { buffer = args.buf, silent = true, desc = 'Previous Column' })
          vim.keymap.set('n', ']r', function() jump_row(1) end, { buffer = args.buf, silent = true, desc = 'Next Table Row' })
          vim.keymap.set('n', '[r', function() jump_row(-1) end, { buffer = args.buf, silent = true, desc = 'Previous Table Row' })

          vim.schedule(function()
            for _, win in ipairs(vim.api.nvim_list_wins()) do
              if vim.api.nvim_win_is_valid(win) then
                local buf = vim.api.nvim_win_get_buf(win)
                local ft = vim.bo[buf].filetype
                if ft == 'dbui' or ft:match('^Neogit') then
                  local cur_win = vim.api.nvim_get_current_win()
                  vim.api.nvim_set_current_win(win)
                  vim.cmd('wincmd L')
                  local width = ft == 'dbui' and 25 or math.max(38, math.floor(vim.o.columns * 0.38))
                  vim.cmd('vertical resize ' .. width)
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

      -- Automatically bind current active database and enable AI completion for any opened .sql file
      vim.api.nvim_create_autocmd('FileType', {
        pattern = { 'sql', 'mysql', 'plsql' },
        callback = function(args)
          -- Never bind or trigger connection fetch during session restoration
          if vim.g.SessionLoad == 1 then
            return
          end

          local buf = args.buf
          if not buf or not vim.api.nvim_buf_is_valid(buf) then
            return
          end

          local db_url, db_name = M.get_active_db(buf)
          if db_url and M.is_accessible(db_url) then
            pcall(function()
              vim.b[buf].db = db_url
              vim.b[buf].db_name = db_name
            end)
          end
          pcall(function()
            vim.b[buf].neocodeium_enabled = true
            vim.b[buf].neocodeium_allowed_encoding = true
          end)
        end,
      })

      -- SQLite binary database files: never treat as text files or save into sessions
      vim.api.nvim_create_autocmd({ 'BufReadPre', 'BufNewFile' }, {
        pattern = { '*.db', '*.sqlite', '*.sqlite3' },
        callback = function(args)
          vim.bo[args.buf].buflisted = false
          vim.bo[args.buf].swapfile = false
        end,
      })
    end,
    keys = {
      {
        '<leader>be',
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
        '<leader>bs',
        function()
          M.select_connection()
        end,
        desc = 'Switch Database',
      },
      {
        '<leader>bw',
        function()
          M.save_query()
        end,
        desc = 'Save Query',
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
        '<leader>bq',
        function()
          M.open_query_scratchpad()
        end,
        desc = 'Query Scratchpad',
      },
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
        '<leader>ba',
        function()
          M.add_connection()
        end,
        desc = 'Add Database',
      },
      {
        '<leader>bd',
        function()
          M.delete_connection()
        end,
        desc = 'Delete Database',
      },
    },
  },
}
