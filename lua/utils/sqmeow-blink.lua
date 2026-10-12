--- blink.cmp source provider for intelligent sqmeow database completion.
--- Provides query-aware completions for:
--- 1. SELECT list: all fields for the current table(s) immediately upon typing 'SELECT '
--- 2. Function calls: all columns immediately upon typing 'FUNC(' (AVG, COUNT, SUM, etc.)
--- 3. Clauses: all columns immediately upon typing 'GROUP BY ', 'ORDER BY ', 'WHERE ', etc.
--- 4. FROM / JOIN: all available schemas and top-level tables immediately upon typing space
--- 5. Qualified dots: all tables for 'schema.' and all columns for 'table.' / 'alias.'
--- Database metadata is scored and sorted with top priority over SQL language keywords.
local Source = {}

local blink_kinds = require('blink.cmp.types').CompletionItemKind

local function clean_token(tok)
  if not tok then
    return ''
  end
  return tok:gsub('^[`"\'%[%]]*', ''):gsub('[`"\'%[%]]*$', '')
end

local function parse_relation(tok)
  local s, t = tok:match '^[`"\'%[%]]*([%w_]+)[`"\'%[%]]*%.[`"\'%[%]]*([%w_]+)[`"\'%[%]]*$'
  if s and t then
    return clean_token(s), clean_token(t)
  end
  return nil, clean_token(tok)
end

--- Extract all referenced tables and aliases from buffer text
local function extract_tables(text)
  local tables = {}
  local seen = {}

  local function add(schema, name, alias)
    if not name or name == '' then
      return
    end
    local upper = name:upper()
    if
      upper == 'WHERE'
      or upper == 'SELECT'
      or upper == 'SET'
      or upper == 'GROUP'
      or upper == 'ORDER'
      or upper == 'HAVING'
      or upper == 'LIMIT'
      or upper == 'JOIN'
      or upper == 'ON'
      or upper == 'USING'
      or upper == 'VALUES'
    then
      return
    end

    local key = (schema and (schema .. '.' .. name) or name):lower()
    if not seen[key] then
      seen[key] = true
      table.insert(tables, {
        schema = schema,
        name = name,
        alias = alias and clean_token(alias) or nil,
      })
    end
  end

  -- FROM table [alias]
  for match_str in text:gmatch '[Ff][Rr][Oo][Mm]%s+([%w_%.`"\'%[%]]+[%s%w_`"\'%[%]]*)' do
    local tokens = {}
    for tok in match_str:gmatch '[%w_%.`"\'%[%]]+' do
      table.insert(tokens, tok)
      if #tokens >= 3 then
        break
      end
    end
    if tokens[1] then
      local s, tbl = parse_relation(tokens[1])
      local alias = nil
      if tokens[2] then
        local upper2 = tokens[2]:upper()
        if upper2 == 'AS' and tokens[3] then
          alias = tokens[3]
        elseif
          upper2 ~= 'WHERE'
          and upper2 ~= 'JOIN'
          and upper2 ~= 'LEFT'
          and upper2 ~= 'GROUP'
          and upper2 ~= 'ORDER'
          and upper2 ~= 'LIMIT'
          and upper2 ~= 'INNER'
          and upper2 ~= 'RIGHT'
          and upper2 ~= 'FULL'
          and upper2 ~= 'CROSS'
          and upper2 ~= 'NATURAL'
          and upper2 ~= 'ON'
        then
          alias = tokens[2]
        end
      end
      add(s, tbl, alias)
    end
  end

  -- JOIN table [alias]
  for match_str in text:gmatch '[Jj][Oo][Ii][Nn]%s+([%w_%.`"\'%[%]]+[%s%w_`"\'%[%]]*)' do
    local tokens = {}
    for tok in match_str:gmatch '[%w_%.`"\'%[%]]+' do
      table.insert(tokens, tok)
      if #tokens >= 3 then
        break
      end
    end
    if tokens[1] then
      local s, tbl = parse_relation(tokens[1])
      local alias = nil
      if tokens[2] then
        local upper2 = tokens[2]:upper()
        if upper2 == 'AS' and tokens[3] then
          alias = tokens[3]
        elseif
          upper2 ~= 'ON'
          and upper2 ~= 'USING'
          and upper2 ~= 'WHERE'
          and upper2 ~= 'JOIN'
          and upper2 ~= 'LEFT'
          and upper2 ~= 'INNER'
          and upper2 ~= 'RIGHT'
          and upper2 ~= 'FULL'
          and upper2 ~= 'CROSS'
        then
          alias = tokens[2]
        end
      end
      add(s, tbl, alias)
    end
  end

  -- INTO table
  for match_str in text:gmatch '[Ii][Nn][Tt][Oo]%s+([%w_%.`"\'%[%]]+)' do
    local s, tbl = parse_relation(match_str)
    add(s, tbl)
  end

  -- UPDATE table
  for match_str in text:gmatch '[Uu][Pp][Dd][Aa][Tt][Ee]%s+([%w_%.`"\'%[%]]+)' do
    local s, tbl = parse_relation(match_str)
    add(s, tbl)
  end

  return tables
end

--- Detect the syntactic SQL context at cursor
local function detect_sql_context(before)
  -- Guard line comments (-- ...)
  if before:match '%-%-' then
    return { type = 'ignore' }
  end
  -- Guard open string literals ('...)
  local quotes = select(2, before:gsub("'", ''))
  if quotes % 2 == 1 then
    return { type = 'ignore' }
  end

  -- 1. Qualified prefix: <qualifier>.
  local qual = before:match '([%w_`"\'%[%]]+)%.[%w_`"\'%[%]]*$'
  if qual then
    return { type = 'qualifier', qualifier = clean_token(qual) }
  end

  -- 2. Relation position: immediately after FROM, JOIN, INTO (with space)
  if
    before:match '[Ff][Rr][Oo][Mm]%s+[%w_`"\'%[%]]*$'
    or before:match '[Jj][Oo][Ii][Nn]%s+[%w_`"\'%[%]]*$'
    or before:match '[Ii][Nn][Tt][Oo]%s+[%w_`"\'%[%]]*$'
  then
    return { type = 'relation' }
  end

  -- 3. Inside function call: e.g. AVG(, COUNT(, SUM(, COALESCE(, etc.
  local func_name = before:match '([%w_]+)%s*%([^()]*$'
  if func_name then
    return { type = 'function_arg', func = func_name }
  end

  -- 4. Clauses requiring columns: GROUP BY, ORDER BY, WHERE, HAVING, ON, SET, AND, OR
  if
    before:match '[Gg][Rr][Oo][Uu][Pp]%s+[Bb][Yy]%s+.*$'
    or before:match '[Oo][Rr][Dd][Ee][Rr]%s+[Bb][Yy]%s+.*$'
    or before:match '[Ww][Hh][Ee][Rr][Ee]%s+.*$'
    or before:match '[Hh][Aa][Vv][Ii][Nn][Gg]%s+.*$'
    or before:match '[Oo][Nn]%s+.*$'
    or before:match '[Ss][Ee][Tt]%s+.*$'
    or before:match '%f[%w][Aa][Nn][Dd]%s+.*$'
    or before:match '%f[%w][Oo][Rr]%s+.*$'
  then
    return { type = 'column' }
  end

  -- 5. SELECT list: immediately after SELECT (with space) or after a comma in SELECT
  if before:match '[Ss][Ee][Ll][Ee][Cc][Tt]%s+.*$' then
    return { type = 'select_list' }
  end

  -- 6. Space pressed after non-SQL token
  if before:match '%s$' then
    return { type = 'ignore' }
  end

  return { type = 'general' }
end

--- Get cached nodes from sqmeow drawer, loading on demand with quick synchronous wait
local function get_drawer_nodes(drawer, conn_id, path)
  local cached = drawer.cached_nodes(conn_id, path)
  if cached == nil then
    drawer.load(conn_id, path, false)
    vim.wait(150, function()
      return drawer.cached_nodes(conn_id, path) ~= nil
    end, 5)
    cached = drawer.cached_nodes(conn_id, path)
  end
  return cached
end

--- Gather all available relations and schemas for an open sqmeow connection
local function get_relations(drawer, conn_id)
  local result, incomplete = {}, false
  local schemas = get_drawer_nodes(drawer, conn_id, {})
  if not schemas then
    return result, true, {}
  end

  for _, schema in ipairs(schemas) do
    if schema.kind == 'schema' then
      local groups = get_drawer_nodes(drawer, conn_id, { schema.name })
      incomplete = incomplete or groups == nil
      for _, group in ipairs(groups or {}) do
        if group.kind == 'tables' or group.kind == 'views' or group.kind == 'keys' then
          local path = { schema.name, group.key }
          local members = get_drawer_nodes(drawer, conn_id, path)
          incomplete = incomplete or members == nil
          for _, relation in ipairs(members or {}) do
            table.insert(result, {
              schema = schema.name,
              node = relation,
              path = { schema.name, group.key, relation.name },
            })
          end
        end
      end
    end
  end
  return result, incomplete, schemas
end

function Source.new()
  return setmetatable({}, { __index = Source })
end

--- Immediate triggers: space after keywords, open paren for functions, dot for qualifiers
function Source:get_trigger_characters()
  return { '.', '"', '`', '[', ' ', '(', ',' }
end

function Source:enabled()
  local ft = vim.bo.filetype
  return ft == 'sql' or ft == 'mysql' or ft == 'plsql'
end

function Source:get_completions(context, callback)
  local bufnr = context.bufnr
  local line = context.line or ''
  local col = context.cursor[2] or 0
  local before = line:sub(1, col)

  local ctx = detect_sql_context(before)
  if ctx.type == 'ignore' then
    return callback { items = {}, is_incomplete_backward = false, is_incomplete_forward = false }
  end

  local ok_conn, conn_api = pcall(require, 'sqmeow.api.connection')
  if not ok_conn then
    return callback { items = {}, is_incomplete_backward = false, is_incomplete_forward = false }
  end

  local conn = conn_api.target(bufnr)
  if not conn then
    local ok_state, state = pcall(require, 'sqmeow.core.state')
    if ok_state and state.current_connection then
      conn = state.current_connection()
    end
  end
  if not conn then
    return callback { items = {}, is_incomplete_backward = false, is_incomplete_forward = false }
  end

  local ok_drawer, drawer = pcall(require, 'sqmeow.ui.drawer')
  if not ok_drawer then
    return callback { items = {}, is_incomplete_backward = false, is_incomplete_forward = false }
  end

  local available, incomplete, schemas = get_relations(drawer, conn.id)
  local items = {}
  local seen = {}

  local function add_item(label, kind, detail, score, doc)
    local key = label .. ':' .. tostring(kind)
    if not seen[key] then
      seen[key] = true
      table.insert(items, {
        label = label,
        kind = kind,
        detail = detail,
        score_offset = score or 200,
        documentation = doc and { kind = 'markdown', value = doc } or nil,
      })
    end
  end

  -- Read full buffer lines for table extraction
  local all_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local buffer_text = table.concat(all_lines, '\n')
  local tables = extract_tables(buffer_text)

  -- Resolve buffer-associated table fallback
  local buf_table = vim.b[bufnr].sqmeow_table
  if not buf_table then
    local bname = vim.api.nvim_buf_get_name(bufnr)
    local preview_tbl = bname:match '%[Preview:%s*([^%(%]]+)'
    if preview_tbl then
      buf_table = vim.trim(preview_tbl)
      vim.b[bufnr].sqmeow_table = buf_table
    end
  end
  if not buf_table and drawer.current_node then
    local node = drawer.current_node()
    if node and (node.kind == 'table' or node.kind == 'view') then
      buf_table = node.name
    end
  end

  if #tables == 0 and buf_table then
    table.insert(tables, { name = buf_table })
  end

  -- Case A: Cursor in FROM / JOIN / INTO position -> Schemas & Tables
  if ctx.type == 'relation' then
    -- 1. All database schemas
    for _, s in ipairs(schemas or {}) do
      if s.kind == 'schema' then
        add_item(s.name, blink_kinds.Module, 'schema', 250)
      end
    end
    -- 2. Tables and views in default schema
    for _, r in ipairs(available) do
      local rel, schema = r.node, r.schema
      local kind = rel.kind == 'view' and blink_kinds.Interface or blink_kinds.Class
      if schema:lower() == 'public' or schema:lower() == 'main' or not schemas or #schemas <= 1 then
        add_item(rel.name, kind, rel.kind, 240)
      else
        add_item(schema .. '.' .. rel.name, kind, schema .. '.' .. rel.kind, 230)
      end
    end

  -- Case B: Cursor after <qualifier>. -> Tables for schema, Columns for table/alias
  elseif ctx.type == 'qualifier' then
    local qual = ctx.qualifier:lower()
    local matched_schema = false

    -- 1. Check if qualifier is a schema name
    for _, s in ipairs(schemas or {}) do
      if s.kind == 'schema' and s.name:lower() == qual then
        matched_schema = true
        for _, r in ipairs(available) do
          if r.schema:lower() == qual then
            local kind = r.node.kind == 'view' and blink_kinds.Interface or blink_kinds.Class
            add_item(r.node.name, kind, r.node.kind, 250)
          end
        end
        break
      end
    end

    -- 2. If not a schema, resolve as a table name or table alias
    if not matched_schema then
      local target_relations = {}
      for _, t in ipairs(tables) do
        if (t.alias and t.alias:lower() == qual) or (t.name:lower() == qual) then
          for _, r in ipairs(available) do
            if r.node.name:lower() == t.name:lower() and (not t.schema or r.schema:lower() == t.schema:lower()) then
              table.insert(target_relations, r)
            end
          end
        end
      end

      -- If no match in parsed tables, check all available relations directly
      if #target_relations == 0 then
        for _, r in ipairs(available) do
          if r.node.name:lower() == qual then
            table.insert(target_relations, r)
          end
        end
      end

      for _, rel in ipairs(target_relations) do
        if rel.node.expandable ~= false then
          local columns = get_drawer_nodes(drawer, conn.id, rel.path)
          incomplete = incomplete or columns == nil
          for _, col in ipairs(columns or {}) do
            if col.kind == 'column' then
              local doc = {}
              if col.primary_key then
                table.insert(doc, 'Primary Key')
              end
              if col.references then
                table.insert(doc, 'Foreign Key: ' .. col.references)
              end
              local doc_str = #doc > 0 and table.concat(doc, ', ') or nil
              add_item(col.name, blink_kinds.Field, col.type_name, 250, doc_str)
            end
          end
        end
      end
    end

  -- Case C: SELECT list, function argument (AVG, COUNT), or column clause (WHERE, GROUP BY, ORDER BY)
  elseif ctx.type == 'select_list' or ctx.type == 'function_arg' or ctx.type == 'column' then
    if ctx.type == 'select_list' then
      add_item('*', blink_kinds.Field, 'all columns', 260)
    end

    -- Find matching relations for the referenced table(s)
    local target_relations = {}
    if #tables > 0 then
      for _, t in ipairs(tables) do
        for _, r in ipairs(available) do
          if r.node.name:lower() == t.name:lower() and (not t.schema or r.schema:lower() == t.schema:lower()) then
            table.insert(target_relations, { relation = r, alias = t.alias })
          end
        end
      end
    end

    -- Fallback: if no specific table was found in query/buffer, gather all relations in default schema
    if #target_relations == 0 then
      for _, r in ipairs(available) do
        if r.schema:lower() == 'public' or r.schema:lower() == 'main' or not schemas or #schemas <= 1 then
          table.insert(target_relations, { relation = r, alias = nil })
        end
      end
    end

    local multi = #target_relations > 1
    for _, item_rel in ipairs(target_relations) do
      local rel = item_rel.relation
      local alias = item_rel.alias
      if rel.node.expandable ~= false then
        local columns = get_drawer_nodes(drawer, conn.id, rel.path)
        incomplete = incomplete or columns == nil
        for _, col in ipairs(columns or {}) do
          if col.kind == 'column' then
            local doc = {}
            if col.primary_key then
              table.insert(doc, 'Primary Key')
            end
            if col.references then
              table.insert(doc, 'Foreign Key: ' .. col.references)
            end
            local doc_str = #doc > 0 and table.concat(doc, ', ') or nil

            local detail = multi and (rel.node.name .. ' (' .. col.type_name .. ')') or col.type_name
            add_item(col.name, blink_kinds.Field, detail, 250, doc_str)

            if multi then
              local pfx = alias or rel.node.name
              add_item(pfx .. '.' .. col.name, blink_kinds.Field, col.type_name, 240, doc_str)
            end
          end
        end
      end
    end

  -- Case D: General context fallback
  else
    for _, s in ipairs(schemas or {}) do
      if s.kind == 'schema' then
        add_item(s.name, blink_kinds.Module, 'schema', 180)
      end
    end
    for _, r in ipairs(available) do
      local kind = r.node.kind == 'view' and blink_kinds.Interface or blink_kinds.Class
      add_item(r.node.name, kind, r.node.kind, 200)
    end
  end

  callback {
    items = items,
    is_incomplete_backward = incomplete,
    is_incomplete_forward = incomplete,
  }
end

return Source
