-- lua/utils/terminal-tracker.lua
-- Fast, lightweight tracking and formatting of bottom-panel terminal instances for Lualine

local M = {}

local uv = vim.uv or vim.loop
local CACHE_TTL_MS = 400
local cache = {
  timestamp = 0,
  items = {},
}

-- Fallback shell label
local function resolve_fallback_label(buf)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return 'zsh'
  end
  local st = vim.b[buf].snacks_terminal
  if st and st.cmd then
    local cmd = type(st.cmd) == 'table' and st.cmd[1] or tostring(st.cmd)
    if cmd and cmd ~= '' then
      local base = vim.fs.basename(cmd)
      if base and base ~= '' then
        return base
      end
    end
  end
  local bname = vim.api.nvim_buf_get_name(buf)
  local shell_name = bname:match ':(%w+)$'
  if shell_name and shell_name ~= '' then
    return shell_name
  end
  return 'zsh'
end

-- Smart command parsing: extracts <binary> <action/subcommand> and strips flags/paths
local function parse_smart_cmd(parts)
  local clean = {}
  for _, p in ipairs(parts) do
    if p and p ~= '' then
      table.insert(clean, p)
    end
  end
  if #clean == 0 then
    return ''
  end

  local bin = vim.fs.basename(clean[1])

  -- Shell clearing commands reset terminal to shell
  if bin == 'clear' or bin == 'reset' then
    return 'zsh'
  end

  -- Package managers: npm, yarn, pnpm, bun
  if bin == 'npm' or bin == 'yarn' or bin == 'pnpm' or bin == 'bun' then
    if clean[2] == 'run' and clean[3] and not clean[3]:match '^%-' then
      return bin .. ' ' .. clean[3]
    elseif clean[2] and not clean[2]:match '^%-' then
      return bin .. ' ' .. clean[2]
    end
    return bin
  end

  -- Python runners
  if bin == 'python' or bin == 'python3' then
    if clean[2] == '-m' and clean[3] then
      return 'python ' .. clean[3]
    elseif clean[2] and not clean[2]:match '^%-' then
      return 'python ' .. vim.fs.basename(clean[2])
    end
    return 'python'
  end

  -- Docker
  if bin == 'docker' or bin == 'docker-compose' then
    if clean[2] == 'compose' and clean[3] and not clean[3]:match '^%-' then
      return 'docker ' .. clean[3]
    elseif clean[2] and not clean[2]:match '^%-' then
      return 'docker ' .. clean[2]
    end
    return 'docker'
  end

  -- General tools (git, cargo, make, pytest, etc.): take binary + first non-flag argument
  if clean[2] and not clean[2]:match '^%-' then
    local sub = vim.fs.basename(clean[2])
    return bin .. ' ' .. sub
  end

  return bin
end

-- Truncate string to budget with '...' indicator if exceeded
local function truncate(str, budget)
  local len = vim.fn.strdisplaywidth(str)
  if len <= budget then
    return str
  end
  if budget <= 3 then
    return vim.fn.strcharpart(str, 0, budget)
  end
  return vim.fn.strcharpart(str, 0, budget - 3) .. '...'
end

-- Read foreground command info via Linux /proc/<pid>/stat and tpgid
local function get_terminal_process_info(buf)
  local pid = vim.b[buf].terminal_job_pid
  if not pid or pid <= 0 then
    local job_id = vim.b[buf].terminal_job_id
    if job_id then
      pid = vim.fn.jobpid(job_id)
    end
  end

  if not pid or pid <= 0 then
    return vim.b[buf].terminal_last_cmd or resolve_fallback_label(buf), false
  end

  local f = io.open('/proc/' .. pid .. '/stat', 'r')
  if not f then
    return vim.b[buf].terminal_last_cmd or resolve_fallback_label(buf), false
  end
  local stat = f:read '*a'
  f:close()

  if not stat or stat == '' then
    return vim.b[buf].terminal_last_cmd or resolve_fallback_label(buf), false
  end

  local rest = stat:match '%)%s+(.+)$'
  if not rest then
    return vim.b[buf].terminal_last_cmd or resolve_fallback_label(buf), false
  end

  local fields = vim.split(rest, '%s+')
  local pgrp = fields[3]
  local tpgid = fields[6]

  local is_running = (tpgid and pgrp and tpgid ~= pgrp and tonumber(tpgid) and tonumber(tpgid) > 0)

  if is_running then
    -- Foreground child process is active! Read its cmdline or comm
    local cf = io.open('/proc/' .. tpgid .. '/cmdline', 'r')
    local parts = {}
    if cf then
      local content = cf:read '*a'
      cf:close()
      if content and content ~= '' then
        for _, p in ipairs(vim.split(content, '\0')) do
          if p and p ~= '' then
            table.insert(parts, p)
          end
        end
      end
    end

    local smart = parse_smart_cmd(parts)
    if not smart or smart == '' then
      local comm_f = io.open('/proc/' .. tpgid .. '/comm', 'r')
      if comm_f then
        local comm = vim.trim(comm_f:read '*a' or '')
        comm_f:close()
        if comm ~= '' and comm ~= 'zsh' and comm ~= 'bash' and comm ~= 'sh' then
          smart = comm
        end
      end
    end

    if smart and smart ~= '' then
      if smart == 'zsh' then
        vim.b[buf].terminal_last_cmd = nil
        return 'zsh', false
      end
      vim.b[buf].terminal_last_cmd = smart
      return smart, true
    end

    -- If foreground process could not be read, treat as running with last command or comm
    local fallback = vim.b[buf].terminal_last_cmd or resolve_fallback_label(buf)
    return fallback, true
  end

  -- Idle state: return retained last command (or fallback shell)
  local idle_cmd = vim.b[buf].terminal_last_cmd or resolve_fallback_label(buf)
  return idle_cmd, false
end

local order_seq = 0
local function ensure_order(buf)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    order_seq = order_seq + 1
    return order_seq
  end
  local seq = vim.b[buf].bottom_order_seq
  if not seq then
    order_seq = order_seq + 1
    seq = order_seq
    vim.b[buf].bottom_order_seq = seq
  end
  return seq
end

-- Strip optional schema prefix (e.g. "public.order_items" -> "order_items")
local function strip_schema(name)
  if not name or name == '' then
    return name
  end
  local clean = name:gsub('["`%[%]]', '')
  return clean:match '%.([^%.]+)$' or clean
end

-- Resolve descriptive label for SQL Results (Option A: active table name -> db name -> 'query')
local function resolve_dbout_label(buf)
  local db_utils = _G.DatabaseUtils
  if not db_utils then
    local ok_u, u = pcall(require, 'utils.database')
    if ok_u then
      db_utils = u
    end
  end

  if db_utils and db_utils.get_active_table then
    local tbl = db_utils.get_active_table(buf)
    if tbl and tbl ~= '' then
      return strip_schema(tbl)
    end
    local ed_win = _G.RightPanel and _G.RightPanel.get_editor_win and _G.RightPanel.get_editor_win()
    if ed_win and vim.api.nvim_win_is_valid(ed_win) then
      local ed_buf = vim.api.nvim_win_get_buf(ed_win)
      local ed_tbl = db_utils.get_active_table(ed_buf)
      if ed_tbl and ed_tbl ~= '' then
        return strip_schema(ed_tbl)
      end
    end
  end

  local ok_st, st = pcall(require, 'sqmeow.core.state')
  if ok_st and st and st.call then
    if st.call.source and st.call.source.name and st.call.source.name ~= '' then
      return strip_schema(st.call.source.name)
    end
    if st.call.statement and db_utils and db_utils.detect_table_from_sql then
      local tbl = db_utils.detect_table_from_sql(st.call.statement)
      if tbl and tbl ~= '' then
        return strip_schema(tbl)
      end
    end
    if st.call.conn_id and st.connections and st.connections[st.call.conn_id] then
      local cname = st.connections[st.call.conn_id].name
      if cname and cname ~= '' then
        return cname
      end
    end
  end

  if db_utils and db_utils.get_active_db then
    local _, dname = db_utils.get_active_db(buf)
    if dname and dname ~= '' then
      return dname
    end
  end

  return 'query'
end

-- Resolve descriptive label for Quickfix (concise source title + count)
local function resolve_qf_label()
  local ok_qf, info = pcall(vim.fn.getqflist, { title = 1, size = 1 })
  if not ok_qf or type(info) ~= 'table' then
    return 'qf'
  end

  local size = tonumber(info.size) or 0
  local title = tostring(info.title or ''):lower()
  local base = 'qf'

  if title:find 'diagnostic' then
    base = size > 0 and 'diag' or 'diagnostics'
  elseif title:find 'reference' then
    base = size > 0 and 'refs' or 'references'
  elseif title:find 'definition' then
    base = size > 0 and 'defs' or 'definitions'
  elseif title:find 'implement' then
    base = size > 0 and 'impl' or 'implementations'
  elseif title:find 'symbol' then
    base = size > 0 and 'sym' or 'symbols'
  elseif title:find 'grep' or title:find 'vimgrep' then
    base = 'grep'
  end

  if size > 0 then
    return string.format('%s (%d)', base, size)
  end
  return base
end

-- Collect all qualifying bottom panel items (Terminals, SQL Results, Quickfix) in visual opening order
function M.get_terminals()
  local now = uv.hrtime() / 1e6
  if (now - cache.timestamp) < CACHE_TTL_MS then
    return cache.items
  end

  local terms = {}
  local seen_term = {}

  -- 1. Query Snacks terminal list (canonical registry of active Snacks terminals)
  local ok_snacks, snacks_term = pcall(function()
    return Snacks.terminal.list()
  end)
  if ok_snacks and type(snacks_term) == 'table' then
    for _, t in ipairs(snacks_term) do
      if t and t:buf_valid() and vim.api.nvim_buf_is_valid(t.buf) then
        local bname = vim.api.nvim_buf_get_name(t.buf):lower()
        local cmd_str = tostring(t.cmd or ''):lower()
        local is_opencode = cmd_str:find 'opencode' ~= nil or bname:find 'opencode' ~= nil
        local is_dbout = bname:find '/sqmeow/' or bname:find '/db_ui/'
        if not is_opencode and not is_dbout then
          local st = vim.b[t.buf].snacks_terminal
          local id = (t.opts and t.opts.count) or (st and st.id) or 1
          if not seen_term[id] then
            seen_term[id] = true
            local cmd, is_running = get_terminal_process_info(t.buf)
            table.insert(terms, {
              kind = 'terminal',
              id = id,
              buf = t.buf,
              icon = ' ',
              cmd = cmd,
              is_running = is_running,
              order = ensure_order(t.buf),
            })
          end
        end
      end
    end
  end

  -- 2. Fallback to scanning open loaded terminal buffers
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_is_loaded(buf) then
      local ft = vim.bo[buf].filetype
      local bt = vim.bo[buf].buftype
      local bname = vim.api.nvim_buf_get_name(buf):lower()
      local is_term = (bt == 'terminal' or ft == 'snacks_terminal' or ft == 'terminal' or bname:find '^term://' ~= nil)
      local st = vim.b[buf].snacks_terminal
      local is_opencode = ft:match 'opencode' ~= nil or bname:find 'opencode' ~= nil or (st and tostring(st.cmd):find 'opencode' ~= nil)
      local is_dbout = ft == 'dbout' or ft == 'sqmeow-result' or bname:find '/sqmeow/' or bname:find '/db_ui/'

      if is_term and not is_opencode and not is_dbout then
        local id = (st and st.id) or 1
        if not seen_term[id] then
          seen_term[id] = true
          local cmd, is_running = get_terminal_process_info(buf)
          table.insert(terms, {
            kind = 'terminal',
            id = id,
            buf = buf,
            icon = ' ',
            cmd = cmd,
            is_running = is_running,
            order = ensure_order(buf),
          })
        end
      end
    end
  end

  -- Sync visible windows so explicitly opened bottom panels are always marked open
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_is_valid(win) then
      local b = vim.api.nvim_win_get_buf(win)
      if vim.api.nvim_buf_is_valid(b) then
        local ft = vim.bo[b].filetype
        local bt = vim.bo[b].buftype
        local name = vim.api.nvim_buf_get_name(b)
        if (ft == 'dbout' or ft == 'sqmeow-result' or name:find 'sqmeow://result') and ft ~= 'sqmeow-drawer' and not name:find 'drawer' then
          if _G.BottomPanel then
            _G.BottomPanel.dbout_open = true
            _G.BottomPanel.last_dbout_buf = b
          end
          ensure_order(b)
        elseif ft == 'qf' or bt == 'quickfix' then
          if _G.BottomPanel then
            _G.BottomPanel.qf_open = true
            _G.BottomPanel.last_qf_buf = b
          end
          ensure_order(b)
        end
      end
    end
  end

  -- 3. Explicitly opened SQL Results panel (dbout / sqmeow-result)
  if _G.BottomPanel and _G.BottomPanel.dbout_open then
    local dbout_buf = _G.BottomPanel.last_dbout_buf
    if not (dbout_buf and vim.api.nvim_buf_is_valid(dbout_buf)) then
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(buf) then
          local ft = vim.bo[buf].filetype
          local name = vim.api.nvim_buf_get_name(buf)
          if (ft == 'dbout' or ft == 'sqmeow-result' or name:find 'sqmeow://result') and ft ~= 'sqmeow-drawer' and not name:find 'drawer' then
            dbout_buf = buf
            _G.BottomPanel.last_dbout_buf = buf
            break
          end
        end
      end
    end
    if dbout_buf and vim.api.nvim_buf_is_valid(dbout_buf) then
      table.insert(terms, {
        kind = 'dbout',
        id = 'dbout',
        buf = dbout_buf,
        icon = '󰆼 ',
        cmd = resolve_dbout_label(dbout_buf),
        is_running = false,
        order = ensure_order(dbout_buf),
      })
    else
      _G.BottomPanel.dbout_open = false
    end
  end

  -- 4. Explicitly opened Quickfix / Diagnostics panel (qf)
  if _G.BottomPanel and _G.BottomPanel.qf_open then
    local qf_buf = _G.BottomPanel.last_qf_buf
    if not (qf_buf and vim.api.nvim_buf_is_valid(qf_buf)) then
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(buf) and (vim.bo[buf].filetype == 'qf' or vim.bo[buf].buftype == 'quickfix') then
          qf_buf = buf
          _G.BottomPanel.last_qf_buf = buf
          break
        end
      end
    end
    if qf_buf and vim.api.nvim_buf_is_valid(qf_buf) then
      table.insert(terms, {
        kind = 'qf',
        id = 'qf',
        buf = qf_buf,
        icon = '󰁨 ',
        cmd = resolve_qf_label(),
        is_running = false,
        order = ensure_order(qf_buf),
      })
    else
      _G.BottomPanel.qf_open = false
    end
  end

  table.sort(terms, function(a, b)
    if a.order ~= b.order then
      return a.order < b.order
    end
    return tostring(a.id) < tostring(b.id)
  end)

  cache.timestamp = now
  cache.items = terms
  return terms
end

-- Invalidate cached state
function M.invalidate()
  cache.timestamp = 0
end

-- Resolve active highlight matching current mode
local function get_active_hl()
  local ok, hl = pcall(require, 'lualine.highlight')
  if ok and hl.get_mode_suffix then
    local name = 'lualine_a' .. hl.get_mode_suffix()
    if vim.fn.hlexists(name) == 1 then
      return name
    end
  end
  return 'TerminalTrackerActive'
end

-- Resolve inactive highlight (transparent background with mode font color)
local function get_inactive_hl()
  local ok, hl = pcall(require, 'lualine.highlight')
  if ok and hl.get_mode_suffix then
    local name = 'lualine_b' .. hl.get_mode_suffix()
    if vim.fn.hlexists(name) == 1 then
      return name
    end
  end
  return 'TerminalTrackerInactive'
end

-- Resolve running highlight (transparent background with vibrant green accent)
local function get_running_hl()
  if vim.fn.hlexists 'TerminalTrackerRunning' == 1 then
    return 'TerminalTrackerRunning'
  end
  return get_inactive_hl()
end

-- Lualine component formatter
function M.lualine_component()
  local terms = M.get_terminals()
  if #terms == 0 then
    return ''
  end

  local cur_win = vim.api.nvim_get_current_win()
  local cur_buf = vim.api.nvim_get_current_buf()
  local win_buf = vim.api.nvim_win_is_valid(cur_win) and vim.api.nvim_win_get_buf(cur_win) or cur_buf
  local active_hl = get_active_hl()
  local inactive_hl = get_inactive_hl()
  local running_hl = get_running_hl()

  -- Dynamic character budget: 16 chars for 1 terminal, 11 for 2 terminals, 8 for 3+ terminals
  local num_terms = #terms
  local budget = 16
  if num_terms == 2 then
    budget = 11
  elseif num_terms >= 3 then
    budget = 8
  end

  local parts = {}

  for _, t in ipairs(terms) do
    local is_active = (t.buf == cur_buf or t.buf == win_buf)
    local raw_cmd = t.cmd or 'zsh'
    local truncated = truncate(raw_cmd, budget)
    local prefix = t.icon or ''
    local label = prefix .. (t.is_running and (truncated .. ' ') or truncated)

    local hl
    if is_active then
      hl = active_hl
    elseif t.is_running then
      hl = running_hl
    else
      hl = inactive_hl
    end

    table.insert(parts, string.format('%%#%s# %s %%*', hl, label))
  end

  return table.concat(parts, '|')
end

-- Setup autocommands to invalidate cache and refresh lualine on terminal lifecycle events
function M.setup()
  local function setup_tracker_highlights()
    local ok, ctp = pcall(require, 'catppuccin.palettes')
    local C = ok and ctp.get_palette 'mocha' or {}
    local green = C.green or '#a6e3a1'
    vim.api.nvim_set_hl(0, 'TerminalTrackerRunning', { bg = 'NONE', fg = green, bold = true, default = true })
  end

  setup_tracker_highlights()
  vim.api.nvim_create_autocmd('ColorScheme', {
    callback = setup_tracker_highlights,
  })

  local group = vim.api.nvim_create_augroup('UserTerminalTracker', { clear = true })
  vim.api.nvim_create_autocmd({
    'TermOpen',
    'TermClose',
    'BufWipeout',
    'BufDelete',
    'TermEnter',
    'TermLeave',
    'FileType',
    'BufWinEnter',
  }, {
    group = group,
    callback = function()
      M.invalidate()
      pcall(function()
        require('lualine').refresh()
      end)
    end,
    desc = 'Invalidate terminal tracker cache on terminal lifecycle events',
  })
end

return M
