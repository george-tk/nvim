--- Standalone blink.cmp provider for SQL keywords, clauses, and boilerplate phrases.
--- Provides fast, zero-dependency completion for standard SQL syntax.
--- Database metadata (schemas, tables, views, columns) is handled natively by sqmeow.
local M = {}

local KEYWORDS = {
  -- DDL / DML commands & statements
  'SELECT',
  'FROM',
  'WHERE',
  'INSERT INTO',
  'INSERT',
  'INTO',
  'VALUES',
  'UPDATE',
  'SET',
  'DELETE FROM',
  'DELETE',
  'TRUNCATE TABLE',
  'TRUNCATE',
  'CREATE TABLE',
  'CREATE VIEW',
  'CREATE INDEX',
  'CREATE OR REPLACE VIEW',
  'ALTER TABLE',
  'DROP TABLE',
  'DROP VIEW',
  'DROP INDEX',
  -- Joins
  'JOIN',
  'INNER JOIN',
  'LEFT JOIN',
  'LEFT OUTER JOIN',
  'RIGHT JOIN',
  'RIGHT OUTER JOIN',
  'FULL JOIN',
  'FULL OUTER JOIN',
  'CROSS JOIN',
  'NATURAL JOIN',
  'ON',
  'USING',
  -- Grouping & ordering & windowing
  'GROUP BY',
  'ORDER BY',
  'HAVING',
  'LIMIT',
  'OFFSET',
  'OVER',
  'PARTITION BY',
  'ASC',
  'DESC',
  'NULLS FIRST',
  'NULLS LAST',
  -- Set operations & conditionals
  'UNION',
  'UNION ALL',
  'INTERSECT',
  'EXCEPT',
  'DISTINCT',
  'CASE',
  'WHEN',
  'THEN',
  'ELSE',
  'END',
  'AS',
  -- Logic & comparisons
  'AND',
  'OR',
  'NOT',
  'IN',
  'IS NULL',
  'IS NOT NULL',
  'IS',
  'NULL',
  'LIKE',
  'ILIKE',
  'NOT LIKE',
  'BETWEEN',
  'EXISTS',
  'NOT EXISTS',
  -- Constraints & DDL modifiers
  'PRIMARY KEY',
  'FOREIGN KEY',
  'REFERENCES',
  'CONSTRAINT',
  'DEFAULT',
  'UNIQUE',
  'CHECK',
  'NOT NULL',
  'CASCADE',
  'RESTRICT',
  -- Upsert & transactions
  'ON CONFLICT',
  'DO NOTHING',
  'DO UPDATE',
  'RETURNING',
  'BEGIN',
  'COMMIT',
  'ROLLBACK',
  'TRANSACTION',
  'SAVEPOINT',
  -- Diagnostics
  'EXPLAIN',
  'EXPLAIN ANALYZE',
  'EXPLAIN QUERY PLAN',
}

local FUNCTIONS = {
  'COUNT(*)',
  'COUNT',
  'SUM',
  'AVG',
  'MIN',
  'MAX',
  'COALESCE',
  'NULLIF',
  'NOW()',
  'CURRENT_TIMESTAMP',
  'ROUND',
  'LOWER',
  'UPPER',
  'TRIM',
  'SUBSTRING',
  'CONCAT',
  'LENGTH',
  'CAST',
  'DATE_TRUNC',
  'GEN_RANDOM_UUID()',
}

local SELECT_EXPR_KEYWORDS = {
  'DISTINCT',
  'CASE',
  'WHEN',
  'THEN',
  'ELSE',
  'END',
  'AS',
  'CAST',
  'COALESCE',
  'NULLIF',
}

local all_items_cache = nil
local select_items_cache = nil

local function get_all_items()
  if all_items_cache then
    return all_items_cache
  end
  local items = {}
  local seen = {}

  local function add(label, kind, desc, score)
    if not seen[label] then
      seen[label] = true
      table.insert(items, {
        label = label,
        kind = kind,
        score_offset = score or 30,
        labelDetails = { description = desc },
      })
    end
  end

  -- Only canonical uppercase - eliminates duplicate 'sql' vs 'SQL' entries
  for _, kw in ipairs(KEYWORDS) do
    add(kw, 14, 'SQL', 20)
  end

  for _, fn in ipairs(FUNCTIONS) do
    add(fn, 3, 'Function', 25)
  end

  all_items_cache = items
  return all_items_cache
end

local function get_select_items()
  if select_items_cache then
    return select_items_cache
  end
  local items = {}
  local seen = {}

  local function add(label, kind, desc, score)
    if not seen[label] then
      seen[label] = true
      table.insert(items, {
        label = label,
        kind = kind,
        score_offset = score or 20,
        labelDetails = { description = desc },
      })
    end
  end

  for _, fn in ipairs(FUNCTIONS) do
    add(fn, 3, 'Function', 25)
  end

  for _, kw in ipairs(SELECT_EXPR_KEYWORDS) do
    add(kw, 14, 'SQL', 20)
  end

  select_items_cache = items
  return select_items_cache
end

function M.new()
  return setmetatable({}, { __index = M })
end

function M:get_trigger_characters()
  return { ' ' }
end

function M:enabled()
  local ft = vim.bo.filetype
  return ft == 'sql' or ft == 'mysql' or ft == 'plsql'
end

function M:get_completions(context, callback)
  local line = context.line or ''
  local col = context.cursor[2] or 0
  local before = line:sub(1, col)

  -- Guard comments and string literals
  if before:match '%-%-' then
    return callback { items = {}, is_incomplete_forward = false, is_incomplete_backward = false }
  end
  local quotes = select(2, before:gsub("'", ''))
  if quotes % 2 == 1 then
    return callback { items = {}, is_incomplete_forward = false, is_incomplete_backward = false }
  end

  -- If cursor is immediately after a dot (e.g. "users.", "public."),
  -- do NOT suggest SQL keywords; let sqmeow handle columns and tables exclusively.
  if before:match '[%w_%.`"]+%.%s*[%w_]*$' then
    return callback { items = {}, is_incomplete_forward = false, is_incomplete_backward = false }
  end

  -- If cursor is in FROM / JOIN / INTO position, do NOT suggest statement keywords;
  -- schemas and tables have exclusive priority.
  if
    before:match '[Ff][Rr][Oo][Mm]%s+[%w_`"\'%[%]]*$'
    or before:match '[Jj][Oo][Ii][Nn]%s+[%w_`"\'%[%]]*$'
    or before:match '[Ii][Nn][Tt][Oo]%s+[%w_`"\'%[%]]*$'
  then
    return callback { items = {}, is_incomplete_forward = false, is_incomplete_backward = false }
  end

  -- If cursor is inside a function call (e.g. AVG(, COUNT(), do NOT suggest statement keywords;
  -- columns have exclusive priority.
  if before:match '([%w_]+)%s*%([^()]*$' then
    return callback { items = {}, is_incomplete_forward = false, is_incomplete_backward = false }
  end

  -- If cursor is in SELECT list, only suggest functions and select-level keywords (DISTINCT, CASE)
  -- so DDL/DML statements never overwhelm column suggestions.
  if before:match '[Ss][Ee][Ll][Ee][Cc][Tt]%s+.*$' then
    return callback {
      items = get_select_items(),
      is_incomplete_forward = false,
      is_incomplete_backward = false,
    }
  end

  callback {
    items = get_all_items(),
    is_incomplete_forward = false,
    is_incomplete_backward = false,
  }
end

return M
