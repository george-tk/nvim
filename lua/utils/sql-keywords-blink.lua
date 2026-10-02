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

local items_cache = nil

local function get_items()
  if items_cache then
    return items_cache
  end
  local items = {}
  local seen = {}

  local function add(label, kind, desc, score)
    if not seen[label] then
      seen[label] = true
      table.insert(items, {
        label = label,
        kind = kind,
        score_offset = score or 50,
        labelDetails = { description = desc },
      })
    end
  end

  for _, kw in ipairs(KEYWORDS) do
    add(kw, 14, 'SQL', 50)
    add(kw:lower(), 14, 'sql', 50)
  end

  for _, fn in ipairs(FUNCTIONS) do
    add(fn, 3, 'SQL fn', 40)
    add(fn:lower(), 3, 'sql fn', 40)
  end

  items_cache = items
  return items_cache
end

function M.new()
  return setmetatable({}, { __index = M })
end

function M:get_trigger_characters()
  return {}
end

function M:enabled()
  local ft = vim.bo.filetype
  return ft == 'sql' or ft == 'mysql' or ft == 'plsql'
end

function M:get_completions(context, callback)
  local line = context.line or ''
  local col = context.cursor[2] or 0
  local before = line:sub(1, col)

  -- If cursor is immediately after a dot (e.g. "users.", "public."),
  -- do NOT suggest SQL keywords; let sqmeow handle columns and tables exclusively.
  if before:match('[%w_%.`"]+%.%s*[%w_]*$') then
    return callback { items = {}, is_incomplete_forward = false, is_incomplete_backward = false }
  end

  callback {
    items = get_items(),
    is_incomplete_forward = false,
    is_incomplete_backward = false,
  }
end

return M
