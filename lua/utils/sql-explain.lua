-- lua/utils/sql-explain.lua
-- Visual PostgreSQL Execution Plan UI (<leader>be) powered by sqmeow.nvim RPC.
-- Renders an interactive MSSQL/VS Code-style operator tree with cost bars,
-- actual vs estimated row mismatch warnings, buffer stats, and node inspection.

local M = {}

local silent_calls = {}
local silent_in_flight = false
local silent_prev_call = nil
local silent_hook_installed = false

local function is_silent_call(call)
  if type(call) ~= 'table' then
    return false
  end
  if call.call_id and silent_calls[call.call_id] then
    return true
  end
  if silent_in_flight and (not silent_prev_call or call.call_id ~= silent_prev_call.call_id) then
    return true
  end
  return false
end

local function ensure_silent_hook()
  if silent_hook_installed then
    return
  end
  local ok_res, result = pcall(require, 'sqmeow.ui.result')
  if not ok_res or type(result) ~= 'table' or type(result.render) ~= 'function' then
    return
  end
  silent_hook_installed = true

  local orig_render = result.render
  result.render = function(summary, ...)
    if is_silent_call(summary) then
      local ok_st, st = pcall(require, 'sqmeow.core.state')
      if ok_st and st and silent_prev_call ~= nil then
        st.call = silent_prev_call
      end
      return
    end
    return orig_render(summary, ...)
  end

  local ok_hist, history = pcall(require, 'sqmeow.server.history')
  if ok_hist and type(history) == 'table' and type(history.append) == 'function' then
    local orig_append = history.append
    history.append = function(call, ...)
      if is_silent_call(call) then
        return
      end
      return orig_append(call, ...)
    end
  end
end

local function get_sql_from_buffer()
  local buf = vim.api.nvim_get_current_buf()
  local mode = vim.api.nvim_get_mode().mode
  if mode:match('[vV\x16]') then
    local s = vim.fn.getpos('v')
    local e = vim.fn.getpos('.')
    local l1, l2 = math.min(s[2], e[2]), math.max(s[2], e[2])
    local lines = vim.api.nvim_buf_get_lines(buf, l1 - 1, l2, false)
    return vim.trim(table.concat(lines, '\n'))
  end

  -- Extract statement under cursor (delimited by `;` or blank lines)
  local cur_line = vim.api.nvim_win_get_cursor(0)[1]
  local all_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local full = table.concat(all_lines, '\n')
  if vim.trim(full) == '' then
    return nil
  end

  -- Find statement containing cur_line by splitting on `;`
  local line_idx = 1
  local stmt_start_line = 1
  local current = {}
  local chosen = nil
  for _, line in ipairs(all_lines) do
    table.insert(current, line)
    if line:find(';', 1, true) then
      if cur_line >= stmt_start_line and cur_line <= line_idx then
        chosen = table.concat(current, '\n')
        break
      end
      current = {}
      stmt_start_line = line_idx + 1
    end
    line_idx = line_idx + 1
  end
  if not chosen and #current > 0 then
    chosen = table.concat(current, '\n')
  end
  return chosen and vim.trim(chosen) or nil
end

local function strip_leading_comments(sql)
  local s = sql
  while true do
    local next_s = s:gsub('^%s*%-%-[^\n]*\n?', ''):gsub('^%s*/%*.-%*/%s*', '')
    if next_s == s then
      break
    end
    s = next_s
  end
  return vim.trim(s)
end

local function is_read_only_sql(sql)
  local clean = strip_leading_comments(sql):upper()
  return clean:match('^SELECT%s') ~= nil
    or clean:match('^WITH%s') ~= nil
    or clean:match('^TABLE%s') ~= nil
    or clean:match('^VALUES%s') ~= nil
end

local function format_num(n)
  if type(n) ~= 'number' then
    return '-'
  end
  if n >= 1000000 then
    return string.format('%.1fM', n / 1000000)
  elseif n >= 1000 then
    return string.format('%.1fk', n / 1000)
  end
  return tostring(math.floor(n + 0.5))
end

local function format_ms(ms)
  if type(ms) ~= 'number' then
    return '-'
  end
  if ms >= 1000 then
    return string.format('%.2fs', ms / 1000)
  elseif ms >= 10 then
    return string.format('%.1fms', ms)
  end
  return string.format('%.2fms', ms)
end

local function cost_bar(pct, width)
  width = width or 10
  local clamped = math.max(0, math.min(100, pct or 0))
  local filled = math.floor((clamped / 100) * width + 0.5)
  return ('█'):rep(filled) .. ('░'):rep(width - filled)
end

-- Recursively enrich plan nodes with exclusive time, cost %, and hotspot flags
local function enrich_node(node, root_time, root_cost, is_analyze, stats)
  local children = node.Plans or {}
  local child_time_sum = 0
  local child_cost_sum = 0

  for _, child in ipairs(children) do
    enrich_node(child, root_time, root_cost, is_analyze, stats)
    local loops = child['Actual Loops'] or 1
    child_time_sum = child_time_sum + ((child['Actual Total Time'] or 0) * loops)
    child_cost_sum = child_cost_sum + (child['Total Cost'] or 0)
  end

  local loops = node['Actual Loops'] or 1
  local total_time = (node['Actual Total Time'] or 0) * loops
  local excl_time = math.max(0, total_time - child_time_sum)
  local total_cost = node['Total Cost'] or 0
  local excl_cost = math.max(0, total_cost - child_cost_sum)

  local pct = 0
  if is_analyze and root_time > 0 then
    pct = (excl_time / root_time) * 100
  elseif root_cost > 0 then
    pct = (excl_cost / root_cost) * 100
  end

  local flags = {}
  local ntype = node['Node Type'] or 'Unknown'
  local is_seq_scan = (ntype == 'Seq Scan')
  if is_seq_scan then
    stats.seq_scans = stats.seq_scans + 1
    table.insert(flags, 'FULL SCAN')
  end

  local plan_rows = node['Plan Rows'] or 0
  local actual_rows = node['Actual Rows']
  local has_mismatch = false
  if is_analyze and actual_rows ~= nil then
    local ratio = math.max((actual_rows + 1) / (plan_rows + 1), (plan_rows + 1) / (actual_rows + 1))
    if ratio >= 10 and math.abs(actual_rows - plan_rows) >= 50 then
      has_mismatch = true
      stats.mismatches = stats.mismatches + 1
      table.insert(flags, 'EST MISMATCH')
    end
  end

  local shared_hit = node['Shared Hit Blocks'] or 0
  local shared_read = node['Shared Read Blocks'] or 0
  stats.shared_hit = stats.shared_hit + shared_hit
  stats.shared_read = stats.shared_read + shared_read

  node._meta = {
    total_time = total_time,
    excl_time = excl_time,
    excl_cost = excl_cost,
    pct = pct,
    flags = flags,
    is_seq_scan = is_seq_scan,
    has_mismatch = has_mismatch,
    collapsed = false,
  }
end

local function node_severity_hl(meta, node_type)
  if meta.pct >= 50 or (meta.is_seq_scan and (meta.pct >= 20 or (meta.total_time or 0) >= 5)) then
    return 'DiagnosticError'
  elseif meta.pct >= 20 or meta.has_mismatch or meta.is_seq_scan then
    return 'DiagnosticWarn'
  elseif (node_type or ''):find('Index', 1, true) then
    return 'DiagnosticOk'
  end
  return 'DiagnosticInfo'
end

local function show_node_details_popup(node)
  local m = node._meta or {}
  local lines = {
    ' ' .. (node['Node Type'] or 'Operator') .. (node['Relation Name'] and (' on ' .. node['Relation Name']) or ''),
    ' ' .. ('━'):rep(64),
  }
  local function add(label, val)
    if val ~= nil and val ~= '' and val ~= vim.NIL then
      table.insert(lines, string.format('  %-22s %s', label .. ':', tostring(val)))
    end
  end

  add('Index Name', node['Index Name'])
  add('Alias', node['Alias'])
  add('Join Type', node['Join Type'])
  add('Exclusive Share', string.format('%.1f%%', m.pct or 0))
  add('Exclusive Time', format_ms(m.excl_time))
  add('Total Time', format_ms(m.total_time))
  add('Actual Rows', node['Actual Rows'] and (format_num(node['Actual Rows']) .. ' (loops: ' .. tostring(node['Actual Loops'] or 1) .. ')') or nil)
  add('Estimated Rows', format_num(node['Plan Rows']))
  add('Startup / Total Cost', string.format('%.2f .. %.2f', node['Startup Cost'] or 0, node['Total Cost'] or 0))
  add('Filter', node['Filter'])
  add('Index Cond', node['Index Cond'])
  add('Hash Cond', node['Hash Cond'])
  add('Join Filter', node['Join Filter'])
  add('Recheck Cond', node['Recheck Cond'])
  add('Sort Key', type(node['Sort Key']) == 'table' and table.concat(node['Sort Key'], ', ') or node['Sort Key'])
  add('Sort Method', node['Sort Method'])
  add('Sort Space Used', node['Sort Space Used'] and (tostring(node['Sort Space Used']) .. ' kB (' .. tostring(node['Sort Space Type'] or '') .. ')') or nil)
  add('Rows Removed by Filter', node['Rows Removed by Filter'])
  add('Shared Hit Blocks', node['Shared Hit Blocks'])
  add('Shared Read Blocks', node['Shared Read Blocks'])
  add('Temp Read / Written', (node['Temp Read Blocks'] or node['Temp Written Blocks']) and (tostring(node['Temp Read Blocks'] or 0) .. ' / ' .. tostring(node['Temp Written Blocks'] or 0)) or nil)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = 'wipe'
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  local width = math.min(82, math.floor(vim.o.columns * 0.7))
  local height = math.min(#lines + 1, math.floor(vim.o.lines * 0.65))
  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = 'minimal',
    border = 'rounded',
    title = ' Operator Details (q / <Esc> to close) ',
    title_pos = 'center',
  })
  vim.wo[win].wrap = true
  local function close()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end
  vim.keymap.set('n', 'q', close, { buffer = buf, silent = true, nowait = true })
  vim.keymap.set('n', '<Esc>', close, { buffer = buf, silent = true, nowait = true })
end

function M.render_plan(plan_doc, raw_json, sql_text, is_analyze, conn_name)
  local entry = (type(plan_doc) == 'table' and plan_doc[1]) or plan_doc
  local root = entry and entry.Plan
  if not root then
    vim.notify('Could not parse PostgreSQL EXPLAIN JSON output', vim.log.levels.ERROR, { title = 'Explain Plan' })
    return
  end

  local root_time = entry['Execution Time'] or root['Actual Total Time'] or 0
  local root_cost = root['Total Cost'] or 0
  local stats = { seq_scans = 0, mismatches = 0, shared_hit = 0, shared_read = 0 }
  enrich_node(root, root_time, root_cost, is_analyze, stats)

  local ed_win = (_G.RightPanel and _G.RightPanel.get_editor_win and _G.RightPanel.get_editor_win()) or vim.api.nvim_get_current_win()
  local prev_ed_buf = (ed_win and vim.api.nvim_win_is_valid(ed_win)) and vim.api.nvim_win_get_buf(ed_win) or nil

  local buf_name = '[Explain Plan: ' .. (conn_name or 'postgres') .. ']'
  local existing = vim.fn.bufnr('^' .. vim.pesc(buf_name) .. '$')
  if existing ~= -1 and vim.api.nvim_buf_is_valid(existing) then
    pcall(vim.api.nvim_buf_delete, existing, { force = true })
  end

  local buf = vim.api.nvim_create_buf(false, true)
  local ns = vim.api.nvim_create_namespace('SqmeowExplainPlan')
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = 'sqmeow-explain'
  vim.b[buf].is_sql_inspector = true
  pcall(vim.api.nvim_buf_set_name, buf, buf_name)

  local line_to_node = {}

  local function draw()
    if not vim.api.nvim_buf_is_valid(buf) then
      return
    end
    line_to_node = {}
    local lines = {}
    local hls = {}

    local mode_str = is_analyze and 'ANALYZE + BUFFERS' or 'ESTIMATED (read-safe)'
    local plan_ms = format_ms(entry['Planning Time'])
    local exec_ms = is_analyze and format_ms(entry['Execution Time']) or ('cost ' .. string.format('%.1f', root_cost))

    table.insert(lines, ('  󱐋 PostgreSQL Execution Plan  ·  %s  ·  %s'):format(conn_name or 'postgres', mode_str))
    table.insert(hls, { row = 0, sc = 0, ec = -1, hl = 'Title' })

    local summary = ('  Plan: %s   Exec: %s   Buffers: %d hit / %d read'):format(plan_ms, exec_ms, stats.shared_hit, stats.shared_read)
    if stats.seq_scans > 0 then
      summary = summary .. ('   ⚠ %d Seq Scan%s'):format(stats.seq_scans, stats.seq_scans == 1 and '' or 's')
    end
    if stats.mismatches > 0 then
      summary = summary .. ('   ⚠ %d Est Mismatch%s'):format(stats.mismatches, stats.mismatches == 1 and '' or 'es')
    end
    table.insert(lines, summary)
    table.insert(hls, {
      row = 1,
      sc = 0,
      ec = -1,
      hl = (stats.seq_scans > 0 or stats.mismatches > 0) and 'DiagnosticWarn' or 'DiagnosticOk',
    })
    table.insert(lines, '  Keys: j/k jump operator · l/<CR>/K details · h/za fold · y yank JSON · q close')
    table.insert(hls, { row = 2, sc = 0, ec = -1, hl = 'Comment' })
    table.insert(lines, '  ' .. ('─'):rep(math.max(60, (vim.api.nvim_win_is_valid(ed_win) and vim.api.nvim_win_get_width(ed_win) or 100) - 4)))
    table.insert(hls, { row = 3, sc = 0, ec = -1, hl = 'Comment' })
    table.insert(lines, '')

    local function walk(node, prefix, is_last, is_root)
      local m = node._meta or {}
      local children = node.Plans or {}
      local connector = is_root and '  ' or (prefix .. (is_last and '└─ ' or '├─ '))
      local fold_glyph = (#children > 0) and (m.collapsed and '▶ ' or '▼ ') or '• '

      local label = node['Node Type'] or 'Operator'
      if node['Relation Name'] then
        label = label .. ' on ' .. node['Relation Name']
      end
      if node['Index Name'] then
        label = label .. ' (' .. node['Index Name'] .. ')'
      end

      local left = connector .. fold_glyph .. label
      local left_target = 52
      local pad_n = math.max(2, left_target - vim.fn.strdisplaywidth(left))

      local bar = cost_bar(m.pct, 10)
      local pct_str = string.format('%5.1f%%', m.pct or 0)
      local time_str = is_analyze and string.format('%8s', format_ms(m.excl_time)) or string.format('%8.1f', m.excl_cost or 0)
      local rows_str
      if is_analyze and node['Actual Rows'] ~= nil then
        rows_str = string.format('rows: %-6s (est %s)', format_num(node['Actual Rows']), format_num(node['Plan Rows']))
      else
        rows_str = string.format('est rows: %s', format_num(node['Plan Rows']))
      end
      local flags_str = (#(m.flags or {}) > 0) and ('  [' .. table.concat(m.flags, ', ') .. ']') or ''

      local line = left .. (' '):rep(pad_n) .. bar .. ' ' .. pct_str .. '  ' .. time_str .. '  ' .. rows_str .. flags_str
      local row_idx = #lines
      table.insert(lines, line)
      line_to_node[row_idx] = node

      local sev_hl = node_severity_hl(m, node['Node Type'])
      local bar_start = #left + pad_n
      table.insert(hls, { row = row_idx, sc = #connector, ec = #left, hl = sev_hl })
      table.insert(hls, { row = row_idx, sc = bar_start, ec = bar_start + #bar + 1 + #pct_str, hl = sev_hl })
      if flags_str ~= '' then
        table.insert(hls, { row = row_idx, sc = #line - #flags_str, ec = #line, hl = 'DiagnosticError' })
      end

      if not m.collapsed then
        local child_prefix = is_root and '  ' or (prefix .. (is_last and '   ' or '│  '))
        for i, child in ipairs(children) do
          walk(child, child_prefix, i == #children, false)
        end
      end
    end

    walk(root, '', true, true)

    -- Show queried SQL at bottom for reference
    table.insert(lines, '')
    table.insert(lines, '  ── Query ──')
    table.insert(hls, { row = #lines - 1, sc = 0, ec = -1, hl = 'Comment' })
    for _, sl in ipairs(vim.split(sql_text or '', '\n', { plain = true })) do
      table.insert(lines, '  ' .. sl)
      table.insert(hls, { row = #lines - 1, sc = 0, ec = -1, hl = 'Comment' })
    end

    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false

    for _, h in ipairs(hls) do
      local opts = { hl_group = h.hl }
      if h.ec and h.ec ~= -1 then
        opts.end_col = h.ec
      end
      pcall(vim.api.nvim_buf_set_extmark, buf, ns, h.row, h.sc, opts)
    end
  end

  if ed_win and vim.api.nvim_win_is_valid(ed_win) then
    if vim.fn.exists('&winfixbuf') == 1 then
      vim.wo[ed_win].winfixbuf = false
    end
    vim.api.nvim_win_set_buf(ed_win, buf)
    vim.api.nvim_set_current_win(ed_win)
    vim.wo[ed_win].wrap = false
    vim.wo[ed_win].cursorline = true
    vim.wo[ed_win].spell = false
  end

  draw()
  pcall(vim.api.nvim_win_set_cursor, ed_win, { 6, 0 })

  local function jump_node(dir)
    local rows = vim.tbl_keys(line_to_node)
    table.sort(rows)
    if #rows == 0 then
      return
    end
    local cur = vim.api.nvim_win_get_cursor(0)[1] - 1
    local target = nil
    if dir > 0 then
      for _, r in ipairs(rows) do
        if r > cur then
          target = r
          break
        end
      end
    else
      for i = #rows, 1, -1 do
        if rows[i] < cur then
          target = rows[i]
          break
        end
      end
    end
    if target then
      vim.api.nvim_win_set_cursor(0, { target + 1, 0 })
    end
  end

  local function current_node()
    local cur = vim.api.nvim_win_get_cursor(0)[1] - 1
    return line_to_node[cur]
  end

  local function close_plan()
    if ed_win and vim.api.nvim_win_is_valid(ed_win) and vim.api.nvim_win_get_buf(ed_win) == buf then
      if prev_ed_buf and prev_ed_buf ~= buf and vim.api.nvim_buf_is_valid(prev_ed_buf) then
        vim.api.nvim_win_set_buf(ed_win, prev_ed_buf)
      else
        vim.api.nvim_win_call(ed_win, function()
          vim.cmd.enew()
        end)
      end
    end
    if vim.api.nvim_buf_is_valid(buf) then
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
  end

  local map = function(lhs, fn, desc)
    vim.keymap.set('n', lhs, fn, { buffer = buf, silent = true, nowait = true, desc = 'Explain: ' .. desc })
  end
  map('j', function()
    jump_node(1)
  end, 'Next operator')
  map('k', function()
    jump_node(-1)
  end, 'Previous operator')
  local open_details = function()
    local n = current_node()
    if n then
      show_node_details_popup(n)
    end
  end
  map('l', open_details, 'Operator details')
  map('<CR>', open_details, 'Operator details')
  map('K', open_details, 'Operator details')
  local toggle_fold = function()
    local n = current_node()
    if n and n.Plans and #n.Plans > 0 and n._meta then
      n._meta.collapsed = not n._meta.collapsed
      local cur = vim.api.nvim_win_get_cursor(0)
      draw()
      pcall(vim.api.nvim_win_set_cursor, 0, { math.min(cur[1], vim.api.nvim_buf_line_count(buf)), 0 })
    end
  end
  map('h', toggle_fold, 'Collapse / expand subtree')
  map('za', toggle_fold, 'Collapse / expand subtree')
  map('y', function()
    vim.fn.setreg('+', raw_json)
    vim.fn.setreg('"', raw_json)
    vim.notify('Yanked raw EXPLAIN JSON to clipboard', vim.log.levels.INFO, { title = 'Explain Plan' })
  end, 'Yank raw JSON')
  map('q', close_plan, 'Close Explain Plan')
  map('<Esc>', close_plan, 'Close Explain Plan')
end

function M.explain_current()
  local sql = get_sql_from_buffer()
  if not sql or sql == '' then
    vim.notify('No SQL statement found under cursor', vim.log.levels.WARN, { title = 'Explain Plan' })
    return
  end

  -- Strip trailing semicolon and any existing EXPLAIN prefix
  sql = sql:gsub(';%s*$', '')
  sql = sql:gsub('^[Ee][Xx][Pp][Ll][Aa][Ii][Nn]%s*%b()%s*', '')
  sql = sql:gsub('^[Ee][Xx][Pp][Ll][Aa][Ii][Nn]%s+', '')

  local ok_db, db = pcall(require, 'utils.database')
  local cur_buf = vim.api.nvim_get_current_buf()
  local _, db_name
  if ok_db and db.get_active_db then
    _, db_name = db.get_active_db(cur_buf)
  end
  db_name = db_name or (ok_db and db.current_db_name)
  if not db_name or db_name == '' then
    vim.notify('No active database connection. Connect with <leader>bs first.', vim.log.levels.WARN, { title = 'Explain Plan' })
    return
  end

  local cid = ok_db and db.ensure_sqmeow_connection(db_name, false)
  if not cid then
    vim.notify('Could not connect to ' .. db_name, vim.log.levels.ERROR, { title = 'Explain Plan' })
    return
  end

  local ok_st, state = pcall(require, 'sqmeow.core.state')
  local conn = ok_st and state and state.connections[cid]
  local dialect = (conn and conn.dialect) or 'postgres'
  if dialect ~= 'postgres' and dialect ~= 'postgresql' and dialect ~= 'cockroachdb' then
    vim.notify('Visual Explain Plan currently supports PostgreSQL (active dialect: ' .. tostring(dialect) .. ')', vim.log.levels.WARN, { title = 'Explain Plan' })
    return
  end

  local is_analyze = is_read_only_sql(sql)
  local explain_sql = (is_analyze and 'EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) ' or 'EXPLAIN (FORMAT JSON) ') .. sql

  local ok_rpc, rpc = pcall(require, 'sqmeow.rpc.client')
  if not ok_rpc or not rpc then
    vim.notify('sqmeow RPC client unavailable', vim.log.levels.ERROR, { title = 'Explain Plan' })
    return
  end

  vim.notify('Running ' .. (is_analyze and 'EXPLAIN ANALYZE' or 'EXPLAIN (estimated)') .. '…', vim.log.levels.INFO, { title = 'Explain Plan' })

  ensure_silent_hook()
  silent_prev_call = ok_st and state and state.call or nil

  local target_id = nil
  local buffered = {}
  local unsub

  local function cleanup_silent(id)
    if id then
      -- Clear on next tick so sqmeow's own call:state handler finishes first
      vim.schedule(function()
        silent_calls[id] = nil
      end)
    end
  end

  local function handle_state(payload)
    if not payload or payload.call_id ~= target_id then
      return
    end
    if payload.state == 'error' or payload.state == 'cancelled' then
      if unsub then
        unsub()
        unsub = nil
      end
      cleanup_silent(target_id)
      vim.schedule(function()
        vim.notify('Explain error: ' .. tostring(payload.error or payload.state), vim.log.levels.ERROR, { title = 'Explain Plan' })
      end)
      return
    end
    if payload.state == 'done' then
      if unsub then
        unsub()
        unsub = nil
      end
      cleanup_silent(target_id)
      vim.schedule(function()
        local reply, verr = rpc.request('rows', {
          call_id = target_id,
          offset = 0,
          limit = 10,
        })
        local raw = nil
        if type(reply) == 'table' and reply.rows and reply.rows[1] and reply.rows[1][1] then
          raw = reply.rows[1][1]
        end
        if not raw then
          vim.notify('Explain returned no plan rows: ' .. tostring(verr or 'empty'), vim.log.levels.ERROR, { title = 'Explain Plan' })
          return
        end
        local raw_str = (type(raw) == 'table') and vim.json.encode(raw) or tostring(raw)
        local ok_dec, decoded = pcall(vim.json.decode, raw_str)
        if not ok_dec or type(decoded) ~= 'table' then
          vim.notify('Failed to decode EXPLAIN JSON', vim.log.levels.ERROR, { title = 'Explain Plan' })
          return
        end
        M.render_plan(decoded, raw_str, sql, is_analyze, db_name)
      end)
    end
  end

  -- Subscribe before issuing execute so fast plans cannot race past the listener
  unsub = rpc.on('call:state', function(payload)
    if not target_id then
      table.insert(buffered, payload)
    else
      handle_state(payload)
    end
  end)

  silent_in_flight = true
  local call_id, req_err = rpc.request('execute', {
    conn_id = cid,
    sql = explain_sql,
  })
  if call_id then
    silent_calls[call_id] = true
  end
  silent_in_flight = false
  if not call_id then
    if unsub then
      unsub()
      unsub = nil
    end
    vim.notify('Explain failed: ' .. tostring(req_err), vim.log.levels.ERROR, { title = 'Explain Plan' })
    return
  end

  target_id = call_id
  for _, ev in ipairs(buffered) do
    handle_state(ev)
  end
  buffered = {}
end

return M
