-- lua/utils/sql-objects.lua
-- Fuzzy DB Object Picker (<leader>bf) & Schema-Aware SQL Templates (<leader>bt)
-- powered by sqmeow.api.view.schema() (v3.3.0+).

local M = {}

M._schema_cache = M._schema_cache or {}

local function get_active_conn_id()
  local ok_st, state = pcall(require, 'sqmeow.core.state')
  local ok_db, db = pcall(require, 'utils.database')
  local cur_buf = vim.api.nvim_get_current_buf()

  if ok_db and db then
    local _, db_name = db.get_active_db(cur_buf)
    db_name = db_name or db.current_db_name
    if db_name and db_name ~= '' then
      local cid = db.ensure_sqmeow_connection(db_name, false)
      if cid then
        return cid, db_name
      end
    end
  end

  if ok_st and state and state.current and state.connections[state.current] then
    return state.current, state.connections[state.current].name
  end
  return nil, nil
end

local function load_schema(conn_id, force, callback)
  if not force and M._schema_cache[conn_id] then
    return callback(M._schema_cache[conn_id], nil)
  end
  local ok_v, view_api = pcall(require, 'sqmeow.api.view')
  if not ok_v or not view_api or not view_api.schema then
    return callback(nil, 'sqmeow.api.view.schema() is not available')
  end
  local started, err = view_api.schema({ conn_id = conn_id }, function(schema, s_err)
    vim.schedule(function()
      if schema and schema.tables then
        M._schema_cache[conn_id] = schema
        callback(schema, nil)
      else
        callback(nil, s_err or 'Failed to read schema')
      end
    end)
  end)
  if not started then
    callback(nil, err or 'Could not start schema read')
  end
end

local function quote_ident(dialect, name)
  local ok_sql, sql_mod = pcall(require, 'sqmeow.core.sql')
  if ok_sql and sql_mod and sql_mod.quote then
    return sql_mod.quote(dialect or 'postgres', name)
  end
  return name
end

local function qualified_name(dialect, tbl)
  local rel = quote_ident(dialect, tbl.relation)
  if tbl.schema and tbl.schema ~= '' and tbl.schema ~= 'public' then
    return quote_ident(dialect, tbl.schema) .. '.' .. rel
  end
  return rel
end

local function insert_or_open_sql(sql_text, conn_name, table_name)
  local ed_win = (_G.RightPanel and _G.RightPanel.get_editor_win and _G.RightPanel.get_editor_win()) or vim.api.nvim_get_current_win()
  local cur_buf = (ed_win and vim.api.nvim_win_is_valid(ed_win)) and vim.api.nvim_win_get_buf(ed_win) or vim.api.nvim_get_current_buf()
  local ft = vim.bo[cur_buf].filetype
  local is_sql = (ft == 'sql' or ft == 'mysql' or ft == 'plsql' or vim.b[cur_buf].sqmeow_editor or vim.b[cur_buf].is_preview_buffer)
  local lines = vim.split(sql_text, '\n', { plain = true })

  if is_sql and vim.bo[cur_buf].modifiable and vim.bo[cur_buf].buftype ~= 'terminal' then
    vim.api.nvim_set_current_win(ed_win)
    local row = vim.api.nvim_win_get_cursor(ed_win)[1]
    local cur_line = vim.api.nvim_buf_get_lines(cur_buf, row - 1, row, false)[1] or ''
    if vim.trim(cur_line) == '' then
      vim.api.nvim_buf_set_lines(cur_buf, row - 1, row, false, lines)
    else
      vim.api.nvim_buf_set_lines(cur_buf, row, row, false, vim.list_extend({ '' }, lines))
    end
    return
  end

  -- Otherwise open a fresh editable SQL preview buffer in the main editor window
  local buf = vim.api.nvim_create_buf(true, true)
  local base_name = ('[Template: %s]'):format(table_name or 'query')
  local suffix, count = '', 0
  while not pcall(vim.api.nvim_buf_set_name, buf, base_name .. suffix) do
    count = count + 1
    suffix = (' (%d)'):format(count)
  end
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'hide'
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = 'sql'
  vim.b[buf].is_preview_buffer = true
  if conn_name then
    vim.b[buf].db_name = conn_name
    vim.b[buf].sqmeow_connection = conn_name
  end
  if table_name then
    vim.b[buf].sqmeow_table = table_name
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modified = false

  if ed_win and vim.api.nvim_win_is_valid(ed_win) then
    if vim.fn.exists('&winfixbuf') == 1 then
      vim.wo[ed_win].winfixbuf = false
    end
    vim.api.nvim_win_set_buf(ed_win, buf)
    vim.api.nvim_set_current_win(ed_win)
  end
end

local function build_templates(tbl, dialect)
  local qtbl = qualified_name(dialect, tbl)
  local cols = tbl.columns or {}
  local fks = tbl.foreign_keys or {}

  local pk_cols = {}
  local non_pk_cols = {}
  local all_col_names = {}
  for _, c in ipairs(cols) do
    local qc = quote_ident(dialect, c.name)
    table.insert(all_col_names, qc)
    if c.primary_key then
      table.insert(pk_cols, c)
    else
      table.insert(non_pk_cols, c)
    end
  end

  local templates = {}

  -- 1. Explicit SELECT
  local sel_cols = #all_col_names > 0 and ('  ' .. table.concat(all_col_names, ',\n  ')) or '  *'
  table.insert(templates, {
    name = 'SELECT (explicit columns)',
    desc = ('List all %d columns cleanly'):format(#cols),
    sql = ('SELECT\n%s\nFROM %s\nLIMIT 100;'):format(sel_cols, qtbl),
  })

  -- 2. SELECT + FK JOINs
  if #fks > 0 then
    local join_lines = {}
    local select_lines = { '  t.*' }
    for idx, fk in ipairs(fks) do
      local alias = 'r' .. idx
      local target = fk.target_relation or fk.target or ''
      local target_schema = fk.target_schema or ''
      local qtarget = (target_schema ~= '' and target_schema ~= 'public')
          and (quote_ident(dialect, target_schema) .. '.' .. quote_ident(dialect, target))
        or quote_ident(dialect, target)
      local conds = {}
      for i, fc in ipairs(fk.columns or {}) do
        local rc = (fk.referenced and fk.referenced[i]) or 'id'
        table.insert(conds, ('t.%s = %s.%s'):format(quote_ident(dialect, fc), alias, quote_ident(dialect, rc)))
      end
      table.insert(join_lines, ('LEFT JOIN %s AS %s ON %s'):format(qtarget, alias, table.concat(conds, ' AND ')))
      table.insert(select_lines, ('  %s.*'):format(alias))
    end
    table.insert(templates, {
      name = ('SELECT + Foreign Key JOINs (%d FK%s)'):format(#fks, #fks == 1 and '' or 's'),
      desc = 'Auto-join referenced parent tables using real FKs',
      sql = ('SELECT\n%s\nFROM %s AS t\n%s\nLIMIT 100;'):format(
        table.concat(select_lines, ',\n'),
        qtbl,
        table.concat(join_lines, '\n')
      ),
    })
  end

  -- 3. Parameterized INSERT
  local ins_cols = #non_pk_cols > 0 and non_pk_cols or cols
  local param_headers, ins_names, ins_vals = {}, {}, {}
  for _, c in ipairs(ins_cols) do
    local pname = c.name:gsub('[^%w_]', '_')
    table.insert(param_headers, ('-- @param %s %s'):format(pname, c.type_name or 'text'))
    table.insert(ins_names, '  ' .. quote_ident(dialect, c.name))
    table.insert(ins_vals, '  :' .. pname)
  end
  table.insert(templates, {
    name = 'INSERT (parameterized)',
    desc = 'Insert row with sqmeow -- @param placeholders',
    sql = ('%s\nINSERT INTO %s (\n%s\n)\nVALUES (\n%s\n)\nRETURNING *;'):format(
      table.concat(param_headers, '\n'),
      qtbl,
      table.concat(ins_names, ',\n'),
      table.concat(ins_vals, ',\n')
    ),
  })

  -- 4. PK-Scoped UPDATE
  local set_lines, upd_params, where_lines = {}, {}, {}
  for _, c in ipairs(non_pk_cols) do
    local pname = c.name:gsub('[^%w_]', '_')
    table.insert(upd_params, ('-- @param %s %s'):format(pname, c.type_name or 'text'))
    table.insert(set_lines, ('  %s = :%s'):format(quote_ident(dialect, c.name), pname))
  end
  local where_cols = #pk_cols > 0 and pk_cols or (cols[1] and { cols[1] } or {})
  for _, c in ipairs(where_cols) do
    local pname = c.name:gsub('[^%w_]', '_')
    table.insert(upd_params, ('-- @param %s %s'):format(pname, c.type_name or 'integer'))
    table.insert(where_lines, ('%s = :%s'):format(quote_ident(dialect, c.name), pname))
  end
  if #set_lines > 0 then
    table.insert(templates, {
      name = 'UPDATE (PK-scoped)',
      desc = 'Safe UPDATE pre-scoped to primary key',
      sql = ('%s\nUPDATE %s\nSET\n%s\nWHERE %s\nRETURNING *;'):format(
        table.concat(upd_params, '\n'),
        qtbl,
        table.concat(set_lines, ',\n'),
        table.concat(where_lines, ' AND ')
      ),
    })
  end

  -- 5. PK-Scoped DELETE
  if #where_lines > 0 then
    local del_params = {}
    for _, c in ipairs(where_cols) do
      table.insert(del_params, ('-- @param %s %s'):format(c.name:gsub('[^%w_]', '_'), c.type_name or 'integer'))
    end
    table.insert(templates, {
      name = 'DELETE (PK-scoped)',
      desc = 'Safe DELETE pre-scoped to primary key',
      sql = ('%s\nDELETE FROM %s\nWHERE %s;'):format(table.concat(del_params, '\n'), qtbl, table.concat(where_lines, ' AND ')),
    })
  end

  -- 6. CTE + Window Function
  local order_col = (cols[#cols] and quote_ident(dialect, cols[#cols].name)) or '1'
  local part_col = (fks[1] and fks[1].columns and fks[1].columns[1] and quote_ident(dialect, fks[1].columns[1]))
    or (cols[2] and quote_ident(dialect, cols[2].name))
    or '1'
  table.insert(templates, {
    name = 'CTE + Window Function (ROW_NUMBER)',
    desc = 'Latest-row-per-group scaffold using real columns',
    sql = ('WITH ranked AS (\n  SELECT\n    t.*,\n    ROW_NUMBER() OVER (PARTITION BY t.%s ORDER BY t.%s DESC) AS rn\n  FROM %s AS t\n)\nSELECT *\nFROM ranked\nWHERE rn = 1\nLIMIT 100;'):format(
      part_col,
      order_col,
      qtbl
    ),
  })

  return templates
end

function M.pick_template(target_tbl, conn_id, conn_name, dialect)
  local function show_for_table(tbl, d, cname)
    local templates = build_templates(tbl, d)
    Snacks.picker.select(templates, {
      prompt = ('SQL Template [%s]'):format(tbl.relation),
      format_item = function(item)
        return item.name .. '  —  ' .. item.desc
      end,
    }, function(choice)
      if not choice then
        return
      end
      insert_or_open_sql(choice.sql, cname, tbl.relation)
    end)
  end

  if target_tbl then
    return show_for_table(target_tbl, dialect or 'postgres', conn_name)
  end

  local cid, cname = get_active_conn_id()
  if not cid then
    vim.notify('No active database connection. Connect with <leader>bs first.', vim.log.levels.WARN, { title = 'SQL Templates' })
    return
  end

  load_schema(cid, false, function(schema, err)
    if not schema or not schema.tables or #schema.tables == 0 then
      vim.notify('Could not load schema: ' .. tostring(err or 'empty'), vim.log.levels.WARN, { title = 'SQL Templates' })
      return
    end
    local d = schema.dialect or 'postgres'
    local ok_db, db = pcall(require, 'utils.database')
    local active_tbl = ok_db and db.get_active_table and db.get_active_table() or nil
    if active_tbl then
      for _, t in ipairs(schema.tables) do
        if t.relation:lower() == active_tbl:lower() then
          return show_for_table(t, d, cname)
        end
      end
    end

    Snacks.picker.select(schema.tables, {
      prompt = 'Select Table for SQL Template [' .. (cname or '') .. ']',
      format_item = function(t)
        return ('󰓫 %s (%d cols)'):format(t.relation, #(t.columns or {}))
      end,
    }, function(chosen)
      if chosen then
        show_for_table(chosen, d, cname)
      end
    end)
  end)
end

local function format_table_preview(tbl)
  local lines = {
    '# ' .. (tbl.schema and tbl.schema ~= '' and (tbl.schema .. '.' .. tbl.relation) or tbl.relation),
    '',
    '## Columns',
  }
  local fk_map = {}
  for _, fk in ipairs(tbl.foreign_keys or {}) do
    for i, c in ipairs(fk.columns or {}) do
      local tgt = (fk.target_relation or fk.target or '') .. '.' .. ((fk.referenced and fk.referenced[i]) or '')
      fk_map[c:lower()] = tgt
    end
  end
  for _, c in ipairs(tbl.columns or {}) do
    local badges = {}
    if c.primary_key then
      table.insert(badges, 'PK')
    end
    if fk_map[(c.name or ''):lower()] then
      table.insert(badges, 'FK -> ' .. fk_map[(c.name or ''):lower()])
    end
    if not c.nullable and not c.primary_key then
      table.insert(badges, 'NOT NULL')
    end
    local bstr = #badges > 0 and ('  [' .. table.concat(badges, ', ') .. ']') or ''
    table.insert(lines, string.format('  %-24s %-18s%s', c.name or '', c.type_name or '', bstr))
  end

  if tbl.indexes and #tbl.indexes > 0 then
    table.insert(lines, '')
    table.insert(lines, '## Indexes')
    for _, idx in ipairs(tbl.indexes) do
      local kind = idx.primary and 'PK' or (idx.unique and 'UNIQUE' or 'INDEX')
      table.insert(lines, string.format('  [%s] %s (%s)', kind, idx.name or '', table.concat(idx.columns or {}, ', ')))
    end
  end
  return table.concat(lines, '\n')
end

local function preview_table_in_editor(conn_id, conn_name, dialect, tbl, grid_only)
  local ok_sql, sql_mod = pcall(require, 'sqmeow.core.sql')
  local ok_cfg, cfg = pcall(require, 'sqmeow.config')
  local ok_q, query_api = pcall(require, 'sqmeow.api.query')
  local ok_c, conn_api = pcall(require, 'sqmeow.api.connection')
  if not (ok_sql and ok_q and ok_c) then
    return
  end

  local limit = (ok_cfg and cfg.get().ui.result.page_size) or 1000
  local parts = (tbl.schema and tbl.schema ~= '') and { tbl.schema, tbl.relation } or { tbl.relation }
  local statement = sql_mod.select_from(dialect or 'postgres', parts, limit)
  if not statement then
    return
  end

  conn_api.use(conn_id)
  if not grid_only then
    insert_or_open_sql(statement .. ';', conn_name, tbl.relation)
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

function M.pick_objects(force_refresh)
  local cid, cname = get_active_conn_id()
  if not cid then
    vim.notify('No active database connection. Connect with <leader>bs first.', vim.log.levels.WARN, { title = 'DB Objects' })
    return
  end

  load_schema(cid, force_refresh == true, function(schema, err)
    if not schema or not schema.tables then
      vim.notify('Could not read schema: ' .. tostring(err or 'empty'), vim.log.levels.WARN, { title = 'DB Objects' })
      return
    end

    local dialect = schema.dialect or 'postgres'
    local items = {}
    for _, tbl in ipairs(schema.tables) do
      local preview_text = format_table_preview(tbl)
      table.insert(items, {
        kind = 'table',
        text = ('%s %s'):format(tbl.relation, tbl.schema or ''),
        label = tbl.relation,
        sub = ('%d cols · %d FKs'):format(#(tbl.columns or {}), #(tbl.foreign_keys or {})),
        tbl = tbl,
        preview = { text = preview_text, ft = 'markdown' },
      })
      for _, col in ipairs(tbl.columns or {}) do
        table.insert(items, {
          kind = 'column',
          text = ('%s.%s %s'):format(tbl.relation, col.name, col.type_name or ''),
          label = tbl.relation .. '.' .. col.name,
          sub = col.type_name or '',
          col = col,
          tbl = tbl,
          preview = { text = preview_text, ft = 'markdown' },
        })
      end
    end

    local function act_open_sql(p, item)
      if not item or not item.tbl then
        return
      end
      p:close()
      preview_table_in_editor(cid, cname, dialect, item.tbl, false)
    end
    local function act_grid_peek(p, item)
      if not item or not item.tbl then
        return
      end
      p:close()
      preview_table_in_editor(cid, cname, dialect, item.tbl, true)
    end
    local function act_erd(p, item)
      if not item or not item.tbl then
        return
      end
      p:close()
      require('sqmeow.api.view').diagram({ conn_id = cid, schema = item.tbl.schema, relation = item.tbl.relation })
    end
    local function act_structure(p, item)
      if not item or not item.tbl then
        return
      end
      p:close()
      require('sqmeow.ui.structure').open(cid, item.tbl.schema or '', item.tbl.relation)
    end
    local function act_templates(p, item)
      if not item or not item.tbl then
        return
      end
      p:close()
      M.pick_template(item.tbl, cid, cname, dialect)
    end
    local function act_yank(p, item)
      if not item then
        return
      end
      local val = (item.kind == 'column' and item.col) and item.col.name or item.tbl.relation
      vim.fn.setreg('+', val)
      vim.fn.setreg('"', val)
      p:close()
      vim.notify('Yanked: ' .. val, vim.log.levels.INFO, { title = 'DB Objects' })
    end
    local function act_refresh(p)
      p:close()
      M.pick_objects(true)
    end

    Snacks.picker({
      title = ('DB Objects [%s] — <CR> SQL · M-p Grid · M-e ERD · M-s Struct · M-t Templates · M-y Yank · M-r Refresh'):format(cname or 'db'),
      items = items,
      preview = 'preview',
      format = function(item)
        if item.kind == 'table' then
          return {
            { '󰓫 ', 'Special' },
            { item.label, 'Title' },
            { '  (' .. item.sub .. ')', 'Comment' },
          }
        end
        return {
          { '󰠵 ', 'DiagnosticInfo' },
          { item.label, 'Normal' },
          { '  ' .. item.sub, 'Comment' },
        }
      end,
      confirm = act_open_sql,
      actions = {
        open_sql = act_open_sql,
        grid_peek = act_grid_peek,
        open_erd = act_erd,
        open_structure = act_structure,
        open_templates = act_templates,
        yank_name = act_yank,
        refresh_schema = act_refresh,
      },
      win = {
        input = {
          keys = {
            ['<Tab>'] = { 'list_down', mode = { 'i', 'n' } },
            ['<S-Tab>'] = { 'list_up', mode = { 'i', 'n' } },
            ['<M-p>'] = { 'grid_peek', mode = { 'i', 'n' }, desc = 'Grid Peek' },
            ['<M-e>'] = { 'open_erd', mode = { 'i', 'n' }, desc = 'Open ERD' },
            ['<M-s>'] = { 'open_structure', mode = { 'i', 'n' }, desc = 'Table Structure' },
            ['<M-t>'] = { 'open_templates', mode = { 'i', 'n' }, desc = 'SQL Templates' },
            ['<M-y>'] = { 'yank_name', mode = { 'i', 'n' }, desc = 'Yank Name' },
            ['<M-r>'] = { 'refresh_schema', mode = { 'i', 'n' }, desc = 'Refresh Schema' },
            ['<C-t>'] = { 'open_templates', mode = { 'i', 'n' }, desc = 'SQL Templates' },
            ['<C-e>'] = { 'open_erd', mode = { 'i', 'n' }, desc = 'Open ERD' },
            ['<C-y>'] = { 'yank_name', mode = { 'i', 'n' }, desc = 'Yank Name' },
          },
        },
        list = {
          keys = {
            ['<Tab>'] = { 'list_down', mode = { 'n' } },
            ['<S-Tab>'] = { 'list_up', mode = { 'n' } },
            ['<M-p>'] = { 'grid_peek', mode = { 'n' }, desc = 'Grid Peek' },
            ['<M-e>'] = { 'open_erd', mode = { 'n' }, desc = 'Open ERD' },
            ['<M-s>'] = { 'open_structure', mode = { 'n' }, desc = 'Table Structure' },
            ['<M-t>'] = { 'open_templates', mode = { 'n' }, desc = 'SQL Templates' },
            ['<M-y>'] = { 'yank_name', mode = { 'n' }, desc = 'Yank Name' },
            ['<M-r>'] = { 'refresh_schema', mode = { 'n' }, desc = 'Refresh Schema' },
            ['l'] = { 'open_sql', mode = { 'n' }, desc = 'Open SQL Preview' },
            ['p'] = { 'grid_peek', mode = { 'n' }, desc = 'Grid Peek' },
            ['e'] = { 'open_erd', mode = { 'n' }, desc = 'Open ERD' },
            ['gE'] = { 'open_erd', mode = { 'n' }, desc = 'Open ERD' },
            ['K'] = { 'open_structure', mode = { 'n' }, desc = 'Table Structure' },
            ['t'] = { 'open_templates', mode = { 'n' }, desc = 'SQL Templates' },
            ['y'] = { 'yank_name', mode = { 'n' }, desc = 'Yank Name' },
            ['r'] = { 'refresh_schema', mode = { 'n' }, desc = 'Refresh Schema' },
          },
        },
      },
    })
  end)
end

return M
