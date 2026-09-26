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

-- Ensure connection is active in sqmeow using upstream connect_named
function M.ensure_sqmeow_connection(db_name)
  if not db_name or db_name == '' then
    return nil
  end

  local ok_api, api = pcall(require, 'sqmeow.api')
  if not ok_api or not api then
    return nil
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

  -- 1. Buffer path belongs to a specific database folder
  local buf_path = vim.fs.normalize(vim.api.nvim_buf_get_name(buf))
  if buf_path ~= '' then
    local conns = M.get_all_connections()
    for _, c in ipairs(conns) do
      if buf_path:find('/' .. c.name .. '/') or buf_path:find('/' .. c.name .. '_') then
        return c.url, c.name
      end
    end
  end

  -- 2. Buffer already has an assigned database
  local ok_db, db_val = pcall(function() return vim.b[buf].db end)
  local ok_name, db_name_val = pcall(function() return vim.b[buf].db_name end)
  if ok_db and db_val and db_val ~= '' then
    local name = (ok_name and db_name_val) or M.current_db_name or 'Database'
    return db_val, name
  end

  -- 2. Buffer bound via sqmeow_connection
  local ok_sq, sq_conn = pcall(function() return vim.b[buf].sqmeow_connection end)
  if ok_sq and sq_conn and sq_conn ~= '' then
    local conns = M.get_all_connections()
    for _, c in ipairs(conns) do
      if c.name == sq_conn then
        return c.url, c.name
      end
    end
  end

  -- 3. Fallback to active connection
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

  -- Position strictly on the right side at 35 columns and keep drawer focused
  vim.schedule(function()
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_is_valid(win) then
        local buf = vim.api.nvim_win_get_buf(win)
        if vim.bo[buf].filetype == 'sqmeow-drawer' then
          vim.wo[win].spell = false
          vim.api.nvim_set_current_win(win)
          vim.cmd('wincmd L')
          vim.cmd('vertical resize 35')
          break
        end
      end
    end
  end)
end

function M.execute_default_query(conn_id, schema, rel, query_type)
  local sql_mod = require('sqmeow.sql')
  local st = require('sqmeow.state').connections[conn_id]
  local dialect = st and st.dialect
  local parts = { schema, rel }
  local query = ''

  if query_type == 'first_1000' then
    query = sql_mod.select_from(dialect, parts, 1000) .. ';'
  elseif query_type == 'count' then
    query = ('select count(*) as count from %s;'):format(sql_mod.qualify(dialect, parts))
  else
    query = query_type
  end

  local conn_name = st and st.name or M.current_db_name
  local pad_dir = vim.fs.normalize(sqmeow_scratch_dir .. '/' .. (conn_name or 'default'))
  vim.fn.mkdir(pad_dir, 'p')
  local pad_path = pad_dir .. '/' .. rel .. '.sql'

  -- Ensure scratchpad file exists with the query content
  vim.fn.writefile({ query }, pad_path)

  -- Open the scratchpad in the main editor window
  local editor = require('sqmeow.ui.editor')
  local buf = editor.open_path(pad_path)

  -- Set active connection context on the buffer for blink.cmp autocompletion
  local conn_url = (st and st.url) or M.current_db
  if not conn_url and conn_name then
    for _, c in ipairs(M.get_all_connections()) do
      if c.name == conn_name then
        conn_url = c.url
        break
      end
    end
  end

  if conn_url then
    vim.b[buf].db = conn_url
    vim.b[buf].db_name = conn_name
    vim.b[buf].sqmeow_connection = conn_name
    vim.b[buf].sqmeow_table = rel
    M.current_db = conn_url
    M.current_db_name = conn_name
  end
  vim.bo[buf].filetype = 'sql'
  vim.opt_local.spell = false

  -- Execute the query so the results grid opens in the bottom panel
  local api = require('sqmeow.api')
  api.use(conn_id)
  api.execute(query)

  -- Ensure bottom panel tracks dbout mode
  if _G.BottomPanel then
    _G.BottomPanel.active_mode = 'dbout'
  end

  -- Position cursor in the editor buffer on the query so user can modify/save
  local ed_win = vim.fn.bufwinid(buf)
  if ed_win > 0 and vim.api.nvim_win_is_valid(ed_win) then
    vim.api.nvim_set_current_win(ed_win)
    vim.api.nvim_win_set_cursor(ed_win, { 1, #query })
  end

  -- Redraw drawer so scratchpads list reflects the new scratchpad
  local ok_dr, drawer = pcall(require, 'sqmeow.ui.drawer')
  if ok_dr and drawer.render then
    drawer.render()
  end
end

function M.setup_drawer_helpers()
  local ok, drawer = pcall(require, 'sqmeow.ui.drawer')
  if not ok or M._drawer_helpers_initialized then return end
  M._drawer_helpers_initialized = true

  -- 1. Hook sqmeow.ui.editor so scratchpad list and open are database-scoped
  local ok_ed, editor = pcall(require, 'sqmeow.ui.editor')
  if ok_ed and editor and not M._editor_list_hooked then
    M._editor_list_hooked = true

    editor.list = function()
      local pads = {}
      local seen = {}
      local base_dir = require('sqmeow.paths').scratch()

      local function add_pad(display_name, file_path, db_name)
        if seen[file_path] then return end
        seen[file_path] = true
        local stat = vim.uv.fs_stat(file_path)
        table.insert(pads, {
          name = display_name,
          path = file_path,
          db_name = db_name,
          modified = stat and stat.mtime.sec or 0,
        })
      end

      -- Scan per-database folders
      local conns = M.get_all_connections()
      for _, c in ipairs(conns) do
        local q_list = M.get_saved_queries_for_db(c.name)
        for _, q in ipairs(q_list) do
          add_pad(c.name .. ' / ' .. q.name, q.path, c.name)
        end
      end

      -- Scan top-level scratch directory (ad-hoc scratchpads)
      local ok_base, base_iter = pcall(vim.fs.dir, base_dir)
      if ok_base and base_iter then
        for file, kind in base_iter do
          if kind == 'file' and file:match('%.sql$') then
            add_pad(file, vim.fs.normalize(base_dir .. '/' .. file), nil)
          end
        end
      end

      table.sort(pads, function(a, b)
        if a.db_name and not b.db_name then return true end
        if not a.db_name and b.db_name then return false end
        return a.name < b.name
      end)
      return pads
    end

    local orig_open_path = editor.open_path
    editor.open_path = function(path)
      local buf = orig_open_path(path)
      local norm_path = vim.fs.normalize(path)
      local conns = M.get_all_connections()
      for _, c in ipairs(conns) do
        if norm_path:find('/' .. c.name .. '/') or norm_path:find('/' .. c.name .. '_') then
          vim.b[buf].sqmeow_connection = c.name
          vim.b[buf].db = c.url
          vim.b[buf].db_name = c.name
          M.ensure_sqmeow_connection(c.name)
          break
        end
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

    -- Under tables/views: inject * First 1000 and * Count (*)
    if payload.path and #payload.path == 3 and (payload.path[2] == 'tables' or payload.path[2] == 'views') and payload.nodes then
      local has_helpers = false
      for _, n in ipairs(payload.nodes) do
        if n.key == '__first_1000' then
          has_helpers = true
          break
        end
      end
      if not has_helpers then
        table.insert(payload.nodes, 1, {
          name = '* First 1000',
          key = '__first_1000',
          kind = 'query',
          expandable = false,
        })
        table.insert(payload.nodes, 2, {
          name = '* Count (*)',
          key = '__count',
          kind = 'query',
          expandable = false,
        })
      end
    end
    return orig_on_nodes(payload)
  end

  -- 4. Hook drawer.actions.toggle for per-db saved queries and helper queries
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

    -- Helper queries (* First 1000, * Count (*))
    if node and node.path and #node.path == 4 and (node.path[2] == 'tables' or node.path[2] == 'views') then
      local key = node.path[4]
      local schema = node.path[1]
      local rel = node.path[3]

      if key == '__first_1000' then
        M.execute_default_query(node.conn_id, schema, rel, 'first_1000')
        return
      elseif key == '__count' then
        M.execute_default_query(node.conn_id, schema, rel, 'count')
        return
      end
    end
    return orig_toggle()
  end

  -- 5. Hook drawer.actions.preview for quick 'First 1000' (opens scratchpad in editor & executes)
  local orig_preview = drawer.actions.preview
  drawer.actions.preview = function()
    local node = drawer.current_node()
    if node and node.path and #node.path == 3 and (node.path[2] == 'tables' or node.path[2] == 'views') then
      local schema = node.path[1]
      local rel = node.path[3]
      M.execute_default_query(node.conn_id, schema, rel, 'first_1000')
      return
    end
    return orig_preview()
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

function M.next_result_column(win)
  win = win or vim.api.nvim_get_current_win()
  local tbl = M.get_result_tbl()
  if not tbl then return end
  local cell = tbl:goto_cell({ 0, 1 }, win)
  if not cell and tbl._ and tbl._.columns and #tbl._.columns > 0 then
    tbl:goto_column(1, win)
  end
end

function M.prev_result_column(win)
  win = win or vim.api.nvim_get_current_win()
  local tbl = M.get_result_tbl()
  if not tbl then return end
  local cell = tbl:goto_cell({ 0, -1 }, win)
  if not cell and tbl._ and tbl._.columns and #tbl._.columns > 0 then
    tbl:goto_column(#tbl._.columns, win)
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

local sticky_buf = nil
local sticky_win = nil

function M.close_sticky_header()
  if sticky_win and vim.api.nvim_win_is_valid(sticky_win) then
    pcall(vim.api.nvim_win_close, sticky_win, true)
  end
  sticky_win = nil
  if sticky_buf and vim.api.nvim_buf_is_valid(sticky_buf) then
    pcall(vim.api.nvim_buf_delete, sticky_buf, { force = true })
  end
  sticky_buf = nil
end

function M.update_sticky_header(win)
  if not win or not vim.api.nvim_win_is_valid(win) then
    M.close_sticky_header()
    return
  end
  local buf = vim.api.nvim_win_get_buf(win)
  if not buf or not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].filetype ~= 'sqmeow-result' then
    M.close_sticky_header()
    return
  end

  local line_count = vim.api.nvim_buf_line_count(buf)
  if line_count < 3 then
    if sticky_win and vim.api.nvim_win_is_valid(sticky_win) then
      pcall(vim.api.nvim_win_close, sticky_win, true)
      sticky_win = nil
    end
    return
  end

  local w0 = vim.fn.line('w0', win)
  if w0 > 2 then
    if not sticky_buf or not vim.api.nvim_buf_is_valid(sticky_buf) then
      sticky_buf = vim.api.nvim_create_buf(false, true)
      vim.bo[sticky_buf].buftype = 'nofile'
      vim.bo[sticky_buf].bufhidden = 'hide'
      vim.bo[sticky_buf].swapfile = false
    end

    local header_lines = vim.api.nvim_buf_get_lines(buf, 0, 2, false)
    if #header_lines == 2 then
      vim.bo[sticky_buf].modifiable = true
      vim.api.nvim_buf_set_lines(sticky_buf, 0, -1, false, header_lines)
      vim.bo[sticky_buf].modifiable = false

      -- Transfer extmarks / highlights from original header rows
      local ns = vim.api.nvim_create_namespace('sqmeow')
      local hns = vim.api.nvim_create_namespace('sqmeow_sticky')
      vim.api.nvim_buf_clear_namespace(sticky_buf, hns, 0, -1)
      local marks = vim.api.nvim_buf_get_extmarks(buf, ns, { 0, 0 }, { 1, -1 }, { details = true })
      for _, m in ipairs(marks) do
        local row, col, details = m[2], m[3], m[4]
        if details and details.hl_group then
          pcall(vim.api.nvim_buf_set_extmark, sticky_buf, hns, row, col, {
            end_col = details.end_col,
            hl_group = details.hl_group,
            priority = details.priority,
          })
        end
      end

      local win_w = vim.api.nvim_win_get_width(win)
      local view = vim.api.nvim_win_call(win, vim.fn.winsaveview)

      if not sticky_win or not vim.api.nvim_win_is_valid(sticky_win) then
        sticky_win = vim.api.nvim_open_win(sticky_buf, false, {
          relative = 'win',
          win = win,
          row = 0,
          col = 0,
          width = win_w,
          height = 2,
          focusable = false,
          style = 'minimal',
          zindex = 45,
        })
        if sticky_win and vim.api.nvim_win_is_valid(sticky_win) then
          vim.wo[sticky_win].wrap = false
          vim.wo[sticky_win].spell = false
        end
      else
        vim.api.nvim_win_set_config(sticky_win, {
          width = win_w,
          height = 2,
        })
      end

      if sticky_win and vim.api.nvim_win_is_valid(sticky_win) then
        vim.api.nvim_win_call(sticky_win, function()
          vim.fn.winrestview({ leftcol = view.leftcol, topline = 1 })
        end)
      end
    end
  else
    if sticky_win and vim.api.nvim_win_is_valid(sticky_win) then
      pcall(vim.api.nvim_win_close, sticky_win, true)
      sticky_win = nil
    end
  end
end

function M.update_result_winbar(win)
  if not win or not vim.api.nvim_win_is_valid(win) then return end
  local ok, result = pcall(require, 'sqmeow.ui.result')
  if not ok then return end

  local ok_st, state = pcall(require, 'sqmeow.state')
  local call = ok_st and state.call
  if not call then return end

  local cell = result.current_cell and result.current_cell()
  local col_info = ''
  if cell and cell.name and cell.name ~= '' then
    local total_cols = call.columns and #call.columns or 0
    local col_type = call.columns and call.columns[cell.column + 1] and call.columns[cell.column + 1].type_name or ''
    col_info = ('  %%#SqmeowSignAdded#󰠵 %s%%*'):format(cell.name)
    if col_type ~= '' then
      col_info = col_info .. (' %%#SqmeowNull#(%s)%%*'):format(col_type)
    end
    if total_cols > 0 then
      col_info = col_info .. (' %%#SqmeowNull#[%d/%d]%%*'):format(cell.column + 1, total_cols)
    end
  end

  local label = call.connection or (state.current_connection() and state.current_connection().name) or 'database'
  local desc = result.describe and result.describe(call, true) or ''
  vim.wo[win].winbar = ('%%#SqmeowWinbar# %s  %%*%s%s'):format(label, desc, col_info)
end

-------------------------------------------------------------------------------
-- Interactive Connection Switcher & Management (<leader>bs, <leader>ba, <leader>bd)
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
    vim.b[cur_buf].sqmeow_connection = choice.name

    vim.notify('Active database: ' .. choice.name, vim.log.levels.INFO, { title = 'Database' })

    if callback then
      callback(choice.url, choice.name)
    end
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
    sqmeow_api.scratchpad()
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
      if node then
        if node.path and #node.path == 4 and (node.path[4] == '__first_1000' or node.path[4] == '__count') then
          drawer.actions.toggle()
          return
        elseif node.path and #node.path == 3 and (node.path[2] == 'tables' or node.path[2] == 'views') then
          drawer.actions.preview()
          return
        end
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

  local default_name = (current_name ~= '' and not current_name:find('scratch') and vim.fn.fnamemodify(current_name, ':t:r'))
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
    table.insert(items, {
      text = p.name,
      file = p.path,
      db_name = p.db_name,
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
                vim.cmd('wincmd L')
                vim.cmd('vertical resize 35')
              end
            end
          end)
          vim.keymap.set('n', '<Tab>', 'j', { buffer = args.buf, silent = true, desc = 'Next Item' })
          vim.keymap.set('n', '<S-Tab>', 'k', { buffer = args.buf, silent = true, desc = 'Previous Item' })
          vim.keymap.set('n', 'l', '<CR>', { buffer = args.buf, remap = true, silent = true, desc = 'Open / Expand Node' })
          vim.keymap.set('n', 'p', function() require('sqmeow.ui.drawer').actions.preview() end, { buffer = args.buf, silent = true, desc = 'Run First 1000' })
          vim.keymap.set('n', 'P', function()
            local drawer = require('sqmeow.ui.drawer')
            local node = drawer.current_node()
            if node and node.path and #node.path == 3 and (node.path[2] == 'tables' or node.path[2] == 'views') then
              local schema = node.path[1]
              local rel = node.path[3]
              M.execute_default_query(node.conn_id, schema, rel, 'count')
            end
          end, { buffer = args.buf, silent = true, desc = 'Run Count (*)' })
          vim.keymap.set('n', 'K', function() require('sqmeow.ui.drawer').actions.structure() end, { buffer = args.buf, silent = true, desc = 'Table Structure / Schema' })
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

          -- Quick Column Navigation (<Tab>/<S-Tab>, ]c/[c, g0/g$)
          vim.keymap.set('n', '<Tab>', function() M.next_result_column() end, { buffer = args.buf, silent = true, desc = 'Next Column' })
          vim.keymap.set('n', '<S-Tab>', function() M.prev_result_column() end, { buffer = args.buf, silent = true, desc = 'Previous Column' })
          vim.keymap.set('n', ']c', function() M.next_result_column() end, { buffer = args.buf, silent = true, desc = 'Next Column' })
          vim.keymap.set('n', '[c', function() M.prev_result_column() end, { buffer = args.buf, silent = true, desc = 'Previous Column' })
          vim.keymap.set('n', 'g0', function() M.first_result_column() end, { buffer = args.buf, silent = true, desc = 'First Column' })
          vim.keymap.set('n', 'g$', function() M.last_result_column() end, { buffer = args.buf, silent = true, desc = 'Last Column' })

          vim.keymap.set('n', 'q', function()
            M.close_sticky_header()
            require('sqmeow.api').close()
            local ed = _G.RightPanel and _G.RightPanel.get_editor_win and _G.RightPanel.get_editor_win()
            if ed and vim.api.nvim_win_is_valid(ed) then
              vim.api.nvim_set_current_win(ed)
            end
          end, { buffer = args.buf, silent = true, desc = 'Close Query Results' })

          -- Sticky Header & Dynamic Winbar listeners
          local group = vim.api.nvim_create_augroup('SqmeowResultSticky_' .. args.buf, { clear = true })
          vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
            group = group,
            buffer = args.buf,
            callback = function()
              local w = vim.fn.bufwinid(args.buf)
              if w > 0 then
                M.update_result_winbar(w)
                M.update_sticky_header(w)
              end
            end,
          })
          vim.api.nvim_create_autocmd({ 'WinScrolled' }, {
            group = group,
            callback = function()
              local w = vim.fn.bufwinid(args.buf)
              if w > 0 then
                M.update_sticky_header(w)
              end
            end,
          })
          vim.api.nvim_create_autocmd({ 'BufLeave', 'BufHidden', 'BufDelete', 'BufUnload' }, {
            group = group,
            buffer = args.buf,
            callback = function()
              M.close_sticky_header()
            end,
          })
        end,
      })
    end,
    config = function(_, opts)
      require('sqmeow').setup(opts)
      M.setup_drawer_helpers()
    end,
    opts = {
      ui = {
        drawer = { width = 35 },
        result = {
          height = 16,
          page_size = 1000,
          max_column_width = 48,
          column_icons = true,
          null_text = 'NULL',
        },
      },
      keymaps = {
        drawer = {
          { action = 'toggle', lhs = { '<CR>', 'o', 'l' }, desc = 'Expand or collapse the node' },
          { action = 'close', lhs = 'q', desc = 'Close the drawer' },
          { action = 'preview', lhs = 'p', desc = 'Show the first 1000 rows of this relation' },
          { action = 'structure', lhs = 'K', desc = 'Show structure of table or key' },
        },
      },
    },
    keys = {
      {
        '<leader>be',
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
