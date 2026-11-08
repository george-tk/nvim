local M = {}

local cache_dir = vim.fs.normalize(vim.fn.stdpath 'cache' .. '/sqmeow-erd')

-- Active async listeners state
M._wired = false
M._struct_waiters = {}
M._rel_waiters = {}
M._nodes_waiters = {}
M._buf_specs = {}
M._seq = 500000

local function sqmeow(submod)
  local ok, mod = pcall(require, 'sqmeow.' .. submod)
  if not ok then
    pcall(function()
      require('lazy').load { plugins = { 'sqmeow.nvim' } }
    end)
    ok, mod = pcall(require, 'sqmeow.' .. submod)
  end
  return ok and mod or nil
end

local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = 'Database ERD' })
end

local function same_ident(a, b)
  return a == b or (type(a) == 'string' and type(b) == 'string' and a:lower() == b:lower())
end

local function qualified(schema, relation)
  if not schema or schema == '' then
    return relation
  end
  return schema .. '.' .. relation
end

-------------------------------------------------------------------------------
-- Engine Event Wiring (Non-intrusive subscriptions to sqmeow RPC events)
-------------------------------------------------------------------------------

function M.ensure_wired()
  local events = sqmeow 'rpc.events'
  local rpc = sqmeow 'rpc.client'
  if not events or not rpc then
    return false
  end
  events.ensure()

  if M._wired then
    return true
  end
  M._wired = true

  rpc.on('structure:done', function(payload)
    if not payload or not payload.conn_id or not payload.relation then
      return
    end
    local key = string.format('%d:%s:%s', payload.conn_id, (payload.schema or ''):lower(), payload.relation:lower())
    local cbs = M._struct_waiters[key]
    if cbs then
      M._struct_waiters[key] = nil
      vim.schedule(function()
        for _, cb in ipairs(cbs) do
          pcall(cb, payload)
        end
      end)
    end
  end)

  rpc.on('relationships:done', function(payload)
    if not payload or not payload.request_id then
      return
    end
    local cb = M._rel_waiters[payload.request_id]
    if cb then
      M._rel_waiters[payload.request_id] = nil
      vim.schedule(function()
        pcall(cb, payload)
      end)
    end
  end)

  rpc.on('schema:nodes', function(payload)
    if not payload or not payload.conn_id then
      return
    end
    local path_str = table.concat(payload.path or {}, '\0')
    local key = string.format('%d:%s', payload.conn_id, path_str)
    local cbs = M._nodes_waiters[key]
    if cbs then
      M._nodes_waiters[key] = nil
      vim.schedule(function()
        for _, cb in ipairs(cbs) do
          pcall(cb, payload)
        end
      end)
    end
  end)

  return true
end

local function fetch_structure(conn_id, schema, relation, callback)
  M.ensure_wired()
  local rpc = sqmeow 'rpc.client'
  if not rpc then
    return callback { error = 'RPC client unavailable' }
  end
  local key = string.format('%d:%s:%s', conn_id, (schema or ''):lower(), relation:lower())
  M._struct_waiters[key] = M._struct_waiters[key] or {}
  table.insert(M._struct_waiters[key], callback)
  local _, err = rpc.request('structure', {
    conn_id = conn_id,
    schema = schema or '',
    relation = relation,
  })
  if err then
    M._struct_waiters[key] = nil
    callback { error = err, conn_id = conn_id, schema = schema, relation = relation }
  end
end

local function fetch_relationships(conn_id, schema, relation, callback)
  M.ensure_wired()
  local rpc = sqmeow 'rpc.client'
  if not rpc then
    return callback { error = 'RPC client unavailable' }
  end
  M._seq = M._seq + 1
  local req_id = M._seq
  M._rel_waiters[req_id] = callback
  local _, err = rpc.request('relationships', {
    conn_id = conn_id,
    schema = schema or '',
    relation = relation,
    request_id = req_id,
  })
  if err then
    M._rel_waiters[req_id] = nil
    callback { error = err, conn_id = conn_id, schema = schema, relation = relation }
  end
end

local function fetch_nodes(conn_id, path, callback)
  M.ensure_wired()
  local drawer = sqmeow 'ui.drawer'
  if drawer and drawer.cached_nodes then
    local cached = drawer.cached_nodes(conn_id, path)
    if cached then
      return callback { conn_id = conn_id, path = path, nodes = cached }
    end
  end
  local rpc = sqmeow 'rpc.client'
  if not rpc then
    return callback { error = 'RPC client unavailable', nodes = {} }
  end
  local path_str = table.concat(path or {}, '\0')
  local key = string.format('%d:%s', conn_id, path_str)
  M._nodes_waiters[key] = M._nodes_waiters[key] or {}
  table.insert(M._nodes_waiters[key], callback)
  local _, err = rpc.request('introspect', {
    conn_id = conn_id,
    path = path or {},
  })
  if err then
    M._nodes_waiters[key] = nil
    callback { error = err, nodes = {} }
  end
end

-------------------------------------------------------------------------------
-- Mermaid ER Diagram Code Generator & Cardinality Inference
-------------------------------------------------------------------------------

local function normalize_mermaid_type(raw_type)
  if not raw_type or raw_type == '' then
    return 'unknown'
  end
  local t = vim.trim(raw_type):lower()
  t = t:gsub('^character varying', 'varchar')
  t = t:gsub('^character', 'char')
  t = t:gsub('^timestamp without time zone', 'timestamp')
  t = t:gsub('^timestamp with time zone', 'timestamptz')
  t = t:gsub('^time without time zone', 'time')
  t = t:gsub('^time with time zone', 'timetz')
  t = t:gsub('^double precision', 'float8')
  t = t:gsub('%s+', '_')
  t = t:gsub('[^%w_%-(),%[%]]', '')
  if t == '' then
    t = 'unknown'
  end
  return t
end

local function normalize_mermaid_ident(name)
  if not name or name == '' then
    return 'unnamed'
  end
  local s = name:gsub('[^%w_]', '_')
  if s:match '^%d' then
    s = '_' .. s
  end
  return s
end

local function format_mermaid_entity_name(schema, relation, multi_schema)
  local raw = (multi_schema and schema and schema ~= '') and (schema .. '.' .. relation) or relation
  if raw:match '^[%a_][%w_]*$' then
    return raw
  end
  return '"' .. raw:gsub('"', '') .. '"'
end

-- Check whether a list of FK columns on a table forms an exact UNIQUE or PRIMARY KEY index
local function is_unique_fk(struct, fk_cols)
  if not struct or not fk_cols or #fk_cols == 0 then
    return false
  end
  for _, idx in ipairs(struct.indexes or {}) do
    if (idx.unique or idx.primary) and idx.columns and #idx.columns == #fk_cols then
      local all_match = true
      for _, fc in ipairs(fk_cols) do
        local found = false
        for _, ic in ipairs(idx.columns) do
          if same_ident(fc, ic) then
            found = true
            break
          end
        end
        if not found then
          all_match = false
          break
        end
      end
      if all_match then
        return true
      end
    end
  end
  -- Also check single-column primary key directly on columns metadata (only if the table PK is a 1-column PK, not composite)
  if #fk_cols == 1 then
    local pk_count = 0
    local fk_is_pk = false
    for _, col in ipairs(struct.columns or {}) do
      if col.primary_key then
        pk_count = pk_count + 1
        if same_ident(col.name, fk_cols[1]) then
          fk_is_pk = true
        end
      end
    end
    if fk_is_pk and pk_count == 1 then
      return true
    end
  end
  return false
end

-- Check if any column in fk_cols on `struct` is nullable
local function is_nullable_fk(struct, fk_cols)
  if not struct or not fk_cols or #fk_cols == 0 then
    return true
  end
  for _, fc in ipairs(fk_cols) do
    for _, col in ipairs(struct.columns or {}) do
      if same_ident(col.name, fc) and col.nullable then
        return true
      end
    end
  end
  return false
end

-- Build Mermaid `erDiagram` string and normalized relationship list from collected table structures
function M.build_mermaid(tables_map, table_order, center_key)
  local schemas_seen = {}
  local schema_count = 0
  for _, key in ipairs(table_order) do
    local entry = tables_map[key]
    if entry and entry.schema and entry.schema ~= '' and not schemas_seen[entry.schema:lower()] then
      schemas_seen[entry.schema:lower()] = true
      schema_count = schema_count + 1
    end
  end
  local multi_schema = schema_count > 1

  -- Collect deduplicated relationships where both source and target are in `tables_map`
  local edges = {}
  local edge_seen = {}

  for _, key in ipairs(table_order) do
    local entry = tables_map[key]
    local struct = entry and entry.structure
    if struct then
      -- 1. From structure.foreign_keys
      for _, fk in ipairs(struct.foreign_keys or {}) do
        local target_raw = fk.target or ''
        local target_schema, target_rel = target_raw:match '^([^.]+)%.(.+)$'
        if not target_rel then
          target_schema = entry.schema or ''
          target_rel = target_raw
        end
        local target_key = ((target_schema or ''):lower()) .. '.' .. (target_rel or ''):lower()
        if not tables_map[target_key] then
          -- Try matching by relation name across any loaded schema
          for k, candidate in pairs(tables_map) do
            if same_ident(candidate.relation, target_rel) then
              target_key = k
              target_schema = candidate.schema
              target_rel = candidate.relation
              break
            end
          end
        end

        if tables_map[target_key] then
          local src_cols = table.concat(fk.columns or {}, ', ')
          local ref_cols = table.concat(fk.referenced or {}, ', ')
          local sig = string.format('%s(%s)->%s(%s)', key, src_cols:lower(), target_key, ref_cols:lower())
          if not edge_seen[sig] then
            edge_seen[sig] = true
            local nullable = is_nullable_fk(struct, fk.columns)
            local unique = is_unique_fk(struct, fk.columns)
            local parent_card = nullable and '|o' or '||'
            local child_card = unique and '|o' or 'o{'
            table.insert(edges, {
              source_key = key,
              source_schema = entry.schema,
              source_relation = entry.relation,
              target_key = target_key,
              target_schema = tables_map[target_key].schema,
              target_relation = tables_map[target_key].relation,
              columns = fk.columns or {},
              referenced = fk.referenced or {},
              name = fk.name or '',
              connector = parent_card .. '--' .. child_card,
              cardinality_label = (unique and '1:1' or '1:N') .. (nullable and ' (optional)' or ''),
            })
          end
        end
      end
    end
  end

  local mmd_lines = { 'erDiagram' }

  -- Emit relationship lines first (Parent ||--o{ Child : "fk -> pk")
  for _, edge in ipairs(edges) do
    local parent_name = format_mermaid_entity_name(edge.target_schema, edge.target_relation, multi_schema)
    local child_name = format_mermaid_entity_name(edge.source_schema, edge.source_relation, multi_schema)
    local src_cols = table.concat(edge.columns, ', ')
    local ref_cols = table.concat(edge.referenced, ', ')
    local label = src_cols ~= '' and (src_cols .. ' -> ' .. ref_cols) or (edge.name ~= '' and edge.name or 'references')
    label = label:gsub('"', "'")
    table.insert(mmd_lines, string.format('  %s %s %s : "%s"', parent_name, edge.connector, child_name, label))
  end

  if #edges > 0 then
    table.insert(mmd_lines, '')
  end

  -- Emit entity blocks with columns, types, PK/FK/UK badges, and comments
  for _, key in ipairs(table_order) do
    local entry = tables_map[key]
    local struct = entry and entry.structure or {}
    local entity_name = format_mermaid_entity_name(entry.schema, entry.relation, multi_schema)
    table.insert(mmd_lines, string.format('  %s {', entity_name))

    -- Identify FK and UK columns for badge tagging
    local fk_col_map = {}
    for _, fk in ipairs(struct.foreign_keys or {}) do
      for idx, c in ipairs(fk.columns or {}) do
        local ref_target = fk.target or ''
        local ref_col = (fk.referenced and fk.referenced[idx]) or ''
        fk_col_map[c:lower()] = ref_col ~= '' and (ref_target .. '.' .. ref_col) or ref_target
      end
    end
    local uk_col_map = {}
    for _, idx in ipairs(struct.indexes or {}) do
      if idx.unique and not idx.primary then
        for _, c in ipairs(idx.columns or {}) do
          uk_col_map[c:lower()] = true
        end
      end
    end

    local cols = struct.columns or {}
    if #cols == 0 then
      table.insert(mmd_lines, '    string _no_columns_ "empty"')
    else
      for _, col in ipairs(cols) do
        local mtype = normalize_mermaid_type(col.type_name)
        local mname = normalize_mermaid_ident(col.name)
        local badges = {}
        if col.primary_key then
          table.insert(badges, 'PK')
        end
        local fk_ref = col.references or fk_col_map[(col.name or ''):lower()]
        if fk_ref then
          table.insert(badges, 'FK')
        elseif uk_col_map[(col.name or ''):lower()] and not col.primary_key then
          table.insert(badges, 'UK')
        end
        local badge_str = #badges > 0 and (' ' .. table.concat(badges, ',')) or ''

        local notes = {}
        if not col.nullable and not col.primary_key then
          table.insert(notes, 'NOT NULL')
        end
        if fk_ref then
          table.insert(notes, '-> ' .. tostring(fk_ref))
        end
        local comment_str = #notes > 0 and string.format(' "%s"', table.concat(notes, ' ')) or ''
        table.insert(mmd_lines, string.format('    %s %s%s%s', mtype, mname, badge_str, comment_str))
      end
    end

    table.insert(mmd_lines, '  }')
  end

  return table.concat(mmd_lines, '\n'), edges
end

-------------------------------------------------------------------------------
-- Mermaid CLI (mmdc) Compiler & Interactive Browser SVG/HTML Exporter
-------------------------------------------------------------------------------

local function ensure_cache_dir()
  if vim.fn.isdirectory(cache_dir) == 0 then
    vim.fn.mkdir(cache_dir, 'p')
  end
  local cfg_path = cache_dir .. '/mermaid-config.json'
  if vim.fn.filereadable(cfg_path) == 0 then
    local cfg = {
      theme = 'dark',
      er = {
        layoutDirection = 'LR',
        entityPadding = 14,
        stroke = '#89b4fa',
        fill = '#1e1e2e',
        fontSize = 13,
      },
      themeVariables = {
        primaryColor = '#1e1e2e',
        primaryTextColor = '#cdd6f4',
        primaryBorderColor = '#89b4fa',
        lineColor = '#a6adc8',
        secondaryColor = '#313244',
        tertiaryColor = '#45475a',
        fontFamily = 'monospace',
      },
    }
    pcall(vim.fn.writefile, { vim.fn.json_encode(cfg) }, cfg_path)
  end
  return cfg_path
end

function M.compile_mermaid_png(mermaid_code, callback)
  if vim.fn.executable 'mmdc' == 0 then
    return callback(nil, 'mmdc (Mermaid CLI) is not installed')
  end
  local cfg_path = ensure_cache_dir()
  local hash = vim.fn.sha256(mermaid_code):sub(1, 16)
  local mmd_path = string.format('%s/erd-%s.mmd', cache_dir, hash)
  local png_path = string.format('%s/erd-%s.png', cache_dir, hash)

  if vim.fn.filereadable(png_path) == 1 and vim.fn.getfsize(png_path) > 0 then
    return callback(png_path, nil)
  end

  pcall(vim.fn.writefile, vim.split(mermaid_code, '\n', { plain = true }), mmd_path)

  vim.system({
    'mmdc',
    '-i',
    mmd_path,
    '-o',
    png_path,
    '-c',
    cfg_path,
    '-b',
    'transparent',
    '-s',
    '2',
  }, { text = true }, function(res)
    vim.schedule(function()
      if res.code == 0 and vim.fn.filereadable(png_path) == 1 and vim.fn.getfsize(png_path) > 0 then
        callback(png_path, nil)
      else
        callback(nil, vim.trim((res.stderr or '') .. '\n' .. (res.stdout or '')))
      end
    end)
  end)
end

function M.open_interactive_browser(title, mermaid_code)
  ensure_cache_dir()
  local hash = vim.fn.sha256(title .. '\n' .. mermaid_code):sub(1, 16)
  local html_path = string.format('%s/erd-%s.html', cache_dir, hash)
  local svg_path = string.format('%s/erd-%s.svg', cache_dir, hash)
  local mmd_path = string.format('%s/erd-%s.mmd', cache_dir, hash)
  local cfg_path = cache_dir .. '/mermaid-config.json'

  pcall(vim.fn.writefile, vim.split(mermaid_code, '\n', { plain = true }), mmd_path)

  local function write_and_open_html(svg_content)
    local html = string.format(
      [[<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>%s</title>
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { background: #11111b; color: #cdd6f4; font-family: system-ui, -apple-system, monospace; overflow: hidden; height: 100vh; display: flex; flex-direction: column; }
  header { background: #181825; border-bottom: 1px solid #313244; padding: 10px 18px; display: flex; align-items: center; justify-content: space-between; z-index: 10; }
  header h1 { font-size: 15px; font-weight: 600; color: #89b4fa; }
  .controls { display: flex; gap: 8px; align-items: center; font-size: 12px; color: #a6adc8; }
  button { background: #313244; color: #cdd6f4; border: 1px solid #45475a; border-radius: 6px; padding: 5px 12px; cursor: pointer; font-size: 12px; }
  button:hover { background: #45475a; border-color: #89b4fa; }
  #viewport { flex: 1; overflow: hidden; cursor: grab; position: relative; display: flex; align-items: center; justify-content: center; }
  #viewport.dragging { cursor: grabbing; }
  #canvas { transform-origin: center center; transition: transform 0.04s linear; }
  #canvas svg { max-width: none !important; height: auto !important; }
</style>
</head>
<body>
  <header>
    <h1>%s</h1>
    <div class="controls">
      <span>Scroll to Zoom · Drag to Pan</span>
      <button onclick="zoomBy(1.25)">Zoom In (+)</button>
      <button onclick="zoomBy(0.8)">Zoom Out (-)</button>
      <button onclick="resetView()">Reset (100%%)</button>
    </div>
  </header>
  <div id="viewport">
    <div id="canvas">%s</div>
  </div>
  <script>
    const vp = document.getElementById('viewport');
    const cv = document.getElementById('canvas');
    let scale = 1, tx = 0, ty = 0, dragging = false, sx = 0, sy = 0;
    function apply() { cv.style.transform = `translate(${tx}px, ${ty}px) scale(${scale})`; }
    function zoomBy(factor) { scale = Math.min(Math.max(scale * factor, 0.15), 12); apply(); }
    function resetView() { scale = 1; tx = 0; ty = 0; apply(); }
    vp.addEventListener('wheel', (e) => {
      e.preventDefault();
      zoomBy(e.deltaY < 0 ? 1.12 : 0.89);
    }, { passive: false });
    vp.addEventListener('mousedown', (e) => { dragging = true; sx = e.clientX - tx; sy = e.clientY - ty; vp.classList.add('dragging'); });
    window.addEventListener('mousemove', (e) => { if (!dragging) return; tx = e.clientX - sx; ty = e.clientY - sy; apply(); });
    window.addEventListener('mouseup', () => { dragging = false; vp.classList.remove('dragging'); });
  </script>
</body>
</html>]],
      title,
      title,
      svg_content
    )
    vim.fn.writefile(vim.split(html, '\n', { plain = true }), html_path)
    if vim.ui and vim.ui.open then
      vim.ui.open(html_path)
    else
      vim.fn.jobstart({ 'xdg-open', html_path }, { detach = true })
    end
    notify('Opened interactive ERD in browser: ' .. title)
  end

  if vim.fn.filereadable(svg_path) == 1 and vim.fn.getfsize(svg_path) > 0 then
    local svg_lines = vim.fn.readfile(svg_path)
    return write_and_open_html(table.concat(svg_lines, '\n'))
  end

  if vim.fn.executable 'mmdc' == 1 then
    notify 'Compiling SVG for interactive browser view…'
    vim.system({
      'mmdc',
      '-i',
      mmd_path,
      '-o',
      svg_path,
      '-c',
      cfg_path,
      '-b',
      'transparent',
    }, { text = true }, function(res)
      vim.schedule(function()
        if res.code == 0 and vim.fn.filereadable(svg_path) == 1 then
          local svg_lines = vim.fn.readfile(svg_path)
          write_and_open_html(table.concat(svg_lines, '\n'))
        else
          notify('Failed to compile SVG via mmdc', vim.log.levels.ERROR)
        end
      end)
    end)
  else
    notify('mmdc is not installed; cannot compile SVG', vim.log.levels.WARN)
  end
end

-------------------------------------------------------------------------------
-- Interactive ERD Buffer Renderer & Navigation Actions
-------------------------------------------------------------------------------

local function execute_table_preview(conn_id, dialect, schema, relation, in_editor)
  local sql_mod = sqmeow 'core.sql'
  local config = sqmeow 'config'
  local conn_api = sqmeow 'api.connection'
  local query_api = sqmeow 'api.query'
  if not sql_mod or not query_api or not conn_api then
    return
  end
  local limit = (config and config.get().ui.result.page_size) or 1000
  local parts = (schema and schema ~= '') and { schema, relation } or { relation }
  local statement = sql_mod.select_from(dialect or 'postgres', parts, limit)
  if not statement then
    return
  end

  conn_api.use(conn_id)

  if in_editor then
    local text = statement .. ';'
    local target_buf = vim.api.nvim_create_buf(true, true)
    local count = 0
    local suffix = ''
    while not pcall(vim.api.nvim_buf_set_name, target_buf, ('[Preview: %s%s]'):format(relation, suffix)) do
      count = count + 1
      suffix = (' (%d)'):format(count)
    end
    vim.bo[target_buf].buftype = 'nofile'
    vim.bo[target_buf].bufhidden = 'hide'
    vim.bo[target_buf].swapfile = false
    vim.bo[target_buf].filetype = 'sql'
    vim.b[target_buf].is_preview_buffer = true
    vim.b[target_buf].sqmeow_table = relation
    vim.b[target_buf].sqmeow_schema = schema
    vim.api.nvim_buf_set_lines(target_buf, 0, -1, false, vim.split(text, '\n', { plain = true }))
    vim.bo[target_buf].modified = false

    local state = sqmeow 'core.state'
    local conn = state and state.connections[conn_id]
    local editor = sqmeow 'ui.editor'
    if editor and editor.attach then
      editor.attach(target_buf, conn and conn.name)
    end
    local ed_win = (_G.RightPanel and _G.RightPanel.get_editor_win and _G.RightPanel.get_editor_win())
      or vim.api.nvim_get_current_win()
    if vim.api.nvim_win_is_valid(ed_win) then
      if vim.fn.exists '&winfixbuf' == 1 and vim.wo[ed_win].winfixbuf then
        vim.wo[ed_win].winfixbuf = false
      end
      vim.api.nvim_win_set_buf(ed_win, target_buf)
      vim.api.nvim_set_current_win(ed_win)
    end
  end

  if _G.BottomPanel then
    _G.BottomPanel.active_mode = 'dbout'
  end
  query_api.execute(statement, { conn_id = conn_id, history = false })
  if _G.BottomPanel and _G.BottomPanel.ensure_precedence then
    vim.schedule(function()
      _G.BottomPanel.ensure_precedence()
    end)
  end
end

function M.render_erd_buffer(spec)
  -- spec: {
  --   conn_id, conn_name, dialect, mode ('neighborhood'|'schema'),
  --   schema, center_schema, center_relation, hops,
  --   tables_map, table_order, mermaid_code, edges, show_mermaid_src, buf
  -- }
  local title_target = spec.mode == 'neighborhood'
      and qualified(spec.center_schema, spec.center_relation)
    or (spec.schema ~= '' and spec.schema or spec.conn_name)
  local buf_name = string.format('[ERD: %s (%s)]', title_target, spec.conn_name)

  local buf = spec.buf
  if not (buf and vim.api.nvim_buf_is_valid(buf)) then
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_valid(b) and vim.api.nvim_buf_get_name(b):find(buf_name, 1, true) then
        buf = b
        break
      end
    end
  end

  if not (buf and vim.api.nvim_buf_is_valid(buf)) then
    buf = vim.api.nvim_create_buf(true, true)
    local suffix = ''
    local count = 0
    while not pcall(vim.api.nvim_buf_set_name, buf, buf_name .. suffix) do
      count = count + 1
      suffix = (' (%d)'):format(count)
    end
  end
  spec.buf = buf

  -- Ensure buffer opens in the main editor window (never inside the 35-col right drawer)
  local ed_win = (_G.RightPanel and _G.RightPanel.get_editor_win and _G.RightPanel.get_editor_win())
    or vim.api.nvim_get_current_win()
  if vim.api.nvim_win_is_valid(ed_win) then
    if vim.fn.exists '&winfixbuf' == 1 and vim.wo[ed_win].winfixbuf then
      vim.wo[ed_win].winfixbuf = false
    end
    vim.api.nvim_win_set_buf(ed_win, buf)
  end

  local lines = {}
  local line_targets = {}

  local scope_label = spec.mode == 'neighborhood'
      and string.format('Table Neighborhood (%d-hop around `%s`)', spec.hops or 1, qualified(spec.center_schema, spec.center_relation))
    or string.format('Full Schema (`%s`)', spec.schema ~= '' and spec.schema or 'default')

  table.insert(lines, string.format('# 󰆼 Entity Relationship Diagram — %s', title_target))
  table.insert(lines, '')
  table.insert(
    lines,
    string.format(
      '> **Connection:** `%s` (%s) · **Scope:** %s · **Tables:** `%d` · **Relationships:** `%d`',
      spec.conn_name,
      spec.dialect or 'sql',
      scope_label,
      #spec.table_order,
      #spec.edges
    )
  )
  table.insert(
    lines,
    '> **Keys:** `l`/`<CR>`/`p` Preview Grid · `P` Preview SQL · `K` Structure · `gR` FKs · `ge` Pivot Table ERD · `gE` Full Schema ERD · `+`/`-` Hops · `gx` Browser Zoom · `gm` Mermaid Code · `gy` Yank Mermaid · `r` Refresh · `q` Close'
  )
  table.insert(lines, '')

  -- Image slot line (line index recorded so async mmdc completion can swap it in-place)
  local img_line_idx = #lines + 1
  if spec.png_path and vim.fn.filereadable(spec.png_path) == 1 then
    table.insert(lines, string.format('![Entity Relationship Diagram](%s)', spec.png_path))
  elseif vim.fn.executable 'mmdc' == 1 then
    table.insert(lines, '_⏳ Rendering graphical ERD diagram via Mermaid CLI (`mmdc`)…_')
  else
    table.insert(lines, '```mermaid')
    for _, ml in ipairs(vim.split(spec.mermaid_code, '\n', { plain = true })) do
      table.insert(lines, ml)
    end
    table.insert(lines, '```')
  end
  table.insert(lines, '')

  -- Relationships Summary Table
  table.insert(lines, '## 󰌷 Foreign Key Relationships')
  table.insert(lines, '')
  if #spec.edges == 0 then
    table.insert(lines, '_No declared foreign key relationships between the tables in this view._')
    if spec.mode == 'neighborhood' then
      table.insert(lines, '_Tip: Press `gE` to view the Full Schema ERD._')
    end
  else
    table.insert(lines, '| Child Table (FK) | Cardinality | Parent Table (PK) | Mapping | Constraint |')
    table.insert(lines, '| :--- | :---: | :--- | :--- | :--- |')
    for _, edge in ipairs(spec.edges) do
      local child_q = qualified(edge.source_schema, edge.source_relation)
      local parent_q = qualified(edge.target_schema, edge.target_relation)
      local mapping = string.format('`%s` → `%s`', table.concat(edge.columns, ', '), table.concat(edge.referenced, ', '))
      local cname = edge.name ~= '' and ('`' .. edge.name .. '`') or '_unnamed_'
      table.insert(
        lines,
        string.format('| **`%s`** | `%s` | **`%s`** | %s | %s |', child_q, edge.cardinality_label, parent_q, mapping, cname)
      )
      line_targets[#lines] = {
        schema = edge.source_schema,
        relation = edge.source_relation,
        alt_schema = edge.target_schema,
        alt_relation = edge.target_relation,
      }
    end
  end
  table.insert(lines, '')

  -- Interactive Tables & Columns Directory
  table.insert(lines, '## 󰓫 Tables & Columns (Press `l`/`<CR>` to Preview, `K` for Structure, `ge` to Pivot ERD)')
  table.insert(lines, '')

  for _, key in ipairs(spec.table_order) do
    local entry = spec.tables_map[key]
    local struct = entry and entry.structure or {}
    local cols = struct.columns or {}
    local fks = struct.foreign_keys or {}
    local is_center = spec.mode == 'neighborhood'
      and same_ident(entry.schema, spec.center_schema)
      and same_ident(entry.relation, spec.center_relation)

    local badge = is_center and ' 🎯 *(Focused)*' or ''
    local tbl_q = qualified(entry.schema, entry.relation)
    local start_line = #lines + 1
    table.insert(
      lines,
      string.format('### `%s`%s — %d columns, %d outgoing FK%s', tbl_q, badge, #cols, #fks, #fks == 1 and '' or 's')
    )
    table.insert(lines, '')

    local fk_col_map = {}
    for _, fk in ipairs(fks) do
      for idx, c in ipairs(fk.columns or {}) do
        local ref_col = (fk.referenced and fk.referenced[idx]) or ''
        fk_col_map[c:lower()] = ref_col ~= '' and (fk.target .. '(' .. ref_col .. ')') or fk.target
      end
    end
    local uk_col_map = {}
    for _, idx in ipairs(struct.indexes or {}) do
      if idx.unique and not idx.primary then
        for _, c in ipairs(idx.columns or {}) do
          uk_col_map[c:lower()] = true
        end
      end
    end

    if #cols == 0 then
      table.insert(lines, '_No columns reported._')
    else
      table.insert(lines, '| Key | Column | Type | Nullable | Default | References |')
      table.insert(lines, '| :---: | :--- | :--- | :---: | :--- | :--- |')
      for _, col in ipairs(cols) do
        local keys = {}
        if col.primary_key then
          table.insert(keys, '🔑 PK')
        end
        local fk_ref = col.references or fk_col_map[(col.name or ''):lower()]
        if fk_ref then
          table.insert(keys, '🔗 FK')
        elseif uk_col_map[(col.name or ''):lower()] and not col.primary_key then
          table.insert(keys, '✦ UK')
        end
        local key_str = #keys > 0 and table.concat(keys, ' ') or ''
        local null_str = col.nullable and 'NULL' or '**NOT NULL**'
        local def_str = (col.default and col.default ~= '') and ('`' .. tostring(col.default) .. '`') or ''
        local ref_str = fk_ref and ('`→ ' .. tostring(fk_ref) .. '`') or ''
        table.insert(
          lines,
          string.format(
            '| %s | **`%s`** | `%s` | %s | %s | %s |',
            key_str,
            col.name or '',
            col.type_name or '',
            null_str,
            def_str,
            ref_str
          )
        )
      end
    end
    table.insert(lines, '')
    local end_line = #lines
    for l = start_line, end_line do
      line_targets[l] = { schema = entry.schema, relation = entry.relation }
    end
  end

  if spec.show_mermaid_src then
    table.insert(lines, '## 󰅩 Mermaid `erDiagram` Source')
    table.insert(lines, '')
    table.insert(lines, '```mermaid')
    for _, ml in ipairs(vim.split(spec.mermaid_code, '\n', { plain = true })) do
      table.insert(lines, ml)
    end
    table.insert(lines, '```')
    table.insert(lines, '')
  end

  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'hide'
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].modified = false
  vim.bo[buf].filetype = 'markdown'

  M._buf_specs[buf] = spec
  vim.b[buf].sqmeow_erd_spec = spec
  vim.b[buf].sqmeow_erd_targets = line_targets
  vim.b[buf].sqmeow_connection = spec.conn_name
  vim.b[buf].db_name = spec.conn_name
  if spec.center_relation then
    vim.b[buf].sqmeow_table = spec.center_relation
  end

  for _, w in ipairs(vim.fn.win_findbuf(buf)) do
    if vim.api.nvim_win_is_valid(w) then
      vim.wo[w].spell = false
      vim.wo[w].wrap = false
      vim.wo[w].cursorline = true
    end
  end

  -- Trigger snacks.image attachment for inline diagram rendering
  pcall(function()
    if _G.Snacks and Snacks.image and Snacks.image.doc then
      Snacks.image.doc.attach(buf)
    end
  end)

  -- Compile PNG in background if not yet compiled
  if not spec.png_path and vim.fn.executable 'mmdc' == 1 then
    M.compile_mermaid_png(spec.mermaid_code, function(png_path, err)
      if not vim.api.nvim_buf_is_valid(buf) then
        return
      end
      vim.bo[buf].modifiable = true
      if png_path then
        spec.png_path = png_path
        M._buf_specs[buf] = spec
        vim.b[buf].sqmeow_erd_spec = spec
        vim.api.nvim_buf_set_lines(
          buf,
          img_line_idx - 1,
          img_line_idx,
          false,
          { string.format('![Entity Relationship Diagram](%s)', png_path) }
        )
      else
        local fallback = { '```mermaid' }
        vim.list_extend(fallback, vim.split(spec.mermaid_code, '\n', { plain = true }))
        table.insert(fallback, '```')
        vim.api.nvim_buf_set_lines(buf, img_line_idx - 1, img_line_idx, false, fallback)
        if err and err ~= '' then
          notify('mmdc warning: ' .. err, vim.log.levels.WARN)
        end
      end
      vim.bo[buf].modifiable = false
      vim.bo[buf].modified = false
      pcall(function()
        if _G.Snacks and Snacks.image and Snacks.image.doc then
          vim.b[buf].snacks_image_attached = false
          Snacks.image.doc.attach(buf)
        end
      end)
    end)
  end

  -- Helper to get the table target under cursor in the ERD buffer
  local function target_at_cursor()
    local cur_line = vim.api.nvim_win_get_cursor(0)[1]
    local targets = vim.b[buf].sqmeow_erd_targets or {}
    if targets[cur_line] then
      return targets[cur_line]
    end
    -- Fallback to focused table or first table in diagram
    if spec.center_relation then
      return { schema = spec.center_schema or spec.schema, relation = spec.center_relation }
    end
    if spec.table_order and spec.table_order[1] then
      local first = spec.tables_map[spec.table_order[1]]
      if first then
        return { schema = first.schema, relation = first.relation }
      end
    end
    return nil
  end

  -- Interactive buffer-local keymaps inside the ERD view
  local bopts = function(desc)
    return { buffer = buf, silent = true, nowait = true, desc = 'ERD: ' .. desc }
  end

  for _, lhs in ipairs { '<CR>', 'l', 'p' } do
    vim.keymap.set('n', lhs, function()
      local t = target_at_cursor()
      if t then
        execute_table_preview(spec.conn_id, spec.dialect, t.schema, t.relation, false)
      end
    end, bopts 'Preview table in bottom result grid')
  end

  vim.keymap.set('n', 'P', function()
    local t = target_at_cursor()
    if t then
      execute_table_preview(spec.conn_id, spec.dialect, t.schema, t.relation, true)
    end
  end, bopts 'Preview table in SQL editor')

  vim.keymap.set('n', 'K', function()
    local t = target_at_cursor()
    local struct_ui = sqmeow 'ui.structure'
    if t and struct_ui and struct_ui.open then
      struct_ui.open(spec.conn_id, t.schema or '', t.relation)
    end
  end, bopts 'Show table structure popup')

  vim.keymap.set('n', 'gR', function()
    local t = target_at_cursor()
    local rel_ui = sqmeow 'ui.relationships'
    if t and rel_ui and rel_ui.open then
      rel_ui.open(spec.conn_id, t.schema or '', t.relation)
    end
  end, bopts 'Browse table foreign keys popup')

  vim.keymap.set('n', 'ge', function()
    local t = target_at_cursor()
    if t then
      M.generate_table_erd(spec.conn_id, spec.conn_name, spec.dialect, t.schema or '', t.relation, 1, buf)
    end
  end, bopts 'Pivot ERD to table neighborhood under cursor')

  vim.keymap.set('n', 'gE', function()
    local schema = spec.schema or spec.center_schema or ''
    M.generate_schema_erd(spec.conn_id, spec.conn_name, spec.dialect, schema, buf)
  end, bopts 'Expand to Full Schema ERD')

  for _, lhs in ipairs { '+', '=' } do
    vim.keymap.set('n', lhs, function()
      if spec.mode ~= 'neighborhood' then
        return notify 'Already showing the Full Schema ERD'
      end
      local next_hops = math.min((spec.hops or 1) + 1, 4)
      notify(string.format('Expanding neighborhood ERD to %d hops…', next_hops))
      M.generate_table_erd(
        spec.conn_id,
        spec.conn_name,
        spec.dialect,
        spec.center_schema or '',
        spec.center_relation,
        next_hops,
        buf
      )
    end, bopts 'Increase neighborhood hop depth (+1)')
  end

  vim.keymap.set('n', '-', function()
    if spec.mode ~= 'neighborhood' or (spec.hops or 1) <= 1 then
      return notify 'Already at 1-hop neighborhood minimum'
    end
    local prev_hops = (spec.hops or 2) - 1
    notify(string.format('Shrinking neighborhood ERD to %d hop%s…', prev_hops, prev_hops == 1 and '' or 's'))
    M.generate_table_erd(
      spec.conn_id,
      spec.conn_name,
      spec.dialect,
      spec.center_schema or '',
      spec.center_relation,
      prev_hops,
      buf
    )
  end, bopts 'Decrease neighborhood hop depth (-1)')

  for _, lhs in ipairs { 'gx', 'gb' } do
    vim.keymap.set('n', lhs, function()
      M.open_interactive_browser(buf_name, spec.mermaid_code)
    end, bopts 'Open interactive Pan & Zoom ERD in browser')
  end

  vim.keymap.set('n', 'gm', function()
    spec.show_mermaid_src = not spec.show_mermaid_src
    M.render_erd_buffer(spec)
  end, bopts 'Toggle raw Mermaid erDiagram source block')

  vim.keymap.set('n', 'gy', function()
    local block = '```mermaid\n' .. spec.mermaid_code .. '\n```'
    vim.fn.setreg('"', block)
    pcall(vim.fn.setreg, '+', block)
    notify 'Yanked Mermaid erDiagram block to clipboard'
  end, bopts 'Yank Mermaid erDiagram code to clipboard')

  vim.keymap.set('n', 'r', function()
    notify 'Refreshing ERD from database…'
    if spec.mode == 'neighborhood' then
      M.generate_table_erd(
        spec.conn_id,
        spec.conn_name,
        spec.dialect,
        spec.center_schema or '',
        spec.center_relation,
        spec.hops or 1,
        buf
      )
    else
      M.generate_schema_erd(spec.conn_id, spec.conn_name, spec.dialect, spec.schema or '', buf)
    end
  end, bopts 'Refresh ERD from database')

  vim.keymap.set('n', 'q', function()
    if _G.smart_close then
      _G.smart_close()
    else
      vim.cmd 'bdelete!'
    end
  end, bopts 'Close ERD buffer')

  -- Register in buffer ring and focus editor window
  local ok_br, br = pcall(require, 'utils.buffer-ring')
  if ok_br and br.on_buf_enter then
    br.on_buf_enter(buf)
  end
  if vim.api.nvim_win_is_valid(ed_win) then
    vim.api.nvim_set_current_win(ed_win)
  end
  local ok_layout, layout = pcall(require, 'utils.layout')
  if ok_layout and layout.RightPanel and layout.RightPanel.ensure_precedence then
    vim.schedule(function()
      layout.RightPanel.ensure_precedence()
    end)
  end
end

-------------------------------------------------------------------------------
-- Table Neighborhood ERD & Full Schema ERD Orchestrators
-------------------------------------------------------------------------------

local function collect_structures_and_render(base_spec, table_list)
  local tables_map = {}
  local table_order = {}
  local pending = 0
  local finished = false

  for _, item in ipairs(table_list) do
    local key = ((item.schema or ''):lower()) .. '.' .. item.relation:lower()
    if not tables_map[key] then
      tables_map[key] = {
        schema = item.schema or '',
        relation = item.relation,
        structure = nil,
      }
      table.insert(table_order, key)
      pending = pending + 1
    end
  end

  if pending == 0 then
    return notify('No tables found to generate ERD', vim.log.levels.WARN)
  end

  local function finalize()
    if finished then
      return
    end
    finished = true

    -- Merge any relationship edges discovered during neighborhood traversal into structure.foreign_keys
    if base_spec.discovered_rels then
      for _, rel in ipairs(base_spec.discovered_rels) do
        local src_key = ((rel.source_schema or ''):lower()) .. '.' .. (rel.source_relation or ''):lower()
        local src_entry = tables_map[src_key]
        if src_entry then
          src_entry.structure = src_entry.structure or { columns = {}, indexes = {}, foreign_keys = {} }
          src_entry.structure.foreign_keys = src_entry.structure.foreign_keys or {}
          local target_q = (rel.target_schema and rel.target_schema ~= '' and rel.target_schema ~= rel.source_schema)
              and (rel.target_schema .. '.' .. rel.target_relation)
            or rel.target_relation
          local exists = false
          for _, fk in ipairs(src_entry.structure.foreign_keys) do
            if same_ident(fk.target, target_q) or same_ident(fk.target, rel.target_relation) then
              if table.concat(fk.columns or {}, ',') == table.concat(rel.columns or {}, ',') then
                exists = true
                break
              end
            end
          end
          if not exists then
            table.insert(src_entry.structure.foreign_keys, {
              name = rel.name or '',
              columns = rel.columns or {},
              target = target_q,
              referenced = rel.referenced or {},
            })
          end
        end
      end
    end

    local center_key = base_spec.center_relation
        and (((base_spec.center_schema or ''):lower()) .. '.' .. base_spec.center_relation:lower())
      or nil
    local mermaid_code, edges = M.build_mermaid(tables_map, table_order, center_key)

    base_spec.tables_map = tables_map
    base_spec.table_order = table_order
    base_spec.mermaid_code = mermaid_code
    base_spec.edges = edges
    base_spec.png_path = nil

    M.render_erd_buffer(base_spec)
  end

  for _, key in ipairs(table_order) do
    local entry = tables_map[key]
    fetch_structure(base_spec.conn_id, entry.schema, entry.relation, function(payload)
      if payload and not payload.error then
        entry.structure = payload
        if payload.schema and payload.schema ~= '' then
          entry.schema = payload.schema
        end
      else
        entry.structure = { columns = {}, indexes = {}, foreign_keys = {} }
      end
      pending = pending - 1
      if pending <= 0 then
        finalize()
      end
    end)
  end

  vim.defer_fn(function()
    if not finished then
      finalize()
    end
  end, 4000)
end

-- Generate a 1-hop (or N-hop) Table Neighborhood ERD
function M.generate_table_erd(conn_id, conn_name, dialect, schema, relation, hops, reuse_buf)
  hops = hops or 1
  notify(string.format('Generating %d-hop ERD for %s…', hops, qualified(schema, relation)))

  local visited = {}
  local table_list = {}
  local discovered_rels = {}

  local function add_table(s, r)
    local key = ((s or ''):lower()) .. '.' .. r:lower()
    if not visited[key] then
      visited[key] = { schema = s or '', relation = r, rel_fetched = false }
      table.insert(table_list, visited[key])
      return visited[key]
    end
    return visited[key]
  end

  add_table(schema, relation)

  local function expand_hop(remaining_hops, done_cb)
    if remaining_hops <= 0 then
      return done_cb()
    end
    local to_fetch = {}
    for _, item in ipairs(table_list) do
      if not item.rel_fetched then
        item.rel_fetched = true
        table.insert(to_fetch, item)
      end
    end
    if #to_fetch == 0 then
      return done_cb()
    end

    local pending = #to_fetch
    for _, item in ipairs(to_fetch) do
      fetch_relationships(conn_id, item.schema, item.relation, function(payload)
        if payload and not payload.error then
          if payload.resolved_schema and payload.resolved_schema ~= '' then
            item.schema = payload.resolved_schema
          end
          for _, rel in ipairs(payload.relationships or {}) do
            table.insert(discovered_rels, rel)
            if rel.source_relation then
              add_table(rel.source_schema or item.schema, rel.source_relation)
            end
            if rel.target_relation then
              add_table(rel.target_schema or item.schema, rel.target_relation)
            end
          end
        end
        pending = pending - 1
        if pending <= 0 then
          expand_hop(remaining_hops - 1, done_cb)
        end
      end)
    end
  end

  expand_hop(hops, function()
    collect_structures_and_render({
      conn_id = conn_id,
      conn_name = conn_name,
      dialect = dialect,
      mode = 'neighborhood',
      schema = schema,
      center_schema = schema,
      center_relation = relation,
      hops = hops,
      discovered_rels = discovered_rels,
      buf = reuse_buf,
    }, table_list)
  end)
end

-- Generate a Full Schema ERD across all tables in `schema`
function M.generate_schema_erd(conn_id, conn_name, dialect, schema, reuse_buf)
  local function load_schema_tables(target_schema)
    notify(
      string.format(
        'Generating Full Schema ERD for %s…',
        target_schema ~= '' and (conn_name .. '.' .. target_schema) or conn_name
      )
    )
    local path = target_schema ~= '' and { target_schema, 'tables' } or { 'tables' }
    fetch_nodes(conn_id, path, function(payload)
      local nodes = (payload and payload.nodes) or {}
      local table_list = {}
      for _, n in ipairs(nodes) do
        if n.kind == 'table' or n.kind == 'relation' then
          table.insert(table_list, { schema = target_schema, relation = n.name })
        end
      end
      if #table_list == 0 then
        return notify(
          string.format('No tables found in schema `%s` on `%s`', target_schema ~= '' and target_schema or 'default', conn_name),
          vim.log.levels.WARN
        )
      end
      collect_structures_and_render({
        conn_id = conn_id,
        conn_name = conn_name,
        dialect = dialect,
        mode = 'schema',
        schema = target_schema,
        buf = reuse_buf,
      }, table_list)
    end)
  end

  if schema and schema ~= '' then
    return load_schema_tables(schema)
  end

  -- Discover schemas at connection root
  fetch_nodes(conn_id, {}, function(payload)
    local nodes = (payload and payload.nodes) or {}
    local schemas = {}
    for _, n in ipairs(nodes) do
      if n.kind == 'schema' then
        table.insert(schemas, n.name)
      end
    end
    if #schemas == 0 then
      return load_schema_tables ''
    elseif #schemas == 1 then
      return load_schema_tables(schemas[1])
    else
      -- Prefer 'public', 'dbo', or 'main' if present, otherwise prompt
      for _, pref in ipairs { 'public', 'dbo', 'main' } do
        for _, s in ipairs(schemas) do
          if s:lower() == pref then
            return load_schema_tables(s)
          end
        end
      end
      Snacks.picker.select(schemas, {
        prompt = 'Select Schema for ERD [' .. conn_name .. ']',
      }, function(choice)
        if choice then
          load_schema_tables(choice)
        end
      end)
    end
  end)
end

-------------------------------------------------------------------------------
-- Entrypoint from sqmeow Database Explorer (`ge` and `gE` in sqmeow-drawer)
-------------------------------------------------------------------------------

function M.from_drawer(force_full_schema)
  local drawer = sqmeow 'ui.drawer'
  local state = sqmeow 'core.state'
  local db = require 'utils.database'
  if not drawer or not state then
    return notify('sqmeow drawer is not loaded', vim.log.levels.WARN)
  end

  local node = drawer.current_node and drawer.current_node()

  -- Resolve connection ID and connection metadata from the node under cursor (or active connection)
  local conn_id = node and node.conn_id
  local conn_name = nil

  if node and node.kind == 'database' and node.conn_id then
    -- Cluster child database node
    local parent = state.connections[node.conn_id]
    local child = state.child_connection and state.child_connection(node.conn_id, node.name)
    if child and child.state == 'connected' then
      conn_id = child.id
      conn_name = child.name
    elseif parent then
      conn_name = parent.name .. '/' .. node.name
      conn_id = db.ensure_sqmeow_connection(conn_name, false)
    end
  elseif node and node.kind == 'connection' then
    conn_name = node.name
    if not conn_id or not state.connections[conn_id] or state.connections[conn_id].state ~= 'connected' then
      conn_id = db.ensure_sqmeow_connection(conn_name, false)
    end
  end

  if not conn_id then
    local cur = state.current_connection and state.current_connection()
    if cur and cur.state == 'connected' then
      conn_id = cur.id
      conn_name = cur.name
    elseif db.current_db_name then
      conn_name = db.current_db_name
      conn_id = db.ensure_sqmeow_connection(conn_name, false)
    end
  end

  local conn = conn_id and state.connections[conn_id]
  if not conn or conn.state ~= 'connected' then
    return notify('Please open or select a connected database in the explorer first', vim.log.levels.WARN)
  end
  conn_name = conn.name or conn_name or 'Database'
  local dialect = conn.dialect or 'sql'

  if dialect == 'redis' or dialect == 'mongodb' then
    return notify('ERD generation is only supported for relational/SQL databases', vim.log.levels.WARN)
  end

  -- Determine whether cursor is on a specific table/column vs a schema/connection node
  if node and not force_full_schema then
    local kind = node.kind
    local path = node.path or {}
    if kind == 'table' or kind == 'view' or kind == 'materialized view' or kind == 'relation' then
      local schema = (#path > 1 and path[1]) or ''
      local relation = path[#path] or node.name
      return M.generate_table_erd(conn_id, conn_name, dialect, schema, relation, 1)
    elseif kind == 'column' and #path >= 3 then
      local schema = path[1] or ''
      local relation = path[3]
      return M.generate_table_erd(conn_id, conn_name, dialect, schema, relation, 1)
    end
  end

  -- Otherwise (or when `gE` is pressed), generate the Full Schema ERD
  local target_schema = ''
  if node and node.path and #node.path >= 1 and node.kind ~= 'database' and node.kind ~= 'connection' then
    target_schema = node.path[1] or ''
  end
  M.generate_schema_erd(conn_id, conn_name, dialect, target_schema)
end

return M
