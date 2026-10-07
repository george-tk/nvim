-- lua/utils/terminal-tracker.lua
-- Track and format bottom-panel terminal instances for Lualine

local M = {}

local uv = vim.uv or vim.loop
local CACHE_TTL_MS = 300
local cache = {
  timestamp = 0,
  items = {},
}

-- Resolve deepest child process PID under shell PID
local function get_child_process_info(pid)
  if not pid or pid <= 0 then
    return nil, false
  end

  local current = pid
  local has_child = false

  while current do
    local f = io.open('/proc/' .. current .. '/task/' .. current .. '/children', 'r')
    if not f then
      break
    end
    local content = f:read('*a')
    f:close()

    local pids = vim.split(vim.trim(content or ''), '%s+')
    if #pids > 0 and pids[#pids] ~= '' and tonumber(pids[#pids]) then
      current = tonumber(pids[#pids])
      has_child = true
    else
      break
    end
  end

  local comm = nil
  local comm_file = io.open('/proc/' .. current .. '/comm', 'r')
  if comm_file then
    comm = vim.trim(comm_file:read('*a') or '')
    comm_file:close()
  end

  return comm, has_child
end

-- Resolve informative label according to priority:
-- 1. Active command (npm, pytest, cargo, etc.)
-- 2. Subdirectory if in a subfolder (frontend, api, etc.)
-- 3. Shell name (zsh, bash)
local function resolve_terminal_label(pid, buf)
  if not pid then
    local bname = vim.api.nvim_buf_get_name(buf)
    local shell_name = bname:match(':(%w+)$') or 'term'
    return shell_name
  end

  local comm, has_child = get_child_process_info(pid)

  -- Priority 1: Active running command
  if has_child and comm and comm ~= '' then
    return comm .. ' '
  end

  -- Priority 2: Subfolder if terminal cwd differs from Neovim cwd
  local ok, proc_cwd = pcall(uv.fs_readlink, '/proc/' .. pid .. '/cwd')
  local nvim_cwd = vim.fn.getcwd()
  if ok and proc_cwd and proc_cwd ~= '' and proc_cwd ~= nvim_cwd then
    local rel = proc_cwd:match('^' .. vim.pesc(nvim_cwd) .. '/(.+)$')
    if rel and rel ~= '' then
      return rel
    end
    local base = vim.fs.basename(proc_cwd)
    if base and base ~= '' then
      return base
    end
  end

  -- Priority 3: Shell name
  if comm and comm ~= '' then
    return comm
  end

  return 'zsh'
end

-- Collect all qualifying bottom panel terminals
function M.get_terminals()
  local now = uv.hrtime() / 1e6
  if (now - cache.timestamp) < CACHE_TTL_MS then
    return cache.items
  end

  local terms = {}
  local seen = {}

  -- 1. Query Snacks terminal list (canonical registry of active Snacks terminals)
  local ok_snacks, snacks_term = pcall(function() return Snacks.terminal.list() end)
  if ok_snacks and type(snacks_term) == 'table' then
    for _, t in ipairs(snacks_term) do
      if t and t:buf_valid() and vim.api.nvim_buf_is_valid(t.buf) then
        local bname = vim.api.nvim_buf_get_name(t.buf):lower()
        local cmd_str = tostring(t.cmd or ''):lower()
        local is_opencode = cmd_str:find('opencode') ~= nil or bname:find('opencode') ~= nil
        local is_dbout = bname:find('/sqmeow/') or bname:find('/db_ui/')
        if not is_opencode and not is_dbout then
          local st = vim.b[t.buf].snacks_terminal
          local id = (t.opts and t.opts.count) or (st and st.id) or 1
          if not seen[id] then
            seen[id] = true
            local pid = vim.b[t.buf].terminal_job_pid
            local label = resolve_terminal_label(pid, t.buf)
            table.insert(terms, {
              id = id,
              buf = t.buf,
              label = label,
            })
          end
        end
      end
    end
  end

  -- 2. Fallback to scanning open loaded buffers
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_is_loaded(buf) then
      local ft = vim.bo[buf].filetype
      local bt = vim.bo[buf].buftype
      local bname = vim.api.nvim_buf_get_name(buf):lower()
      local is_term = (bt == 'terminal' or ft == 'snacks_terminal' or ft == 'terminal' or bname:find('^term://') ~= nil)
      local st = vim.b[buf].snacks_terminal
      local is_opencode = ft:match('opencode') ~= nil or bname:find('opencode') ~= nil or (st and tostring(st.cmd):find('opencode') ~= nil)
      local is_dbout = ft == 'dbout' or ft == 'sqmeow-result' or bname:find('/sqmeow/') or bname:find('/db_ui/')

      if is_term and not is_opencode and not is_dbout then
        local id = (st and st.id) or 1
        if not seen[id] then
          seen[id] = true
          local pid = vim.b[buf].terminal_job_pid
          local label = resolve_terminal_label(pid, buf)
          table.insert(terms, {
            id = id,
            buf = buf,
            label = label,
          })
        end
      end
    end
  end

  table.sort(terms, function(a, b) return a.id < b.id end)

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

  local parts = {}

  for _, t in ipairs(terms) do
    local is_active = (t.buf == cur_buf or t.buf == win_buf)
    if is_active then
      table.insert(parts, string.format('%%#%s# %d: %s %%*', active_hl, t.id, t.label))
    else
      table.insert(parts, string.format('%%#%s# %d: %s %%*', inactive_hl, t.id, t.label))
    end
  end

  return table.concat(parts, '')
end

-- Setup autocommands to invalidate cache and refresh lualine on terminal events
function M.setup()
  local group = vim.api.nvim_create_augroup('UserTerminalTracker', { clear = true })
  vim.api.nvim_create_autocmd({
    'TermOpen',
    'TermClose',
    'BufEnter',
    'BufLeave',
    'WinEnter',
    'WinLeave',
    'TermEnter',
    'TermLeave',
    'ModeChanged',
    'BufWipeout',
    'BufDelete',
  }, {
    group = group,
    callback = function()
      M.invalidate()
      pcall(function() require('lualine').refresh() end)
    end,
    desc = 'Invalidate terminal tracker cache and refresh lualine on lifecycle changes',
  })
end

return M
