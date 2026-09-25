--- Custom intelligent blink.cmp provider for vim-dadbod-completion
--- Prioritizes schemas, tables, and columns based on precise SQL query context:
--- - After <schema>. (e.g. "public".), tables are prioritized first with kind:7 (Class) and description: 'table'.
--- - Inside FROM / JOIN, tables are prioritized over columns and keywords.
--- - Inside SELECT / WHERE, columns of the active/open table are prioritized at the top.
local M = {}

--- Extract active table names from buffer variables and SQL query text
local function extract_active_tables(bufnr)
  local tables = {}

  local function add_tbl(name)
    if not name or name == '' then return end
    name = name:gsub('["`]', '')
    local short = name:match('([^.]+)$')
    if short and short ~= '' then
      tables[short:lower()] = true
    end
    tables[name:lower()] = true
  end

  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return tables
  end

  -- 1. Parse buffer text for SQL clauses: FROM, JOIN, UPDATE, INTO, TABLE
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local full_text = table.concat(lines, ' ')
  full_text = full_text:gsub('/%*.-%*/', ' ')
  full_text = full_text:gsub('%-%-[^\n]*', ' ')
  local lower_text = full_text:lower()

  -- FROM clause (single table or comma-separated tables)
  for from_clause in lower_text:gmatch('%f[%w]from%s+([%w_%.`",%s]+)') do
    local tables_part = from_clause:match('^([^;]+)') or from_clause
    tables_part = tables_part:gsub('%f[%w]where%f[%W].*$', '')
    tables_part = tables_part:gsub('%f[%w]group%f[%W].*$', '')
    tables_part = tables_part:gsub('%f[%w]order%f[%W].*$', '')
    tables_part = tables_part:gsub('%f[%w]limit%f[%W].*$', '')
    tables_part = tables_part:gsub('%f[%w]having%f[%W].*$', '')
    tables_part = tables_part:gsub('%f[%w]join%f[%W].*$', '')
    for part in tables_part:gmatch('[^,]+') do
      local tbl = part:match('^%s*([%w_%.`"]+)')
      if tbl and tbl ~= 'select' then add_tbl(tbl) end
    end
  end

  -- JOIN clause (LEFT JOIN, RIGHT JOIN, INNER JOIN, etc.)
  for t in lower_text:gmatch('%f[%w]join%s+([%w_%.`"]+)') do
    add_tbl(t)
  end

  -- UPDATE clause
  for t in lower_text:gmatch('%f[%w]update%s+([%w_%.`"]+)') do
    add_tbl(t)
  end

  -- INTO clause (INSERT INTO ...)
  for t in lower_text:gmatch('%f[%w]into%s+([%w_%.`"]+)') do
    add_tbl(t)
  end

  -- TABLE clause (TRUNCATE TABLE, TABLE ...)
  for t in lower_text:gmatch('%f[%w]table%s+([%w_%.`"]+)') do
    add_tbl(t)
  end

  -- 2. ONLY if no tables were found in the query text, fall back to buffer variable or filename stem
  if next(tables) == nil then
    local ok_tbl, b_table = pcall(function()
      return vim.b[bufnr].sqmeow_table
    end)
    if ok_tbl and b_table and b_table ~= '' then
      add_tbl(b_table)
    end

    local bname = vim.api.nvim_buf_get_name(bufnr)
    if bname and bname ~= '' then
      local stem = vim.fn.fnamemodify(bname, ':t:r')
      if stem and stem ~= '' and stem ~= 'first_1000' and stem ~= 'scratch' and not stem:find('^query_') then
        add_tbl(stem)
      end
    end
  end

  return tables
end

function M.new()
  return setmetatable({}, { __index = M })
end

function M:get_trigger_characters()
  return { '"', '`', '[', ']', '.' }
end

function M:enabled()
  local filetypes = { 'sql', 'mysql', 'plsql' }
  return vim.tbl_contains(filetypes, vim.bo.filetype)
end

function M:get_completions(ctx, callback)
  local cursor_col = ctx.cursor[2]
  local line = ctx.line or ''
  local before_cursor = line:sub(1, cursor_col)

  -- Check if cursor is immediately after a dot (e.g. "public". or users.)
  local dot_prefix, dot_word = before_cursor:match('([%w_%.`"]+)%.%s*([%w_]*)$')
  local is_dot = dot_prefix ~= nil
  local clean_prefix = is_dot and dot_prefix:gsub('["`]', ''):lower() or ''

  -- Check if cursor is in a FROM, JOIN, INTO, or UPDATE clause
  local is_from_clause = before_cursor:lower():match('%f[%w]from%s+[%w_`"]*$')
    or before_cursor:lower():match('%f[%w]join%s+[%w_`"]*$')
    or before_cursor:lower():match('%f[%w]into%s+[%w_`"]*$')
    or before_cursor:lower():match('%f[%w]update%s+[%w_`"]*$')

  local word_start = cursor_col + 1
  local triggers = self:get_trigger_characters()
  while word_start > 1 do
    local char = line:sub(word_start - 1, word_start - 1)
    if vim.tbl_contains(triggers, char) or char:match('%s') then
      break
    end
    word_start = word_start - 1
  end

  local input = line:sub(word_start, cursor_col)
  if input ~= '' and input:match('[^0-9A-Za-z_]+') then
    input = ''
  end

  local transformed_callback = function(items)
    callback({
      context = ctx,
      is_incomplete_forward = true,
      is_incomplete_backward = true,
      items = items,
    })
  end

  local results = vim.api.nvim_call_function('vim_dadbod_completion#omni', { 0, input })
  if not results or #results == 0 then
    transformed_callback({})
    return function() end
  end

  -- Determine if dot_prefix represents a database schema
  local is_schema_prefix = clean_prefix == 'public'
    or clean_prefix == 'pg_catalog'
    or clean_prefix == 'information_schema'

  if is_dot and not is_schema_prefix then
    -- If dadbod omni returns tables for this dot prefix, it's definitely a schema
    for _, it in ipairs(results) do
      if it.kind == 'T' then
        is_schema_prefix = true
        break
      end
    end
  end

  local bufnr = ctx.bufnr
  local active_tables = extract_active_tables(bufnr)
  local has_active = next(active_tables) ~= nil

  local items = {}
  local seen_keys = {}
  local active_cols = {}
  local other_cols = {}

  for _, item in ipairs(results) do
    local word = item.abbr or item.word
    local kind_code = item.kind

    if is_schema_prefix then
      -- 1. Typing after a schema (e.g. "public".):
      -- Return ONLY tables / views (and functions), prioritized at the very top.
      if kind_code == 'T' then
        local key = 'table_' .. word
        if not seen_keys[key] then
          seen_keys[key] = true
          table.insert(items, {
            label = word,
            insertText = item.word,
            kind = 7, -- Class (Table)
            score_offset = 500,
            labelDetails = { description = 'table' },
            documentation = item.info or '',
            source_id = 'dadbod',
            source_name = 'Dadbod',
            cursor_column = cursor_col,
          })
        end
      elseif kind_code == 'F' then
        local key = 'fn_' .. word
        if not seen_keys[key] then
          seen_keys[key] = true
          table.insert(items, {
            label = word,
            insertText = item.word,
            kind = 3, -- Function
            score_offset = 200,
            labelDetails = { description = 'function' },
            documentation = item.info or '',
            source_id = 'dadbod',
            source_name = 'Dadbod',
            cursor_column = cursor_col,
          })
        end
      end

    elseif is_dot then
      -- 2. Typing after a table or alias (e.g. orders. or u.):
      -- Return ONLY columns of that specific table/alias.
      if kind_code == 'C' then
        local key = 'col_' .. word
        if not seen_keys[key] then
          seen_keys[key] = true
          local doc = item.info or ''
          local tbl = doc:match('^(.-)%s+table column$')
          local short_tbl = tbl and tbl:match('([^.]+)$')
          table.insert(items, {
            label = word,
            insertText = item.word,
            kind = 5, -- Field (Column)
            score_offset = 500,
            labelDetails = { description = '★ ' .. (short_tbl or tbl or clean_prefix) },
            documentation = doc,
            source_id = 'dadbod',
            source_name = 'Dadbod',
            cursor_column = cursor_col,
          })
        end
      end

    else
      -- 3. General SQL completion (no dot)
      if kind_code == 'T' then
        -- Table candidate
        local is_system = word:match('^pg_') or word:match('^sql_') or word:match('^information_schema')
        local is_active = active_tables[word:lower()]
        local score = is_from_clause and (is_active and 400 or (is_system and -50 or 350))
          or (is_active and 180 or (is_system and -60 or 80))

        local key = 'table_' .. word
        if not seen_keys[key] then
          seen_keys[key] = true
          table.insert(items, {
            label = word,
            insertText = item.word,
            kind = 7, -- Class (Table)
            score_offset = score,
            labelDetails = { description = is_system and 'system table' or 'table' },
            documentation = item.info or '',
            source_id = 'dadbod',
            source_name = 'Dadbod',
            cursor_column = cursor_col,
          })
        end

      elseif kind_code == 'S' then
        -- Schema candidate (e.g. public, pg_catalog)
        local key = 'schema_' .. word
        if not seen_keys[key] then
          seen_keys[key] = true
          table.insert(items, {
            label = word,
            insertText = item.word,
            kind = 19, -- Folder (Schema)
            score_offset = is_from_clause and 320 or 50,
            labelDetails = { description = 'schema' },
            documentation = item.info or '',
            source_id = 'dadbod',
            source_name = 'Dadbod',
            cursor_column = cursor_col,
          })
        end

      elseif kind_code == 'C' then
        -- Column candidate
        local doc = item.info or ''
        local tbl = doc:match('^(.-)%s+table column$')
        local short_tbl = tbl and tbl:match('([^.]+)$')
        local is_active = tbl and (active_tables[tbl:lower()] or (short_tbl and active_tables[short_tbl:lower()]))
        local is_system = tbl and (tbl:match('^pg_') or tbl:match('^information_schema'))

        if is_active then
          local key = word .. '_' .. (short_tbl or tbl)
          if not active_cols[key] then
            active_cols[key] = {
              label = word,
              insertText = item.word,
              kind = 5,
              score_offset = is_from_clause and -60 or 350,
              labelDetails = { description = '★ ' .. (short_tbl or tbl) },
              documentation = doc,
              source_id = 'dadbod',
              source_name = 'Dadbod',
              cursor_column = cursor_col,
            }
          end
        elseif not is_system then
          local key = word .. (tbl and ('_' .. tbl) or '')
          if not other_cols[key] then
            other_cols[key] = {
              label = word,
              insertText = item.word,
              kind = 5,
              score_offset = is_from_clause and -80 or (has_active and -40 or 60),
              labelDetails = { description = short_tbl or tbl or item.menu or 'column' },
              documentation = doc,
              source_id = 'dadbod',
              source_name = 'Dadbod',
              cursor_column = cursor_col,
            }
          end
        end

      elseif kind_code == 'R' then
        -- Reserved word / Keyword
        local key_upper = 'kw_' .. word:upper()
        if not seen_keys[key_upper] then
          seen_keys[key_upper] = true
          table.insert(items, {
            label = word:upper(),
            insertText = item.word:upper(),
            kind = 14,
            score_offset = 40,
            labelDetails = { description = 'SQL command' },
            source_id = 'dadbod',
            source_name = 'Dadbod',
            cursor_column = cursor_col,
          })
        end
        local key_lower = 'kw_' .. word:lower()
        if not seen_keys[key_lower] then
          seen_keys[key_lower] = true
          table.insert(items, {
            label = word:lower(),
            insertText = item.word:lower(),
            kind = 14,
            score_offset = 40,
            labelDetails = { description = 'SQL command' },
            source_id = 'dadbod',
            source_name = 'Dadbod',
            cursor_column = cursor_col,
          })
        end

      elseif kind_code == 'A' then
        -- Alias
        local key = 'alias_' .. word
        if not seen_keys[key] then
          seen_keys[key] = true
          table.insert(items, {
            label = word,
            insertText = item.word,
            kind = 6,
            score_offset = 120,
            labelDetails = { description = item.info or 'alias' },
            source_id = 'dadbod',
            source_name = 'Dadbod',
            cursor_column = cursor_col,
          })
        end

      elseif kind_code == 'F' then
        -- Function
        local key = 'fn_' .. word
        if not seen_keys[key] then
          seen_keys[key] = true
          table.insert(items, {
            label = word,
            insertText = item.word,
            kind = 3,
            score_offset = 30,
            labelDetails = { description = 'function' },
            source_id = 'dadbod',
            source_name = 'Dadbod',
            cursor_column = cursor_col,
          })
        end
      end
    end
  end

  -- Add active table columns first
  for _, col in pairs(active_cols) do
    table.insert(items, col)
  end

  -- Add other columns
  for _, col in pairs(other_cols) do
    table.insert(items, col)
  end

  -- Inject common multi-word SQL clauses ONLY when not completing after a dot
  if not is_dot then
    local phrases = {
      { 'SELECT', 'SQL command' },
      { 'select', 'SQL command' },
      { 'FROM', 'SQL clause' },
      { 'from', 'SQL clause' },
      { 'WHERE', 'SQL clause' },
      { 'where', 'SQL clause' },
      { 'INSERT INTO', 'SQL statement' },
      { 'insert into', 'SQL statement' },
      { 'UPDATE', 'SQL statement' },
      { 'update', 'SQL statement' },
      { 'DELETE FROM', 'SQL statement' },
      { 'delete from', 'SQL statement' },
      { 'LEFT JOIN', 'SQL join' },
      { 'left join', 'SQL join' },
      { 'INNER JOIN', 'SQL join' },
      { 'inner join', 'SQL join' },
      { 'RIGHT JOIN', 'SQL join' },
      { 'right join', 'SQL join' },
      { 'GROUP BY', 'SQL clause' },
      { 'group by', 'SQL clause' },
      { 'ORDER BY', 'SQL clause' },
      { 'order by', 'SQL clause' },
      { 'HAVING', 'SQL clause' },
      { 'having', 'SQL clause' },
      { 'LIMIT', 'SQL clause' },
      { 'limit', 'SQL clause' },
      { 'OFFSET', 'SQL clause' },
      { 'offset', 'SQL clause' },
      { 'CREATE TABLE', 'SQL DDL' },
      { 'create table', 'SQL DDL' },
      { 'ALTER TABLE', 'SQL DDL' },
      { 'alter table', 'SQL DDL' },
      { 'DROP TABLE', 'SQL DDL' },
      { 'drop table', 'SQL DDL' },
      { 'PRIMARY KEY', 'SQL constraint' },
      { 'primary key', 'SQL constraint' },
      { 'FOREIGN KEY', 'SQL constraint' },
      { 'foreign key', 'SQL constraint' },
      { 'REFERENCES', 'SQL constraint' },
      { 'references', 'SQL constraint' },
      { 'RETURNING', 'SQL clause' },
      { 'returning', 'SQL clause' },
      { 'ON CONFLICT', 'SQL clause' },
      { 'on conflict', 'SQL clause' },
      { 'COUNT(*)', 'SQL function' },
      { 'count(*)', 'SQL function' },
    }

    for _, p in ipairs(phrases) do
      local key = 'phrase_' .. p[1]
      if not seen_keys[key] then
        seen_keys[key] = true
        table.insert(items, {
          label = p[1],
          insertText = p[1],
          kind = 14,
          source_id = 'dadbod',
          source_name = 'Dadbod',
          cursor_column = cursor_col,
          labelDetails = { description = p[2] },
          score_offset = 100,
        })
      end
    end
  end

  -- Defensive normalization loop
  for _, it in ipairs(items) do
    it.source_id = it.source_id or 'dadbod'
    it.source_name = it.source_name or 'Dadbod'
    it.cursor_column = it.cursor_column or cursor_col
  end

  transformed_callback(items)
  return function() end
end

return M
