local M = {}

-- Silence dadbod completion notifications and redraw prompts
vim.g.vim_dadbod_completion_disable_notifications = 1

local sqmeow_dir = vim.fs.normalize(vim.fn.stdpath('data') .. '/sqmeow')
local sqmeow_scratch_dir = vim.fs.normalize(sqmeow_dir .. '/scratch')
local sqmeow_conn_file = sqmeow_dir .. '/connections.json'
local active_file = sqmeow_dir .. '/last_active.json'

-- Active connection state across all buffers (nil until a connection is active)
M.current_db = nil
M.current_db_name = nil

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

function M.get_saved_queries_dir(db_name)
  if not db_name or db_name == '' then
    return sqmeow_scratch_dir
  end
  return vim.fs.normalize(sqmeow_scratch_dir .. '/' .. db_name)
end

-- Get saved queries for a specific database (stored in sqmeow/scratch/<db_name>/)
function M.get_saved_queries_for_db(db_name)
  if not db_name then return {} end
  local files = {}
  local seen = {}
  local dir = M.get_saved_queries_dir(db_name)
  if vim.fn.isdirectory(dir) == 1 then
    local ok, iter = pcall(vim.fs.dir, dir)
    if ok and iter then
      for name, kind in iter do
        if kind == 'file' and name:match('%.sql$') and not seen[name] then
          seen[name] = true
          table.insert(files, {
            name = name,
            path = dir .. '/' .. name,
            db_name = db_name,
          })
        end
      end
    end
  end
  table.sort(files, function(a, b) return a.name < b.name end)
  return files
end

function M.get_connection_url(name)
  if not name or name == '' then return nil end

  -- Check active sqmeow connections first (e.g. child connections like "cluster/testdb")
  local ok_state, state = pcall(require, 'sqmeow.state')
  if ok_state and state and state.connections then
    local conn = state.connection_by_name(name)
    if conn then
      if conn.database and conn.url and not conn.url:match('/' .. conn.database .. '$') then
        local base = conn.url:gsub('/+$', '')
        return base .. '/' .. conn.database
      end
      return conn.url
    end
  end

  if name:find('/') then
    local parent_name, child_db = name:match('^([^/]+)/(.+)$')
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

-- Prune duplicate connections (no-op since upstream branch handles deduplication)
function M.deduplicate_connections()
end

-- Ensure connection is active in sqmeow using upstream connect_named or active child connection
function M.ensure_sqmeow_connection(db_name)
  if not db_name or db_name == '' then
    return nil
  end

  local ok_state, state = pcall(require, 'sqmeow.state')
  local ok_api, api = pcall(require, 'sqmeow.api')
  if not ok_api or not api then
    return nil
  end

  -- If it is already an active open connection (including child connections like "cluster/testdb"), activate it
  if ok_state and state and state.connections then
    local conn = state.connection_by_name(db_name)
    if conn and conn.state ~= 'closed' then
      api.use(conn.id)
      return conn.id
    end
  end

  -- If it's a child connection like "parent/child", ensure parent is open and look for child
  if db_name:find('/') then
    local parent_name, child_db = db_name:match('^([^/]+)/(.+)$')
    if parent_name and child_db then
      local parent_conn = ok_state and state and state.connection_by_name(parent_name)
      if not parent_conn or parent_conn.state == 'closed' then
        pcall(function() api.connect_named(parent_name) end)
      end

      local waited = 0
      while waited < 2000 do
        parent_conn = ok_state and state and state.connection_by_name(parent_name)
        if parent_conn and parent_conn.state == 'connected' then break end
        vim.wait(50, function() return false end)
        waited = waited + 50
      end

      if ok_state and state and parent_conn and parent_conn.state == 'connected' then
        local child = state.child_connection and state.child_connection(parent_conn.id, child_db)
        if child and child.id then
          api.use(child.id)
          return child.id
        else
          local child_id = api.connect(parent_conn.url, {
            name = db_name,
            parent = parent_conn.id,
            database = child_db,
            read_only = parent_conn.read_only,
            ssh = parent_conn.ssh,
          })
          if child_id then
            api.use(child_id)
            return child_id
          end
        end
      end
    end
  end

  local id = nil
  pcall(function()
    id = api.connect_named(db_name)
  end)
  return id
end

-- Set active connection across global state, disk persistence, and all open SQL buffers
function M.set_active_connection(name, url)
  M.current_db = url
  M.current_db_name = name
  M.save_active_connection(name, url)

  -- Update all active SQL buffers for blink.cmp and sqmeow
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) then
      local ft = vim.bo[buf].filetype
      if ft == 'sql' or ft == 'mysql' or ft == 'plsql' then
        vim.b[buf].db = url
        vim.b[buf].db_name = name
        vim.b[buf].sqmeow_connection = name
        pcall(function()
          vim.cmd('call vim_dadbod_completion#fetch(' .. buf .. ')')
        end)
      end
    end
  end

  -- Connect & use connection in sqmeow without duplicating
  M.ensure_sqmeow_connection(name)
end

-- Initialize persistent connections & state
function M.init()
  M.get_all_connections()
  M.load_active_connection()
end

M.init()

-- Resolve the active database for any buffer
function M.get_active_db(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return nil, nil
  end

  -- 1. If buffer already has an assigned sqmeow_connection, respect it
  local ok_sq, sq_conn = pcall(function() return vim.b[buf].sqmeow_connection end)
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
  end

  -- 2. Buffer path belongs to a specific database folder
  local buf_path = vim.fs.normalize(vim.api.nvim_buf_get_name(buf))
  if buf_path ~= '' then
    -- Collect all known connections (both persistent and active in state)
    local candidates = {}
    local seen = {}

    local ok_state, state = pcall(require, 'sqmeow.state')
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

    -- Sort candidates by name length descending so child connections match before parent
    table.sort(candidates, function(a, b) return #a.name > #b.name end)

    for _, c in ipairs(candidates) do
      local pattern = '/' .. c.name:gsub('([^%w])', '%%%1') .. '/'
      local pattern_under = '/' .. c.name:gsub('([^%w])', '%%%1') .. '_'
      if buf_path:find(pattern) or buf_path:find(pattern_under) then
        -- Check if path contains a child database subfolder (e.g. .../scratch/cluster/testdb/...)
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

  -- 3. Buffer already has an assigned database or sqmeow connection
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
  end

  local ok_db, db_val = pcall(function() return vim.b[buf].db end)
  local ok_name, db_name_val = pcall(function() return vim.b[buf].db_name end)
  if ok_db and db_val and db_val ~= '' then
    local name = (ok_name and db_name_val) or M.current_db_name or 'Database'
    return db_val, name
  end

  -- 4. Fallback to active connection
  if M.current_db and M.is_accessible(M.current_db) then
    return M.current_db, M.current_db_name
  end

  return nil, nil
end

-------------------------------------------------------------------------------
-- Spatial Drawer Docking & Right Panel Management
-------------------------------------------------------------------------------

function M.open_drawer()
  local ok, sqmeow_api = pcall(require, 'sqmeow.api')
  if not ok then
    vim.notify('sqmeow.nvim is not loaded yet', vim.log.levels.WARN, { title = 'Database' })
    return
  end

  M.setup_drawer_helpers()

  -- If drawer is already open, toggle it off
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(win) then
      local buf = vim.api.nvim_win_get_buf(win)
      if vim.bo[buf].filetype == 'sqmeow-drawer' then
        sqmeow_api.close_drawer()
        return
      end
    end
  end

  -- Mutually exclusive with other right panels (File Explorer, OpenCode)
  if _G.RightPanel then
    if _G.RightPanel.active_mode == 'explorer' then
      pcall(function() Snacks.picker.pickers.explorer:close() end)
    end
    _G.RightPanel.active_mode = 'dbui'
  end

  sqmeow_api.open_drawer()

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

--- Get the current in-memory preview buffer (provided natively by sqmeow)
function M.preview_buffer()
  local ok, drawer = pcall(require, 'sqmeow.ui.drawer')
  return ok and drawer.preview_buffer() or nil
end

--- Preview the relation under cursor in the in-memory editor buffer
function M.open_preview_buffer(node)
  local ok, drawer = pcall(require, 'sqmeow.ui.drawer')
  if ok and drawer.actions and drawer.actions.preview then
    drawer.actions.preview()
  end
end

function M.setup_drawer_helpers()
  local ok, drawer = pcall(require, 'sqmeow.ui.drawer')
  if not ok or M._drawer_helpers_initialized then return end
  M._drawer_helpers_initialized = true

  -- 1. Hook sqmeow.ui.editor so scratchpads opened from database folders attach connection context
  local ok_ed, editor = pcall(require, 'sqmeow.ui.editor')
  if ok_ed and editor and not M._editor_list_hooked then
    M._editor_list_hooked = true

    local orig_open_path = editor.open_path
    editor.open_path = function(path)
      local buf = orig_open_path(path)
      local db_url, db_name = M.get_active_db(buf)
      if db_name then
        vim.b[buf].sqmeow_connection = db_name
        vim.b[buf].db = db_url
        vim.b[buf].db_name = db_name
        M.ensure_sqmeow_connection(db_name)
      end
      return buf
    end
  end

  -- 2. Hook NuiTree.Node to label the bottom scratchpads section as 'Saved Queries'
  local ok_nui, NuiTree = pcall(require, 'nui.tree')
  if ok_nui and NuiTree and not M._nui_tree_hooked then
    M._nui_tree_hooked = true
    local orig_node = NuiTree.Node
    NuiTree.Node = function(data, children)
      if data and data.id == 'scratchpads' and data.name == 'scratchpads' then
        data.name = 'All Saved Queries'
      end
      return orig_node(data, children)
    end
  end

  -- 3. Hook on_nodes to inject 'Saved queries' directly under each database connection,
  -- and helper queries (* First 1000, * Count (*)) under tables
  local orig_on_nodes = drawer.on_nodes
  drawer.on_nodes = function(payload)
    -- Under connection root: inject Saved queries node for that database
    if (payload.path == nil or #payload.path == 0) and payload.nodes then
      local has_sq = false
      for _, n in ipairs(payload.nodes) do
        if n.key == '__saved_queries' then
          has_sq = true
          break
        end
      end
      if not has_sq then
        local state = require('sqmeow.state')
        local conn = (state.connections and state.connections[payload.conn_id])
        local db_name = conn and conn.name
        local queries = db_name and M.get_saved_queries_for_db(db_name) or {}
        local count = #queries
        table.insert(payload.nodes, 1, {
          name = 'Saved queries',
          key = '__saved_queries',
          kind = 'saved_queries',
          icon_kind = 'scratchpads',
          count = count,
          expandable = true,
        })

        -- If currently expanded, keep cached query nodes fresh
        local ok_exp, is_exp = pcall(drawer.is_expanded, payload.conn_id, { '__saved_queries' })
        if ok_exp and is_exp then
          local _, node_key = debug.getupvalue(drawer.is_expanded, 2)
          local _, cache = debug.getupvalue(drawer.invalidate, 2)
          if node_key and cache then
            local key = node_key(payload.conn_id, { '__saved_queries' })
            local q_nodes = {}
            for _, q in ipairs(queries) do
              table.insert(q_nodes, {
                name = q.name,
                key = q.name,
                kind = 'scratchpad',
                file = q.path,
                expandable = false,
              })
            end
            cache[key] = { nodes = q_nodes }
          end
        end
      end
    end

    return orig_on_nodes(payload)
  end

  -- 4. Hook drawer.actions.toggle for per-db saved queries and child connection activation
  local orig_toggle = drawer.actions.toggle
  drawer.actions.toggle = function()
    local node = drawer.current_node()

    -- Expanding/collapsing 'Saved queries' directly under a database connection
    if node and node.path and #node.path == 1 and node.path[1] == '__saved_queries' then
      local state = require('sqmeow.state')
      local conn = (state.connections and state.connections[node.conn_id]) or (node.name and state.connection_by_name(node.name))
      local db_name = conn and conn.name
      local queries = db_name and M.get_saved_queries_for_db(db_name) or {}
      local q_nodes = {}
      for _, q in ipairs(queries) do
        table.insert(q_nodes, {
          name = q.name,
          key = q.name,
          kind = 'scratchpad',
          file = q.path,
          expandable = false,
        })
      end

      local _, expanded = debug.getupvalue(drawer.is_expanded, 1)
      local _, node_key = debug.getupvalue(drawer.is_expanded, 2)
      local _, cache = debug.getupvalue(drawer.invalidate, 2)

      if expanded and node_key then
        local key = node_key(node.conn_id, node.path)
        if expanded[key] then
          expanded[key] = nil
        else
          expanded[key] = true
          if cache then
            cache[key] = {
              nodes = q_nodes,
            }
          end
        end
        drawer.render()
      end
      return
    end

    -- Opening a saved query directly under a database connection
    if node and node.path and #node.path == 2 and node.path[1] == '__saved_queries' then
      local state = require('sqmeow.state')
      local conn = (state.connections and state.connections[node.conn_id]) or (node.name and state.connection_by_name(node.name))
      local db_name = conn and conn.name
      local file_path = node.file
      if not file_path and db_name then
        local dir = M.get_saved_queries_dir(db_name)
        local candidate = dir .. '/' .. node.path[2]
        if vim.uv.fs_stat(candidate) then
          file_path = candidate
        else
          local queries = M.get_saved_queries_for_db(db_name)
          for _, q in ipairs(queries) do
            if q.name == node.path[2] then
              file_path = q.path
              break
            end
          end
        end
      end
      if file_path then
        local buf = require('sqmeow.ui.editor').open_path(file_path)
        if db_name then
          local db_url = M.get_connection_url(db_name)
          vim.b[buf].sqmeow_connection = db_name
          vim.b[buf].db = db_url
          vim.b[buf].db_name = db_name
          M.ensure_sqmeow_connection(db_name)
        end
        return
      end
    end

    return orig_toggle()
  end

  -- 5. Hook drawer.actions.preview to attach save-query on :w and track bottom panel dbout mode
  local orig_preview = drawer.actions.preview
  drawer.actions.preview = function(...)
    local res = orig_preview(...)
    local buf = drawer.preview_buffer()
    if buf and vim.api.nvim_buf_is_valid(buf) then
      vim.bo[buf].buflisted = true
      vim.b[buf].is_preview_buffer = true
      if M.current_db then
        vim.b[buf].db = M.current_db
        vim.b[buf].db_name = M.current_db_name
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
    end
    return res
  end

  -- 6. Hook drawer.actions.use to synchronize Dadbod / completion state on connection switch
  local orig_use = drawer.actions.use
  drawer.actions.use = function(...)
    local res = orig_use(...)
    local ok_st, state = pcall(require, 'sqmeow.state')
    local conn_id = ok_st and state.current
    local conn = conn_id and state.connections[conn_id]
    if conn then
      local conn_url = M.get_connection_url(conn.name) or conn.url
      M.current_db = conn_url
      M.current_db_name = conn.name
      M.save_active_connection(conn.name, conn_url)

      -- Synchronize dadbod context on the active editor buffer if present
      local ed_win = _G.RightPanel and _G.RightPanel.get_editor_win and _G.RightPanel.get_editor_win()
      local buf = (ed_win and vim.api.nvim_win_is_valid(ed_win)) and vim.api.nvim_win_get_buf(ed_win) or vim.api.nvim_get_current_buf()
      if buf and vim.api.nvim_buf_is_valid(buf) and (vim.bo[buf].filetype == 'sql' or vim.b[buf].sqmeow_connection) then
        vim.b[buf].db = conn_url
        vim.b[buf].db_name = conn.name
        pcall(vim.cmd, 'call vim_dadbod_completion#fetch(' .. buf .. ')')
      end
    end
    return res
  end
end

-------------------------------------------------------------------------------
-- Query Result Grid Helpers (Column Navigation & Sticky Headers)
-------------------------------------------------------------------------------

function M.get_result_tbl()
  local ok, result = pcall(require, 'sqmeow.ui.result')
  if not ok then return nil end
  local i = 1
  while true do
    local name, val = debug.getupvalue(result.goto_column, i)
    if not name then break end
    if name == 'tbl' then return val end
    i = i + 1
  end
  return nil
end

function M.next_result_column()
  local ok, result = pcall(require, 'sqmeow.ui.result')
  if ok and result.actions and result.actions.next_column then
    result.actions.next_column()
  end
end

function M.prev_result_column()
  local ok, result = pcall(require, 'sqmeow.ui.result')
  if ok and result.actions and result.actions.prev_column then
    result.actions.prev_column()
  end
end

function M.first_result_column(win)
  win = win or vim.api.nvim_get_current_win()
  local tbl = M.get_result_tbl()
  if tbl and tbl._ and tbl._.columns and #tbl._.columns > 0 then
    tbl:goto_column(1, win)
  end
end

function M.last_result_column(win)
  win = win or vim.api.nvim_get_current_win()
  local tbl = M.get_result_tbl()
  if tbl and tbl._ and tbl._.columns and #tbl._.columns > 0 then
    tbl:goto_column(#tbl._.columns, win)
  end
end

-------------------------------------------------------------------------------
-- Interactive Connection Switcher & Management (<leader>bs, <leader>ba, <leader>bd)
-------------------------------------------------------------------------------

M._conn_databases = M._conn_databases or {}

function M.get_url_database(url)
  if not url or url == '' then return nil end
  local ok_u, umod = pcall(require, 'sqmeow.url')
  if ok_u and umod and umod.split then
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

  local ok_api, api = pcall(require, 'sqmeow.api')
  local ok_state, state = pcall(require, 'sqmeow.state')
  if not ok_api or not ok_state or not api.databases then
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
    local ok_rpc, rpc = pcall(require, 'sqmeow.rpc')
    if ok_rpc and rpc then
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
  M.set_active_connection(name, url)
  local cur_buf = vim.api.nvim_get_current_buf()
  vim.b[cur_buf].db = url
  vim.b[cur_buf].db_name = name
  vim.b[cur_buf].sqmeow_connection = name
  pcall(function()
    require('sqmeow.ui.editor').update_winbar()
    vim.cmd('call vim_dadbod_completion#fetch(' .. cur_buf .. ')')
  end)

  -- Sync connection in sqmeow natively (supports clusters and single-db via PR #57)
  pcall(function()
    vim.cmd('Sqmeow use ' .. vim.fn.fnameescape(name))
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
  local ok_st, state = pcall(require, 'sqmeow.state')
  if ok_st and state and state.connections then
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
    if not choice then return end

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
        vim.notify(
          'Could not retrieve databases for ' .. choice.name .. (err and (': ' .. err) or ''),
          vim.log.levels.WARN,
          { title = 'Database' }
        )
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
        if not db_choice then return end
        M.activate_connection(db_choice.name, db_choice.url, callback)
      end)
    end)
  end)
end

function M.add_connection(callback)
  vim.ui.input({
    prompt = 'Connection URL (e.g. postgresql://user:pass@host:5432/db or sqlite:/path/db): ',
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

    pcall(function()
      require('sqmeow.api').remove(choice.name)
    end)

    vim.notify('Removed database connection: ' .. choice.name, vim.log.levels.INFO, { title = 'Database' })
  end)
end

-------------------------------------------------------------------------------
-- Query Execution, Scratchpad, and Save Management (<leader>br, <leader>bq, <leader>bw)
-------------------------------------------------------------------------------

function M.open_query_scratchpad()
  local ok, sqmeow_api = pcall(require, 'sqmeow.api')
  if ok then
    local default_prefix = M.current_db_name and (M.current_db_name .. '/') or nil
    sqmeow_api.scratchpad(nil, default_prefix)
    local cur_buf = vim.api.nvim_get_current_buf()
    if M.current_db then
      vim.b[cur_buf].db = M.current_db
      vim.b[cur_buf].db_name = M.current_db_name
      vim.b[cur_buf].sqmeow_connection = M.current_db_name
    end
    vim.b[cur_buf].neocodeium_enabled = true
    vim.b[cur_buf].neocodeium_allowed_encoding = true
  end
end

function M.run_query()
  local ok, sqmeow_api = pcall(require, 'sqmeow.api')
  if not ok then
    vim.notify('sqmeow is not available', vim.log.levels.ERROR, { title = 'Database' })
    return
  end

  local cur_buf = vim.api.nvim_get_current_buf()
  local ft = vim.bo[cur_buf].filetype
  if ft == 'sqmeow-drawer' then
    local ok_dr, drawer = pcall(require, 'sqmeow.ui.drawer')
    if ok_dr and drawer.current_node then
      local node = drawer.current_node()
      if node and node.path and #node.path == 3 and (node.path[2] == 'tables' or node.path[2] == 'views') then
        drawer.actions.preview()
        return
      end
    end
  end

  local db_url, db_name = M.get_active_db(cur_buf)

  if not db_name or db_name == '' then
    if M.current_db_name then
      db_name = M.current_db_name
      db_url = M.current_db
      vim.b[cur_buf].db = db_url
      vim.b[cur_buf].db_name = db_name
      vim.b[cur_buf].sqmeow_connection = db_name
    else
      M.select_connection(function(selected_url, selected_name)
        if selected_name then
          M.run_query()
        end
      end)
      return
    end
  end

  -- Ensure active in sqmeow without duplicating connection
  M.ensure_sqmeow_connection(db_name)

  local mode = vim.api.nvim_get_mode().mode
  local is_visual = mode:match('[vV\x16]') ~= nil

  if is_visual then
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'x', false)
    sqmeow_api.execute_selection()
  else
    sqmeow_api.execute_statement()
  end

  if _G.BottomPanel then
    _G.BottomPanel.active_mode = 'dbout'
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
    local cur_dir = vim.fs.normalize(vim.fn.fnamemodify(current_name, ':h'))
    for _, c in ipairs(conns) do
      local expected_sq = vim.fs.normalize(sqmeow_scratch_dir .. '/' .. c.name)
      if cur_dir == expected_sq then
        is_existing_saved = true
        existing_db_name = c.name
        break
      end
    end
  end

  if is_existing_saved and vim.bo[buf].buftype == '' then
    local ok, err = pcall(vim.cmd, 'write')
    if ok then
      vim.notify('Saved query updated: ' .. vim.fn.fnamemodify(current_name, ':t'), vim.log.levels.INFO, { title = 'Database' })
      pcall(function() require('sqmeow.ui.drawer').render() end)
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

  local default_name = (vim.b[buf].sqmeow_table and vim.b[buf].sqmeow_table)
    or (current_name ~= '' and not current_name:find('scratch') and not current_name:find('Preview') and vim.fn.fnamemodify(current_name, ':t:r'))
    or ('query_' .. os.date('%Y%m%d_%H%M%S'))

  vim.ui.input({
    prompt = 'Save Query Name (for ' .. db_name .. '): ',
    default = default_name,
  }, function(input_name)
    if not input_name or input_name:match('^%s*$') then return end
    input_name = vim.trim(input_name)
    if not input_name:match('%.sql$') then
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

    if M._preview_buf == buf then
      M._preview_buf = nil
    end

    pcall(function()
      vim.cmd('edit ' .. vim.fn.fnameescape(scratch_path))
      local new_buf = vim.api.nvim_get_current_buf()
      vim.bo[new_buf].filetype = 'sql'
      vim.bo[new_buf].buftype = ''
      vim.b[new_buf].db = db_url or M.current_db
      vim.b[new_buf].db_name = db_name
      vim.b[new_buf].sqmeow_connection = db_name
      local prev_table = vim.b[buf] and vim.b[buf].sqmeow_table
      if prev_table then
        vim.b[new_buf].sqmeow_table = prev_table
      end
    end)

    pcall(function()
      local ok_dr, drawer = pcall(require, 'sqmeow.ui.drawer')
      if ok_dr then
        local ok_st, state = pcall(require, 'sqmeow.state')
        if ok_st and state.connections then
          local conn = state.connection_by_name(db_name)
          if conn then
            local _, node_key = debug.getupvalue(drawer.is_expanded, 2)
            local _, cache = debug.getupvalue(drawer.invalidate, 2)
            if node_key and cache then
              local key = node_key(conn.id, { '__saved_queries' })
              local queries = M.get_saved_queries_for_db(db_name)
              local q_nodes = {}
              for _, q in ipairs(queries) do
                table.insert(q_nodes, {
                  name = q.name,
                  key = q.name,
                  kind = 'scratchpad',
                  file = q.path,
                  expandable = false,
                })
              end
              cache[key] = { nodes = q_nodes }
            end
          end
        end
        drawer.render()
      end
    end)

    vim.notify('Saved query: ' .. input_name .. ' (saved under ' .. db_name .. ')', vim.log.levels.INFO, { title = 'Database' })
  end)
end

function M.select_saved_query()
  local editor = require('sqmeow.ui.editor')
  local pads = editor.list()
  if #pads == 0 then
    vim.notify('No saved queries found. Save one with <leader>bw', vim.log.levels.INFO, { title = 'Database' })
    return
  end

  local items = {}
  for _, p in ipairs(pads) do
    local db_name = p.db_name or p.name:match('^([^/]+)/')
    table.insert(items, {
      text = p.name,
      file = p.path,
      db_name = db_name,
    })
  end

  local cur_db = vim.b.sqmeow_connection or vim.b.db_name or M.current_db_name
  table.sort(items, function(a, b)
    if cur_db then
      if a.db_name == cur_db and b.db_name ~= cur_db then return true end
      if a.db_name ~= cur_db and b.db_name == cur_db then return false end
    end
    return a.text < b.text
  end)

  Snacks.picker.select(items, {
    prompt = 'Select Saved Query' .. (cur_db and (' [' .. cur_db .. ']') or ''),
    format_item = function(item) return '󰈙 ' .. item.text end,
  }, function(choice)
    if not choice then return end
    local buf = editor.open_path(choice.file)
    local target_db = choice.db_name or M.current_db_name
    if target_db then
      local db_url = M.get_connection_url(target_db) or M.current_db
      vim.b[buf].db = db_url
      vim.b[buf].db_name = target_db
      vim.b[buf].sqmeow_connection = target_db
      M.ensure_sqmeow_connection(target_db)
    end
  end)
end

vim.api.nvim_create_user_command('SaveQuery', function() M.save_query() end, { desc = 'Save query to database saved queries' })
vim.api.nvim_create_user_command('DBDeduplicate', function()
  M.deduplicate_connections()
  vim.notify('Deduplicated sqmeow connections', vim.log.levels.INFO, { title = 'Database' })
end, { desc = 'Clean up duplicate connections in sqmeow drawer' })

_G.DatabaseUtils = M

return {
  -- Core Database Engine (Dadbod) - provides connection & execution fallback
  {
    'tpope/vim-dadbod',
    cmd = { 'DB' },
    ft = { 'sql', 'mysql', 'plsql' },
  },

  -- Database Completion for Blink.cmp (Fast, buffer-local column & table autocomplete)
  {
    'kristijanhusak/vim-dadbod-completion',
    dependencies = { 'tpope/vim-dadbod' },
    ft = { 'sql', 'mysql', 'plsql' },
  },

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
        pattern = { 'dbui', 'dbout', 'sqmeow-drawer', 'sqmeow-result' },
        callback = function(args)
          vim.opt_local.spell = false
          for _, win in ipairs(vim.fn.win_findbuf(args.buf)) do
            vim.wo[win].spell = false
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

          local db_url, db_name = M.get_active_db(buf)
          vim.opt_local.spell = false
          if db_url and M.is_accessible(db_url) then
            pcall(function()
              vim.b[buf].db = db_url
              vim.b[buf].db_name = db_name
              vim.b[buf].sqmeow_connection = db_name
            end)
            vim.schedule(function()
              pcall(function()
                require('lazy').load({ plugins = { 'vim-dadbod-completion' } })
                vim.cmd('call vim_dadbod_completion#fetch(' .. buf .. ')')
              end)
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
          M.setup_drawer_helpers()
          vim.opt_local.spell = false
          local win = vim.fn.bufwinid(args.buf)
          if win > 0 then
            vim.wo[win].spell = false
          end

          vim.schedule(function()
            if vim.api.nvim_buf_is_valid(args.buf) then
              local w = vim.fn.bufwinid(args.buf)
              if w > 0 then
                vim.wo[w].spell = false
                vim.api.nvim_set_current_win(w)
              end
            end
          end)
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
              _G.RightPanel.close()
            else
              require('sqmeow.api').close_drawer()
            end
          end, { buffer = args.buf, silent = true, desc = 'Close Database Drawer' })
        end,
      })

      -- Result window coordination: keymaps, navigation, sticky headers & winbar
      vim.api.nvim_create_autocmd({ 'FileType', 'BufWinEnter' }, {
        pattern = 'sqmeow-result',
        callback = function(args)
          vim.opt_local.spell = false
          local win = vim.fn.bufwinid(args.buf)
          if win > 0 then
            vim.wo[win].spell = false
          end
          vim.bo[args.buf].buflisted = false
          if _G.BottomPanel then
            _G.BottomPanel.last_dbout_buf = args.buf
            _G.BottomPanel.active_mode = 'dbout'
          end

          -- First/Last column navigation (next/prev column are now built-in upstream on <Tab>/<S-Tab> and ]c/[c)
          vim.keymap.set('n', 'g0', function() M.first_result_column() end, { buffer = args.buf, silent = true, desc = 'First Column' })
          vim.keymap.set('n', 'g$', function() M.last_result_column() end, { buffer = args.buf, silent = true, desc = 'Last Column' })

          vim.keymap.set('n', 'q', function()
            require('sqmeow.api').close()
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
      M.setup_drawer_helpers()
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
            M.open_drawer()
          end
        end,
        desc = 'Database Explorer',
      },
      {
        '<leader>bs',
        function()
          M.select_connection()
        end,
        desc = 'Switch / Bind Database',
      },
      {
        '<leader>bw',
        function()
          M.save_query()
        end,
        desc = 'Save Query',
      },
      {
        '<leader>bl',
        function()
          M.select_saved_query()
        end,
        desc = 'Select Saved Query',
      },
      {
        '<leader>br',
        function()
          M.run_query()
        end,
        desc = 'Run Query (Statement / Visual)',
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
          else
            require('sqmeow.api').open()
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
      {
        '<leader>bf',
        function()
          require('sqmeow.api').toggle_float()
        end,
        desc = 'Toggle Float Result',
      },
      {
        '<leader>bv',
        function()
          require('sqmeow.api').review()
        end,
        desc = 'Review & Apply In-Grid Edits',
      },
      {
        '<leader>bx',
        function()
          vim.ui.input({ prompt = 'Export Format (csv, json, sql): ', default = 'csv' }, function(fmt)
            if not fmt or fmt == '' then return end
            require('sqmeow.api').export({ format = vim.trim(fmt), clipboard = true })
          end)
        end,
        desc = 'Export Results',
      },
    },
  },
}
