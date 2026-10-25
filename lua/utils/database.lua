local M = {}

local sqmeow_dir = vim.fs.normalize(vim.fn.stdpath 'data' .. '/sqmeow')
local sqmeow_scratch_dir = vim.fs.normalize(sqmeow_dir .. '/scratch')
local sqmeow_conn_file = sqmeow_dir .. '/connections.json'
local active_file = sqmeow_dir .. '/last_active.json'

-- Active connection state across all buffers (nil until a connection is active)
M.current_db = nil
M.current_db_name = nil

-- Helper to load sqmeow native modules with lazy fallback
local function sqmeow(submod)
  local mod_name = 'sqmeow.' .. submod
  local ok, mod = pcall(require, mod_name)
  if not ok then
    pcall(function()
      require('lazy').load { plugins = { 'sqmeow.nvim' } }
    end)
    ok, mod = pcall(require, mod_name)
  end
  return ok and mod or nil
end

-------------------------------------------------------------------------------
-- Persistent Connection Storage & Management (sqmeow.nvim)
-------------------------------------------------------------------------------

-- Save connections list to sqmeow connections.json
function M.save_connections(connections)
  if vim.fn.isdirectory(sqmeow_dir) == 0 then
    vim.fn.mkdir(sqmeow_dir, 'p')
  end

  local json_str = vim.fn.json_encode(connections)
  vim.fn.writefile({ json_str }, sqmeow_conn_file)
  vim.g.dbs = nil
end

-- Read all persistent connections from sqmeow connections.json
function M.get_all_connections()
  local connections = {}
  local seen = {}

  if vim.fn.filereadable(sqmeow_conn_file) == 1 then
    local ok, lines = pcall(vim.fn.readfile, sqmeow_conn_file)
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

  -- Merge any extra connections from vim.g.dbs if defined
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
  if vim.fn.isdirectory(sqmeow_dir) == 0 then
    vim.fn.mkdir(sqmeow_dir, 'p')
  end
  vim.fn.writefile({ vim.fn.json_encode { name = name, url = url } }, active_file)
end

-- Check if a database connection URL is currently accessible/online
function M.is_accessible(url)
  if not url or url == '' then
    return false
  end
  if url:match '^sqlite:' then
    local path = url:gsub('^sqlite:', '')
    return vim.fn.filereadable(path) == 1
  end

  local host, port = url:match '://[^@]*@?([^:/]+):?(%d*)'
  if not host or host == '' then
    host, port = url:match '://([^:/]+):?(%d*)'
  end
  if not host or host == '' then
    return false
  end
  if host == 'localhost' then
    host = '127.0.0.1'
  end
  port = tonumber(port)
  if not port then
    if url:match '^postgres' then
      port = 5432
    elseif url:match '^mysql' then
      port = 3306
    elseif url:match '^sqlserver' then
      port = 1433
    else
      port = 5432
    end
  end

  local accessible = false
  local done = false
  local tcp = vim.uv.new_tcp()
  if not tcp then
    return false
  end
  local ok = pcall(tcp.connect, tcp, host, port, function(cerr)
    if not cerr then
      accessible = true
    end
    tcp:close()
    done = true
  end)
  if not ok then
    pcall(function()
      tcp:close()
    end)
    return false
  end
  vim.wait(80, function()
    return done
  end, 5)
  if not done then
    pcall(function()
      tcp:close()
    end)
  end
  return accessible
end

-- Restore last active connection
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
          if c.name == parsed.name then
            found = true
            break
          end
        end
        if found then
          M.current_db = parsed.url
          M.current_db_name = parsed.name
          return parsed.url, parsed.name
        end
      end
    end
  end

  if #conns > 0 then
    M.current_db = conns[1].url
    M.current_db_name = conns[1].name
    return conns[1].url, conns[1].name
  end

  M.current_db = nil
  M.current_db_name = nil
  return nil, nil
end

function M.get_connection_url(name)
  if not name or name == '' then
    return nil
  end

  -- Check active sqmeow connections first (e.g. child connections like "cluster/testdb")
  local state = sqmeow 'core.state'
  if state and state.connections then
    local conn = state.connection_by_name(name)
    if conn then
      if conn.database and conn.url and not conn.url:match('/' .. conn.database .. '$') then
        local base = conn.url:gsub('/+$', '')
        return base .. '/' .. conn.database
      end
      return conn.url
    end
  end

  if name:find '/' then
    local parent_name, child_db = name:match '^([^/]+)/(.+)$'
    if parent_name and child_db then
      local parent_url = M.get_connection_url(parent_name)
      if parent_url then
        local base = parent_url:gsub('/+$', '')
        return base .. '/' .. child_db
      end
    end
  end

  local conns = M.get_all_connections()
  for _, c in ipairs(conns) do
    if c.name == name then
      return c.url
    end
  end
  return nil
end

-- Ensure connection is active in sqmeow using upstream connect_named or active child connection
function M.ensure_sqmeow_connection(db_name, non_blocking)
  if not db_name or db_name == '' then
    return nil
  end

  local state = sqmeow 'core.state'
  local api = sqmeow 'api.connection'
  if not api or not state then
    return nil
  end

  -- If it is already an active open connection (including child connections like "cluster/testdb"), activate it
  if state and state.connections then
    local conn = state.connection_by_name(db_name)
    if conn and conn.state ~= 'closed' then
      api.use(conn.id)
      return conn.id
    end
  end

  -- If it's a child connection like "parent/child", ensure parent is open and look for child
  if db_name:find '/' then
    local parent_name, child_db = db_name:match '^([^/]+)/(.+)$'
    if parent_name and child_db then
      local parent_conn = state and state.connection_by_name(parent_name)
      if not parent_conn or parent_conn.state == 'closed' then
        pcall(function()
          api.connect_named(parent_name)
        end)
        parent_conn = state and state.connection_by_name(parent_name)
      end

      local function activate_child(pconn)
        local child = state.child_connection and state.child_connection(pconn.id, child_db)
        if child and child.id then
          api.use(child.id)
          return child.id
        end
        local child_id = api.connect(pconn.url, {
          name = db_name,
          parent = pconn.id,
          database = child_db,
          read_only = pconn.read_only,
          ssh = pconn.ssh,
        })
        if child_id then
          api.use(child_id)
          return child_id
        end
        return nil
      end

      if parent_conn and parent_conn.state == 'connected' then
        return activate_child(parent_conn)
      end

      if non_blocking then
        local rpc = sqmeow 'rpc.client'
        if rpc and rpc.on and parent_conn then
          local unsub
          unsub = rpc.on('conn:state', function(payload)
            if payload.id == parent_conn.id and payload.state == 'connected' then
              if unsub then
                unsub()
              end
              vim.schedule(function()
                local pnow = state.connections[parent_conn.id]
                if pnow then
                  activate_child(pnow)
                end
              end)
            end
          end)
        end
        return parent_conn and parent_conn.id or nil
      end

      local waited = 0
      while waited < 2000 do
        parent_conn = state and state.connection_by_name(parent_name)
        if parent_conn and parent_conn.state == 'connected' then
          break
        end
        vim.wait(50, function()
          return false
        end)
        waited = waited + 50
      end

      if state and parent_conn and parent_conn.state == 'connected' then
        return activate_child(parent_conn)
      end
    end
  end

  local id = nil
  pcall(function()
    id = api.connect_named(db_name)
  end)
  if id then
    pcall(function()
      api.use(id)
    end)
    if not non_blocking then
      local waited = 0
      while waited < 2000 do
        local c = state.connections[id]
        if c and c.state == 'connected' then
          break
        end
        vim.wait(50, function()
          local cur = state.connections[id]
          return (cur and cur.state == 'connected') or state.failures[db_name] ~= nil
        end)
        waited = waited + 50
      end
    end
  end
  return id
end

-- Set active connection on the target buffer (per-buffer) and update default persistence
function M.set_active_connection(name, url, target_buf)
  M.current_db = url
  M.current_db_name = name
  M.save_active_connection(name, url)

  -- Bind only the target editor buffer (never overwrite other open SQL buffers)
  local buf = target_buf
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    local ed_win = _G.RightPanel and _G.RightPanel.get_editor_win and _G.RightPanel.get_editor_win()
    if ed_win and vim.api.nvim_win_is_valid(ed_win) then
      buf = vim.api.nvim_win_get_buf(ed_win)
    else
      buf = vim.api.nvim_get_current_buf()
    end
  end

  if buf and vim.api.nvim_buf_is_valid(buf) then
    local ft = vim.bo[buf].filetype
    if ft ~= 'sqmeow-drawer' and ft ~= 'sqmeow-result' and ft ~= 'dbui' and ft ~= 'dbout' then
      vim.b[buf].db_name = name
      vim.b[buf].sqmeow_connection = name
    end
  end

  -- Connect & use connection in sqmeow without duplicating
  M.ensure_sqmeow_connection(name)

  local ok_lualine, lualine = pcall(require, 'lualine')
  if ok_lualine and lualine.refresh then
    lualine.refresh()
  end
end

-- Initialize persistent connections & state
function M.init()
  M.get_all_connections()
  M.load_active_connection()
end

M.init()

-- Extract table name from a SQL query string
function M.detect_table_from_sql(sql)
  if not sql or type(sql) ~= 'string' then
    return nil
  end
  local raw = sql:match '[Ff][Rr][Oo][Mm]%s+([%w_%.%"`%[%]]+)'
    or sql:match '[Ii][Nn][Ss][Ee][Rr][Tt]%s+[Ii][Nn][Tt][Oo]%s+([%w_%.%"`%[%]]+)'
    or sql:match '[Uu][Pp][Dd][Aa][Tt][Ee]%s+([%w_%.%"`%[%]]+)'
    or sql:match '[Tt][Aa][Bb][Ll][Ee]%s+([%w_%.%"`%[%]]+)'
  if raw then
    raw = raw:gsub('["`%[%]]', '')
    local upper = raw:upper()
    local ignored = {
      WHERE = true,
      SET = true,
      SELECT = true,
      VALUES = true,
      JOIN = true,
      IF = true,
      ONLY = true,
      DUAL = true,
    }
    if not ignored[upper] and raw ~= '' then
      return raw
    end
  end
  return nil
end

-- Detect table name from buffer lines (checks first 30 lines)
function M.detect_table_from_buffer(buf)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return nil
  end
  local lines = vim.api.nvim_buf_get_lines(buf, 0, 30, false)
  if #lines == 0 then
    return nil
  end
  local text = table.concat(lines, ' ')
  return M.detect_table_from_sql(text)
end

-- Resolve the active table for any buffer
function M.get_active_table(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return nil
  end

  -- 1. Explicit buffer variable
  if vim.b[buf].sqmeow_table and vim.b[buf].sqmeow_table ~= '' then
    return vim.b[buf].sqmeow_table
  end

  -- 2. Buffer name pattern: [Preview: <table>] or [Alter: <table>]
  local bname = vim.api.nvim_buf_get_name(buf)
  local tbl = bname:match '%[Preview:%s*([^%]]+)%]' or bname:match '%[Alter:%s*([^%]]+)%]'
  if tbl then
    tbl = tbl:gsub('%s*%(%d+%)', '')
    tbl = vim.trim(tbl)
    if tbl ~= '' then
      return tbl
    end
  end

  -- 3. Result buffer (sqmeow-result / dbout)
  local ft = vim.bo[buf].filetype
  if ft == 'sqmeow-result' or ft == 'dbout' or bname:find 'sqmeow://result' then
    local ok_st, st = pcall(require, 'sqmeow.core.state')
    if ok_st and st and st.call then
      if st.call.source and st.call.source.name then
        return st.call.source.name
      end
      if st.call.statement then
        local t = M.detect_table_from_sql(st.call.statement)
        if t then
          return t
        end
      end
    end
  end

  -- 4. Parse SQL statements from buffer content
  if ft == 'sql' or ft == 'mysql' or ft == 'plsql' or ft == 'surql' or ft == 'cql' or vim.b[buf].sqmeow_editor then
    local t = M.detect_table_from_buffer(buf)
    if t then
      return t
    end
  end

  return nil
end

-- Resolve the active database for any buffer (strictly per-buffer first, global fallback last)
function M.get_active_db(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return nil, nil
  end

  -- 1. Check explicit buffer-local connection bindings first (`b:sqmeow_connection` / `b:db_name`)
  local ok_sq, sq_conn = pcall(function()
    return vim.b[buf].sqmeow_connection
  end)
  if ok_sq and sq_conn and sq_conn ~= '' then
    local url = M.get_connection_url(sq_conn)
    if url then
      return url, sq_conn
    end
    for _, c in ipairs(M.get_all_connections()) do
      if c.name == sq_conn then
        return c.url, c.name
      end
    end
    return nil, sq_conn
  end

  local ok_db, db_val = pcall(function()
    return vim.b[buf].db
  end)
  local ok_name, db_name_val = pcall(function()
    return vim.b[buf].db_name
  end)
  if ok_name and db_name_val and db_name_val ~= '' then
    local url = (ok_db and db_val and db_val ~= '' and db_val) or M.get_connection_url(db_name_val)
    return url, db_name_val
  end

  -- 2. Buffer path belongs to a specific database folder (e.g. scratch/<db_name>/*.sql)
  local buf_path = vim.fs.normalize(vim.api.nvim_buf_get_name(buf))
  if buf_path ~= '' then
    local candidates = {}
    local seen = {}

    local ok_state, state = pcall(require, 'sqmeow.core.state')
    if not ok_state then
      ok_state, state = pcall(require, 'sqmeow.state')
    end
    if ok_state and state and state.connections then
      for _, conn in pairs(state.connections) do
        if conn and conn.name and not seen[conn.name] then
          seen[conn.name] = true
          table.insert(candidates, { name = conn.name, url = conn.url })
        end
      end
    end

    local conns = M.get_all_connections()
    for _, c in ipairs(conns) do
      if not seen[c.name] then
        seen[c.name] = true
        table.insert(candidates, { name = c.name, url = c.url })
      end
    end

    table.sort(candidates, function(a, b)
      return #a.name > #b.name
    end)

    for _, c in ipairs(candidates) do
      local pattern = '/' .. c.name:gsub('([^%w])', '%%%1') .. '/'
      local pattern_under = '/' .. c.name:gsub('([^%w])', '%%%1') .. '_'
      if buf_path:find(pattern) or buf_path:find(pattern_under) then
        local sub_db = buf_path:match('/' .. c.name:gsub('([^%w])', '%%%1') .. '/([^/]+)/')
        if sub_db then
          local child_name = c.name .. '/' .. sub_db
          local child_url = M.get_connection_url(child_name) or (c.url and (c.url:gsub('/+$', '') .. '/' .. sub_db))
          return child_url, child_name
        end
        local conn_url = M.get_connection_url(c.name) or c.url
        return conn_url, c.name
      end
    end
  end

  if ok_db and db_val and db_val ~= '' then
    local name = M.current_db_name or 'Database'
    return db_val, name
  end

  -- 3. Check sqmeow target / active connection fallback for new unbound buffers
  local ok_target, conn_api = pcall(require, 'sqmeow.api.connection')
  if ok_target and conn_api and conn_api.target then
    local target = conn_api.target(buf)
    if target and target.name then
      local url = M.get_connection_url(target.name) or target.url
      return url, target.name
    end
  end

  -- 4. Active sqmeow state connection
  local ok_state, state = pcall(require, 'sqmeow.core.state')
  if ok_state and state and state.current_connection then
    local curr = state.current_connection()
    if curr and curr.name then
      local url = M.get_connection_url(curr.name) or curr.url
      return url, curr.name
    end
  end

  -- 5. Fallback to active connection
  if M.current_db_name and M.current_db_name ~= '' then
    return M.current_db, M.current_db_name
  end

  return nil, nil
end

-------------------------------------------------------------------------------
-- Spatial Drawer Docking & Right Panel Management
-------------------------------------------------------------------------------

function M.open_drawer()
  local view_api = sqmeow 'api.view'
  if not view_api then
    vim.notify('sqmeow.nvim is not loaded yet', vim.log.levels.WARN, { title = 'Database' })
    return
  end

  M.setup_drawer_helpers()

  -- If drawer is already open, toggle it off
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(win) then
      local buf = vim.api.nvim_win_get_buf(win)
      if vim.bo[buf].filetype == 'sqmeow-drawer' then
        view_api.close_drawer()
        return
      end
    end
  end

  -- Mutually exclusive with other right panels (File Explorer, OpenCode)
  if _G.RightPanel then
    if _G.RightPanel.active_mode == 'explorer' then
      pcall(function()
        Snacks.picker.pickers.explorer:close()
      end)
    end
    _G.RightPanel.active_mode = 'dbui'
  end

  view_api.open_drawer()

  -- Ensure drawer window is focused and spell is disabled
  vim.schedule(function()
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_is_valid(win) then
        local buf = vim.api.nvim_win_get_buf(win)
        if vim.bo[buf].filetype == 'sqmeow-drawer' then
          vim.wo[win].spell = false
          vim.api.nvim_set_current_win(win)
          break
        end
      end
    end
  end)
end

function M.setup_drawer_helpers()
  local drawer = sqmeow 'ui.drawer'
  if not drawer or not drawer.actions then
    return
  end

  -- 1. Hook drawer.actions.preview_editor to attach save-query on :w, manage preview ring slots, and track bottom panel dbout mode
  if not M._drawer_preview_hooked and drawer.actions.preview_editor then
    M._drawer_preview_hooked = true
    local orig_preview_editor = drawer.actions.preview_editor
    drawer.actions.preview_editor = function(...)
      local res = orig_preview_editor(...)
      local buf = drawer.preview_buffer()
      if buf and vim.api.nvim_buf_is_valid(buf) then
        vim.b[buf].is_preview_buffer = true

        local node = drawer.current_node and drawer.current_node()
        local conn_name = nil
        if node and node.conn_id then
          local ok_st, st = pcall(require, 'sqmeow.core.state')
          if ok_st and st and st.connections and st.connections[node.conn_id] then
            conn_name = st.connections[node.conn_id].name
          end
        end
        conn_name = conn_name or vim.b[buf].sqmeow_connection or M.current_db_name
        if conn_name then
          vim.b[buf].db_name = conn_name
          vim.b[buf].sqmeow_connection = conn_name
          M.current_db_name = conn_name
          local url = M.get_connection_url(conn_name)
          if url then
            M.current_db = url
          end
        end

        if node and node.name then
          vim.b[buf].sqmeow_table = node.name
          if node.path and node.path[1] then
            vim.b[buf].sqmeow_schema = node.path[1]
          end
        end

        local group = vim.api.nvim_create_augroup('SqmeowPreviewSave', { clear = false })
        pcall(vim.api.nvim_clear_autocmds, { buffer = buf, group = group })
        vim.api.nvim_create_autocmd('BufWriteCmd', {
          group = group,
          buffer = buf,
          callback = function()
            M.save_query(true)
          end,
        })
        if _G.BottomPanel then
          _G.BottomPanel.active_mode = 'dbout'
        end

        -- Ensure preview window is never locked by winfixbuf
        local pwin = vim.fn.bufwinid(buf)
        if pwin and pwin ~= -1 and vim.api.nvim_win_is_valid(pwin) then
          if vim.fn.exists '&winfixbuf' == 1 and vim.wo[pwin].winfixbuf then
            vim.wo[pwin].winfixbuf = false
          end
        end

        -- Explicitly register in buffer ring and refresh lualine
        local ok_br, br = pcall(require, 'utils.buffer-ring')
        if ok_br and br.on_buf_enter then
          br.on_buf_enter(buf)
        end
        local ok_lualine, lualine = pcall(require, 'lualine')
        if ok_lualine and lualine.refresh then
          lualine.refresh()
        end

        -- Guarantee right sidebar retains its 35-column width and vertical precedence
        vim.schedule(function()
          local ok_layout, layout = pcall(require, 'utils.layout')
          if ok_layout and layout.RightPanel and layout.RightPanel.ensure_precedence then
            layout.RightPanel.ensure_precedence()
          end
        end)
      end
      return res
    end
  end

  -- Hook drawer.actions.preview (result grid only) to track bottom panel dbout mode and precedence
  if not M._drawer_grid_preview_hooked and drawer.actions.preview then
    M._drawer_grid_preview_hooked = true
    local orig_preview = drawer.actions.preview
    drawer.actions.preview = function(...)
      local res = orig_preview(...)
      if _G.BottomPanel then
        _G.BottomPanel.active_mode = 'dbout'
        if _G.BottomPanel.ensure_precedence then
          _G.BottomPanel.ensure_precedence()
        end
      end
      local ok_lualine, lualine = pcall(require, 'lualine')
      if ok_lualine and lualine.refresh then
        lualine.refresh()
      end
      return res
    end
  end

  -- 2. Hook drawer.actions.use to synchronize connection state on connection switch
  if not M._drawer_use_hooked and drawer.actions.use then
    M._drawer_use_hooked = true
    local orig_use = drawer.actions.use
    drawer.actions.use = function(...)
      local res = orig_use(...)
      local ok_st, state = pcall(require, 'sqmeow.core.state')
      if not ok_st then
        ok_st, state = pcall(require, 'sqmeow.state')
      end
      local conn_id = ok_st and state.current
      local conn = conn_id and state.connections[conn_id]
      if conn then
        local conn_url = M.get_connection_url(conn.name) or conn.url
        M.current_db = conn_url
        M.current_db_name = conn.name
        M.save_active_connection(conn.name, conn_url)

        -- Synchronize connection context on the active editor buffer if present
        local ed_win = _G.RightPanel and _G.RightPanel.get_editor_win and _G.RightPanel.get_editor_win()
        local buf = (ed_win and vim.api.nvim_win_is_valid(ed_win)) and vim.api.nvim_win_get_buf(ed_win) or vim.api.nvim_get_current_buf()
        if buf and vim.api.nvim_buf_is_valid(buf) and (vim.bo[buf].filetype == 'sql' or vim.b[buf].sqmeow_connection) then
          vim.b[buf].db_name = conn.name
          vim.b[buf].sqmeow_connection = conn.name
        end

        local ok_lualine, lualine = pcall(require, 'lualine')
        if ok_lualine and lualine.refresh then
          lualine.refresh()
        end
      end
      return res
    end
  end

  -- 3. Route sqmeow editor actions (<CR>, visual <CR>, <leader>E) through M.run_query
  -- so buffer-local connections are auto-opened and BottomPanel is coordinated
  local ok_ed, editor = pcall(require, 'sqmeow.ui.editor')
  if ok_ed and editor and editor.actions and not M._editor_actions_hooked then
    M._editor_actions_hooked = true
    editor.actions.execute_statement = function()
      M.run_query(false)
    end
    editor.actions.execute_selection = function()
      M.run_query(false)
    end
    editor.actions.execute_buffer = function()
      M.run_query(true)
    end
  end

  -- 4. Render non-grid result messages (e.g. "2 rows affected", "no rows", "running…")
  -- directly inside the result buffer body when `ui.winbar = false`
  local ok_res, result = pcall(require, 'sqmeow.ui.result')
  if ok_res and result and not M._result_non_grid_hooked then
    M._result_non_grid_hooked = true
    local ns = vim.api.nvim_create_namespace 'sqmeow_non_grid_status'

    local function render_non_grid_summary(summary)
      local state = sqmeow 'core.state'
      local call = summary or (state and state.call)
      if not call or call.state == 'error' then
        return
      end
      if call.columns and #call.columns > 0 then
        return
      end
      local handle = result.buffer and result.buffer()
      if not handle or not vim.api.nvim_buf_is_valid(handle) then
        return
      end
      local desc = result.describe and result.describe(call, false) or ''
      if desc == '' then
        return
      end
      local line = '  ' .. desc
      vim.bo[handle].modifiable = true
      vim.api.nvim_buf_set_lines(handle, 0, -1, false, { line })
      vim.api.nvim_buf_clear_namespace(handle, ns, 0, -1)
      local hl = call.state == 'executing' and 'Comment' or 'SqmeowSignAdded'
      pcall(vim.api.nvim_buf_set_extmark, handle, ns, 0, 0, {
        end_col = #line,
        hl_group = hl,
      })
      vim.bo[handle].modifiable = false
    end

    local function refresh_statusline()
      local ok_tt, tt = pcall(require, 'utils.terminal-tracker')
      if ok_tt and tt and tt.invalidate then
        tt.invalidate()
      end
      local ok_lualine, lualine = pcall(require, 'lualine')
      if ok_lualine and lualine and lualine.refresh then
        lualine.refresh { place = { 'statusline' } }
      end
    end

    local orig_render = result.render
    result.render = function(summary)
      local r = orig_render(summary)
      render_non_grid_summary(summary)
      refresh_statusline()
      return r
    end

    local orig_update_winbar = result.update_winbar
    result.update_winbar = function(summary)
      local r = orig_update_winbar(summary)
      render_non_grid_summary(summary)
      refresh_statusline()
      return r
    end
  end

  -- 5. Pre-warm schema & table completion cache on connection / schema load
  local ok_comp, completion = pcall(require, 'sqmeow.completion')
  if ok_comp and completion and not M._completion_warm_hooked then
    M._completion_warm_hooked = true
    local orig_ensure = completion.ensure
    completion.ensure = function(conn_id)
      if orig_ensure then
        orig_ensure(conn_id)
      end
      if not conn_id then
        return
      end
      local dr = sqmeow 'ui.drawer'
      if not dr or not dr.cached_nodes or not dr.load then
        return
      end
      local schemas = dr.cached_nodes(conn_id, {})
      for _, schema in ipairs(schemas or {}) do
        if schema.kind == 'schema' then
          local groups = dr.cached_nodes(conn_id, { schema.name })
          if groups == nil then
            dr.load(conn_id, { schema.name }, true)
          else
            for _, group in ipairs(groups) do
              if group.kind == 'tables' or group.kind == 'views' or group.kind == 'keys' then
                local path = { schema.name, group.key }
                if dr.cached_nodes(conn_id, path) == nil then
                  dr.load(conn_id, path, true)
                end
              end
            end
          end
        end
      end
    end
  end
end

-------------------------------------------------------------------------------
-- Query Result Grid Helpers (Column Navigation)
-------------------------------------------------------------------------------

function M.first_result_column(win)
  local result = sqmeow 'ui.result'
  if result and result.goto_column then
    result.goto_column(1)
  end
end

function M.last_result_column(win)
  local result = sqmeow 'ui.result'
  if result and result.goto_column then
    local state = sqmeow 'core.state'
    local count = (state and state.call and state.call.columns and #state.call.columns) or 99
    result.goto_column(count)
  end
end

-------------------------------------------------------------------------------
-- Interactive Connection Switcher & Management (<leader>bs, <leader>ba, <leader>bd)
-------------------------------------------------------------------------------

M._conn_databases = M._conn_databases or {}

function M.get_url_database(url)
  if not url or url == '' then
    return nil
  end
  local umod = sqmeow 'core.url'
  if umod and umod.split then
    local parts = umod.split(url)
    if parts then
      if parts.dialect == 'sqlite' or parts.dialect == 'duckdb' then
        return vim.fs.basename(parts.path or '')
      elseif parts.database and parts.database ~= '' then
        return parts.database
      end
    end
  end
  return nil
end

function M.fetch_connection_databases(conn_name, conn_url, callback)
  -- 1. Check local in-memory cache
  if M._conn_databases[conn_name] and #M._conn_databases[conn_name] > 0 then
    callback(M._conn_databases[conn_name])
    return
  end

  local api = sqmeow 'api.connection'
  local state = sqmeow 'core.state'
  if not api or not state or not api.databases then
    callback(nil, 'sqmeow core modules not available')
    return
  end

  -- Connect parent if not already connected
  local parent = state.connection_by_name(conn_name)
  local parent_id = parent and parent.id
  if not parent_id or parent.state == 'closed' then
    parent_id = api.connect_named(conn_name)
  end

  if not parent_id then
    callback(nil, 'Failed to connect to ' .. conn_name)
    return
  end

  local function query_databases()
    api.databases(parent_id, function(dbs, err)
      if dbs and #dbs > 0 then
        table.sort(dbs)
        M._conn_databases[conn_name] = dbs
      end
      callback(dbs, err)
    end)
  end

  local conn_now = state.connections[parent_id]
  if conn_now and conn_now.state == 'connected' then
    query_databases()
  else
    local rpc = sqmeow 'rpc.client'
    if rpc and rpc.on then
      local state_unsub
      state_unsub = rpc.on('conn:state', function(payload)
        if payload.id == parent_id and payload.state == 'connected' then
          if state_unsub then
            state_unsub()
          end
          query_databases()
        end
      end)
    else
      query_databases()
    end
  end
end

function M.activate_connection(name, url, callback)
  local ed_win = _G.RightPanel and _G.RightPanel.get_editor_win and _G.RightPanel.get_editor_win()
  local target_buf = (ed_win and vim.api.nvim_win_is_valid(ed_win)) and vim.api.nvim_win_get_buf(ed_win) or vim.api.nvim_get_current_buf()
  M.set_active_connection(name, url, target_buf)

  pcall(function()
    require('sqmeow.ui.editor').update_winbar()
  end)

  vim.notify('Active database: ' .. name, vim.log.levels.INFO, { title = 'Database' })

  if callback then
    callback(url, name)
  end
end

function M.select_connection(callback)
  local connections = M.get_all_connections()
  local items = {}
  local seen = {}

  -- Include top-level active connections from sqmeow state if not already in connections.json
  local state = sqmeow 'core.state'
  if state and state.connections then
    for _, conn in pairs(state.connections) do
      if conn and conn.name and not conn.parent and not seen[conn.name] then
        local url = M.get_connection_url(conn.name) or conn.url
        table.insert(connections, { name = conn.name, url = url })
      end
    end
  end

  for _, entry in ipairs(connections) do
    if not seen[entry.name] then
      seen[entry.name] = true
      local db_in_url = M.get_url_database(entry.url)
      local is_multi = (db_in_url == nil)
      local display_name = entry.name

      if not is_multi then
        display_name = entry.name .. ' / ' .. db_in_url
      end

      local is_current = false
      local active_child = nil

      if not is_multi then
        if M.current_db_name == entry.name or M.current_db_name == (entry.name .. '/' .. db_in_url) then
          is_current = true
        elseif not M.current_db_name and entry.url == M.current_db then
          is_current = true
        end
      else
        if M.current_db_name then
          if M.current_db_name == entry.name then
            is_current = true
          else
            active_child = M.current_db_name:match('^' .. vim.pesc(entry.name) .. '/(.+)$')
            if active_child then
              is_current = true
            end
          end
        end
      end

      local text = (is_current and '● ' or '○ ') .. display_name
      if is_multi and active_child then
        text = text .. ' [' .. active_child .. ']'
      end
      text = text .. '  (' .. entry.url .. ')'

      table.insert(items, {
        text = text,
        name = entry.name,
        url = entry.url,
        is_multi = is_multi,
        action = 'select',
      })
    end
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
    if not choice then
      return
    end

    if choice.action == 'add' then
      M.add_connection(callback)
      return
    end

    if choice.action == 'delete' then
      M.delete_connection()
      return
    end

    if not choice.is_multi then
      M.activate_connection(choice.name, choice.url, callback)
      return
    end

    -- Multi-database connection: fetch databases and open second picker
    M.fetch_connection_databases(choice.name, choice.url, function(dbs, err)
      if not dbs or #dbs == 0 then
        vim.notify('Could not retrieve databases for ' .. choice.name .. (err and (': ' .. err) or ''), vim.log.levels.WARN, { title = 'Database' })
        return
      end

      if #dbs == 1 then
        local child_name = choice.name .. '/' .. dbs[1]
        local child_url = choice.url:gsub('/+$', '') .. '/' .. dbs[1]
        M.activate_connection(child_name, child_url, callback)
        return
      end

      local db_items = {}
      for _, db in ipairs(dbs) do
        local child_name = choice.name .. '/' .. db
        local child_url = choice.url:gsub('/+$', '') .. '/' .. db
        local is_current = (child_name == M.current_db_name or child_url == M.current_db)
        table.insert(db_items, {
          text = (is_current and '● ' or '○ ') .. db,
          name = child_name,
          url = child_url,
          db = db,
        })
      end

      Snacks.picker.select(db_items, {
        prompt = 'Select Database [' .. choice.name .. ']',
        format_item = function(item)
          return item.text
        end,
      }, function(db_choice)
        if not db_choice then
          return
        end
        M.activate_connection(db_choice.name, db_choice.url, callback)
      end)
    end)
  end)
end

function M.add_connection(callback)
  vim.ui.input({
    prompt = 'Connection URL (e.g. postgresql://user:pass@host:5432/db or sqlite:/path/db): ',
  }, function(url)
    if not url or url:match '^%s*$' then
      return
    end
    url = vim.trim(url)

    local default_name = url:match '([^/:]+)$' or 'Remote DB'
    vim.ui.input({
      prompt = 'Connection Name: ',
      default = default_name,
    }, function(name)
      if not name or name:match '^%s*$' then
        return
      end
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
    format_item = function(item)
      return item.text
    end,
  }, function(choice)
    if not choice then
      return
    end

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

    pcall(function()
      local conn_api = sqmeow 'api.connection'
      if conn_api and conn_api.remove then
        conn_api.remove(choice.name)
      end
    end)

    vim.notify('Removed database connection: ' .. choice.name, vim.log.levels.INFO, { title = 'Database' })
  end)
end

-------------------------------------------------------------------------------
-- Query Execution, Scratchpad, and Save Management (<leader>br, <leader>bq, <leader>bw)
-------------------------------------------------------------------------------

function M.open_query_scratchpad()
  local view_api = sqmeow 'api.view'
  if view_api and view_api.scratchpad then
    local default_prefix = M.current_db_name and (M.current_db_name .. '/') or nil
    view_api.scratchpad(nil, default_prefix)
    local cur_buf = vim.api.nvim_get_current_buf()
    if M.current_db_name then
      vim.b[cur_buf].db_name = M.current_db_name
      vim.b[cur_buf].sqmeow_connection = M.current_db_name
    end
    vim.b[cur_buf].neocodeium_enabled = true
    vim.b[cur_buf].neocodeium_allowed_encoding = true
    local ok_lualine, lualine = pcall(require, 'lualine')
    if ok_lualine and lualine.refresh then
      lualine.refresh()
    end
  end
end

function M.run_query(full_buffer)
  local query_api = sqmeow 'api.query'
  if not query_api then
    vim.notify('sqmeow is not available', vim.log.levels.ERROR, { title = 'Database' })
    return
  end

  local cur_buf = vim.api.nvim_get_current_buf()
  local ft = vim.bo[cur_buf].filetype
  if ft == 'sqmeow-drawer' then
    local drawer = sqmeow 'ui.drawer'
    if drawer and drawer.current_node then
      local node = drawer.current_node()
      if node and node.path and #node.path == 3 and (node.path[2] == 'tables' or node.path[2] == 'views') then
        if drawer.actions.preview_editor then
          drawer.actions.preview_editor()
        else
          drawer.actions.preview()
        end
        return
      end
    end
  end

  local db_url, db_name = M.get_active_db(cur_buf)

  if not db_name or db_name == '' then
    if M.current_db_name then
      db_name = M.current_db_name
      db_url = M.current_db
    else
      M.select_connection(function(selected_url, selected_name)
        if selected_name then
          M.run_query(full_buffer)
        end
      end)
      return
    end
  end

  -- Synchronize buffer-local connection bindings and active state
  vim.b[cur_buf].db_name = db_name
  vim.b[cur_buf].sqmeow_connection = db_name
  M.current_db_name = db_name
  M.current_db = db_url or M.get_connection_url(db_name)

  -- Detect active table if not already assigned
  if not vim.b[cur_buf].sqmeow_table then
    local tbl = M.get_active_table(cur_buf)
    if tbl then
      vim.b[cur_buf].sqmeow_table = tbl
    end
  end

  -- Ensure active in sqmeow without duplicating connection
  M.ensure_sqmeow_connection(db_name)
  M.setup_drawer_helpers()
  if _G.BottomPanel and _G.BottomPanel.hide_terminal then
    _G.BottomPanel.hide_terminal()
  end
  if _G.BottomPanel then
    _G.BottomPanel.active_mode = 'dbout'
  end

  local mode = vim.api.nvim_get_mode().mode
  local is_visual = mode:match '[vV\x16]' ~= nil

  if full_buffer then
    query_api.execute_buffer()
  elseif is_visual then
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'x', false)
    query_api.execute_selection()
  else
    query_api.execute_statement()
  end

  if _G.BottomPanel then
    _G.BottomPanel.active_mode = 'dbout'
    if _G.BottomPanel.ensure_precedence then
      _G.BottomPanel.ensure_precedence()
    end
  end

  local ok_lualine, lualine = pcall(require, 'lualine')
  if ok_lualine and lualine.refresh then
    lualine.refresh()
  end
end

function M.save_query(force_prompt)
  local buf = vim.api.nvim_get_current_buf()
  local ft = vim.bo[buf].filetype
  if ft == 'sqmeow-drawer' or ft == 'sqmeow-result' or ft == 'dbui' or ft == 'dbout' then
    return
  end

  local current_name = vim.fs.normalize(vim.api.nvim_buf_get_name(buf))
  local conns = M.get_all_connections()
  local is_existing_saved = false
  local existing_db_name = nil

  if not force_prompt and current_name ~= '' and vim.fn.filereadable(current_name) == 1 then
    if current_name:sub(1, #sqmeow_scratch_dir) == sqmeow_scratch_dir then
      is_existing_saved = true
    end
  end

  if is_existing_saved and vim.bo[buf].buftype == '' then
    local ok, err = pcall(vim.cmd, 'write')
    if ok then
      vim.notify('Saved query updated: ' .. vim.fn.fnamemodify(current_name, ':t'), vim.log.levels.INFO, { title = 'Database' })
      pcall(function()
        require('sqmeow.ui.drawer').render()
      end)
    else
      vim.notify('Error saving query: ' .. tostring(err), vim.log.levels.ERROR, { title = 'Database' })
    end
    return
  end

  local db_url, db_name = M.get_active_db(buf)
  db_name = db_name or M.current_db_name or (conns[1] and conns[1].name)
  if not db_name or db_name == '' or db_name == 'Database' then
    M.select_connection(function(selected_url, selected_name)
      if selected_name then
        M.current_db = selected_url
        M.current_db_name = selected_name
        M.save_query(force_prompt)
      end
    end)
    return
  end

  local default_name = M.get_active_table(buf)
    or (current_name ~= '' and not current_name:find 'scratch' and not current_name:find 'Preview' and not current_name:find 'Alter' and vim.fn.fnamemodify(
      current_name,
      ':t:r'
    ))
    or ('query_' .. os.date '%Y%m%d_%H%M%S')

  vim.ui.input({
    prompt = 'Save Query Name (for ' .. db_name .. '): ',
    default = default_name,
  }, function(input_name)
    if not input_name or input_name:match '^%s*$' then
      return
    end
    input_name = vim.trim(input_name)
    if not input_name:match '%.sql$' then
      input_name = input_name .. '.sql'
    end

    local sqmeow_db_dir = vim.fs.normalize(sqmeow_scratch_dir .. '/' .. db_name)
    if vim.fn.isdirectory(sqmeow_db_dir) == 0 then
      vim.fn.mkdir(sqmeow_db_dir, 'p')
    end

    local scratch_path = vim.fs.normalize(sqmeow_db_dir .. '/' .. input_name)
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

    local write_ok, write_err = pcall(vim.fn.writefile, lines, scratch_path)

    if not write_ok then
      vim.notify('Failed to save query: ' .. tostring(write_err), vim.log.levels.ERROR, { title = 'Database' })
      return
    end

    pcall(function()
      vim.cmd('edit ' .. vim.fn.fnameescape(scratch_path))
      local new_buf = vim.api.nvim_get_current_buf()
      vim.bo[new_buf].filetype = 'sql'
      vim.bo[new_buf].buftype = ''
      vim.b[new_buf].db_name = db_name
      vim.b[new_buf].sqmeow_connection = db_name
      local prev_table = vim.b[buf] and vim.b[buf].sqmeow_table
      if prev_table then
        vim.b[new_buf].sqmeow_table = prev_table
      end
    end)

    pcall(function()
      local ok_dr, drawer = pcall(require, 'sqmeow.ui.drawer')
      if ok_dr and drawer.render then
        drawer.render()
      end
    end)

    vim.notify('Saved query: ' .. input_name .. ' (saved under ' .. db_name .. ')', vim.log.levels.INFO, { title = 'Database' })
  end)
end

function M.select_saved_query()
  local editor = require 'sqmeow.ui.editor'
  local pads = editor.list()
  if editor.project then
    local proj = editor.project()
    if proj and proj.list then
      for _, p in ipairs(proj.list()) do
        table.insert(pads, p)
      end
    end
  end
  if #pads == 0 then
    vim.notify('No saved queries found. Save one with <leader>bw', vim.log.levels.INFO, { title = 'Database' })
    return
  end

  local items = {}
  for _, p in ipairs(pads) do
    local db_name = p.db_name or p.name:match '^([^/]+)/'
    table.insert(items, {
      text = p.name,
      file = p.path,
      db_name = db_name,
    })
  end

  local cur_db = vim.b.sqmeow_connection or vim.b.db_name or M.current_db_name
  table.sort(items, function(a, b)
    if cur_db then
      if a.db_name == cur_db and b.db_name ~= cur_db then
        return true
      end
      if a.db_name ~= cur_db and b.db_name == cur_db then
        return false
      end
    end
    return a.text < b.text
  end)

  Snacks.picker.select(items, {
    prompt = 'Select Saved Query' .. (cur_db and (' [' .. cur_db .. ']') or ''),
    format_item = function(item)
      return '󰈙 ' .. item.text
    end,
  }, function(choice)
    if not choice then
      return
    end
    local buf = editor.open_path(choice.file)
    local target_db = choice.db_name or M.current_db_name
    if target_db then
      vim.b[buf].db_name = target_db
      vim.b[buf].sqmeow_connection = target_db
      M.current_db_name = target_db
      M.current_db = M.get_connection_url(target_db)
      M.ensure_sqmeow_connection(target_db)
    end
    if not vim.b[buf].sqmeow_table then
      local tbl = M.get_active_table(buf)
      if tbl then
        vim.b[buf].sqmeow_table = tbl
      end
    end
    local ok_lualine, lualine = pcall(require, 'lualine')
    if ok_lualine and lualine.refresh then
      lualine.refresh()
    end
  end)
end

vim.api.nvim_create_user_command('SaveQuery', function()
  M.save_query()
end, { desc = 'Save query to database saved queries' })

_G.DatabaseUtils = M

return M
