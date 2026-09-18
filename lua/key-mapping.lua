--  NOTE: Must happen before plugins are loaded (otherwise wrong leader will be used)
vim.g.mapleader = ' '
vim.g.maplocalleader = ' '

-- Clear highlights on search
vim.keymap.set('n', '<Esc>', '<cmd>nohlsearch<CR>')

-- Exit terminal mode
vim.keymap.set('t', '<Esc><Esc>', '<C-\\><C-n>', { desc = 'Exit Terminal Mode' })

-- Spelling (Clean 2-key length, compact cursor box)
vim.keymap.set('n', '<leader>st', '<cmd>set spell!<CR>', { desc = 'Spelling Toggle' })
vim.keymap.set('n', '<leader>sn', ']s <leader>ss', { desc = 'Next Spell Error', remap = true })
vim.keymap.set('n', '<leader>sp', '[s <leader>ss', { desc = 'Previous Spell Error', remap = true })



-- Navigation: Markdown Table Cells & Function Parameters (<Tab> / <S-Tab>)
vim.keymap.set('n', '<Tab>', function()
  if vim.bo.filetype == 'markdown' then
    local ok, node = pcall(vim.treesitter.get_node)
    if ok and node then
      while node do
        if node:type() == 'pipe_table' or node:type() == 'table' then
          vim.cmd('MkdnTableNextCell')
          return
        end
        node = node:parent()
      end
    end
  end
  -- In code files, jump to next function parameter/argument
  local ok, move = pcall(require, 'nvim-treesitter-textobjects.move')
  if ok and move then
    pcall(move.goto_next_start, '@parameter.inner', 'textobjects')
  end
end, { desc = 'Next Table Cell / Parameter' })

vim.keymap.set('n', '<S-Tab>', function()
  if vim.bo.filetype == 'markdown' then
    local ok, node = pcall(vim.treesitter.get_node)
    if ok and node then
      while node do
        if node:type() == 'pipe_table' or node:type() == 'table' then
          vim.cmd('MkdnTablePrevCell')
          return
        end
        node = node:parent()
      end
    end
  end
  -- In code files, jump to previous function parameter/argument
  local ok, move = pcall(require, 'nvim-treesitter-textobjects.move')
  if ok and move then
    pcall(move.goto_previous_start, '@parameter.inner', 'textobjects')
  end
end, { desc = 'Previous Table Cell / Parameter' })



-- Snacks Zen Mode (Distraction-free mode)
vim.keymap.set('n', '<leader>z', function()
  Snacks.zen()
end, { desc = 'Zen Mode' })

-------------------------------------------------------------------------------
-- Window Analysis & Navigation Helpers
-------------------------------------------------------------------------------

local function get_win_info(win)
  win = win or vim.api.nvim_get_current_win()
  if not vim.api.nvim_win_is_valid(win) then return {} end

  local buf = vim.api.nvim_win_get_buf(win)
  local ft = vim.bo[buf].filetype
  local bname = vim.api.nvim_buf_get_name(buf):lower()

  -- Check File Explorer (Snacks Explorer)
  local is_explorer = ft:match('^snacks_picker') ~= nil or ft:match('^snacks_layout') ~= nil
  if not is_explorer then
    local ok, pickers = pcall(function() return Snacks.picker.get({ source = 'explorer' }) end)
    if ok and pickers and #pickers > 0 then
      for _, p in ipairs(pickers) do
        local wins = { p.win, p.input, p.list, p.preview, p.layout and p.layout.root, p.layout and p.layout.box }
        for _, w in ipairs(wins) do
          if type(w) == 'table' and (w.win == win or w == win) then
            is_explorer = true
            break
          elseif w == win then
            is_explorer = true
            break
          end
        end
        if is_explorer then break end
      end
    end
  end

  -- Check DBUI Drawer
  local is_dbui = ft == 'dbui'

  -- Check OpenCode Terminal
  local is_opencode = ft:match('opencode') ~= nil
    or bname:find('opencode') ~= nil
    or (vim.b[buf].snacks_terminal and tostring(vim.b[buf].snacks_terminal.cmd):find('opencode') ~= nil)

  -- Check Terminal / Database Query Results Table (only if NOT opencode)
  local is_terminal = (not is_opencode) and (ft == 'dbout' or ft == 'snacks_terminal' or ft == 'terminal' or bname:find('term://') ~= nil)

  -- Check Editor
  local is_editor = not is_explorer and not is_dbui and not is_terminal and not is_opencode and ft ~= 'snacks_dashboard'

  return {
    win = win,
    buf = buf,
    ft = ft,
    is_explorer = is_explorer,
    is_dbui = is_dbui,
    is_terminal = is_terminal,
    is_opencode = is_opencode,
    is_editor = is_editor,
  }
end

local function find_win_type(key)
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local info = get_win_info(win)
    if info[key] then
      return win
    end
  end
  return nil
end

local function get_right_sidebar_win()
  local ok, pickers = pcall(function() return Snacks.picker.get({ source = 'explorer' }) end)
  if ok and pickers and #pickers > 0 then
    local p = pickers[1]
    if p.layout and p.layout.root and p.layout.root.win and vim.api.nvim_win_is_valid(p.layout.root.win) then
      return p.layout.root.win
    end
    if p.win and p.win.win and vim.api.nvim_win_is_valid(p.win.win) then
      return p.win.win
    end
  end

  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(win) then
      local buf = vim.api.nvim_win_get_buf(win)
      local ft = vim.bo[buf].filetype
      local bname = vim.api.nvim_buf_get_name(buf):lower()
      if ft == 'dbui' or ft:match('opencode') or bname:find('opencode') then
        return win
      end
    end
  end
  return nil
end

local function ensure_right_sidebar_precedence()
  local r_win = get_right_sidebar_win()
  if r_win and vim.api.nvim_win_is_valid(r_win) then
    vim.api.nvim_win_call(r_win, function()
      vim.cmd('wincmd L')
      local b = vim.api.nvim_win_get_buf(r_win)
      local ft = vim.bo[b].filetype
      local width = (ft == 'dbui' or ft:match('^snacks_')) and 35 or math.max(38, math.floor(vim.o.columns * 0.38))
      vim.cmd('vertical resize ' .. width)
    end)
  end
end

local function get_editor_win()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(win) then
      local buf = vim.api.nvim_win_get_buf(win)
      local ft = vim.bo[buf].filetype
      local buftype = vim.bo[buf].buftype
      local bname = vim.api.nvim_buf_get_name(buf):lower()

      local is_special = (
        ft:match('snacks') ~= nil
        or ft:match('opencode') ~= nil
        or ft:match('^Neogit') ~= nil
        or ft == 'terminal'
        or ft == 'neo-tree'
        or ft == 'dbui'
        or ft == 'dbout'
        or buftype == 'terminal'
        or buftype == 'nofile'
        or bname:find('opencode') ~= nil
        or bname:find('neogit') ~= nil
        or bname:find('term://') ~= nil
      )

      if not is_special then
        return win
      end
    end
  end

  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local info = get_win_info(win)
    if info.is_editor then return win end
  end

  return nil
end

local function prepare_nav()
  if vim.api.nvim_get_mode().mode == 't' then
    vim.cmd('stopinsert')
  end
end

local function try_wincmd(dir)
  prepare_nav()
  local cur_win = vim.api.nvim_get_current_win()
  vim.cmd('wincmd ' .. dir)
  return vim.api.nvim_get_current_win() ~= cur_win
end

-------------------------------------------------------------------------------
-- Unified Right-Side Panel Manager (File Explorer | DBUI | OpenCode AI)
-------------------------------------------------------------------------------

local function get_opencode_cmd()
  local binary = vim.fn.exepath('opencode')
  if binary == '' then
    local opencode_path = vim.fn.expand('~/.opencode/bin/opencode')
    if (vim.uv or vim.loop).fs_stat(opencode_path) then
      binary = opencode_path
    else
      binary = 'opencode'
    end
  end
  return binary .. ' --port'
end

local RightPanel = {
  active_mode = 'explorer', -- Default mode on startup: 'explorer' ('explorer' | 'dbui' | 'opencode')
}

-- Close any currently open right-side panel (preserves background AI session)
function RightPanel.close_all()
  local ok, pickers = pcall(function() return Snacks.picker.get({ source = 'explorer' }) end)
  if ok and pickers and #pickers > 0 then
    for _, p in ipairs(pickers) do
      pcall(function() p:close() end)
    end
  end

  -- Hide OpenCode terminal window if visible without killing the persistent AI session
  local cmd = get_opencode_cmd()
  local ok_t, term = pcall(function() return Snacks.terminal.get(cmd, { create = false }) end)
  if ok_t and term and term:win_valid() then
    pcall(function() term:hide() end)
  end

  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(win) then
      local buf = vim.api.nvim_win_get_buf(win)
      local bname = vim.api.nvim_buf_get_name(buf):lower()
      local ft = vim.bo[buf].filetype
      if ft == 'dbui' then
        pcall(vim.api.nvim_win_close, win, true)
      elseif (ft:match('opencode') or bname:find('opencode')) and not (ok_t and term and term.win == win) then
        pcall(vim.api.nvim_win_close, win, true)
      end
    end
  end
end

-- Open File Explorer on the right (35 cols) and set active_mode = 'explorer'
function RightPanel.open_explorer()
  local info = get_win_info()
  if info.is_explorer then
    RightPanel.close_all()
    local ed = get_editor_win()
    if ed then vim.api.nvim_set_current_win(ed) end
    return
  end

  RightPanel.close_all()
  RightPanel.active_mode = 'explorer'

  local ed = get_editor_win()
  if ed and vim.api.nvim_win_is_valid(ed) then
    vim.api.nvim_set_current_win(ed)
  end

  Snacks.explorer({
    layout = { layout = { position = 'right', width = 35 } },
    jump = { close = false },
  })
end

-- Open Database Explorer on the right (35 cols) and set active_mode = 'dbui'
function RightPanel.open_dbui()
  local info = get_win_info()
  if info.is_dbui then
    RightPanel.close_all()
    local ed = get_editor_win()
    if ed then vim.api.nvim_set_current_win(ed) end
    return
  end

  RightPanel.close_all()
  RightPanel.active_mode = 'dbui'

  local ed = get_editor_win()
  if ed and vim.api.nvim_win_is_valid(ed) then
    vim.api.nvim_set_current_win(ed)
  end

  vim.cmd('DBUI')
end

-- Open OpenCode AI on the right (38% width, persistent background session)
function RightPanel.open_opencode()
  local info = get_win_info()
  if info.is_opencode then
    RightPanel.close_all()
    local ed = get_editor_win()
    if ed then vim.api.nvim_set_current_win(ed) end
    return
  end

  RightPanel.close_all()
  RightPanel.active_mode = 'opencode'

  local ed = get_editor_win()
  if ed and vim.api.nvim_win_is_valid(ed) then
    vim.api.nvim_set_current_win(ed)
  end

  local cmd = get_opencode_cmd()
  Snacks.terminal.toggle(cmd, {
    win = {
      position = 'right',
      width = 0.38,
      relative = 'editor',
      wo = { winbar = '', winfixwidth = true, winfixbuf = true },
    },
  })
end

-- Unified <C-l> Action: Toggle / Move to currently active right-side tool
function RightPanel.toggle_active()
  local info = get_win_info()

  -- 1. If currently inside any right panel: close it!
  if info.is_explorer or info.is_dbui or info.is_opencode then
    RightPanel.close_all()
    local ed = get_editor_win()
    if ed then vim.api.nvim_set_current_win(ed) end
    return
  end

  -- 2. If a right panel is already visible on screen: focus into it!
  local visible_right = find_win_type('is_explorer')
    or find_win_type('is_dbui')
    or find_win_type('is_opencode')
  if visible_right and vim.api.nvim_win_is_valid(visible_right) then
    vim.api.nvim_set_current_win(visible_right)
    return
  end

  -- 3. Otherwise, open active_mode (default: File Explorer)
  if RightPanel.active_mode == 'dbui' then
    RightPanel.open_dbui()
  elseif RightPanel.active_mode == 'opencode' then
    RightPanel.open_opencode()
  else
    RightPanel.open_explorer()
  end
end

_G.RightPanel = RightPanel

-------------------------------------------------------------------------------
-- Unified Bottom-Panel Manager (Persistent Terminals | SQL Results Table)
-------------------------------------------------------------------------------

local BottomPanel = {
  active_mode = 'terminal', -- 'terminal' | 'dbout'
  last_dbout_buf = nil,
  active_terminal_count = 1,
}

-- Helper to close only dbout window if open
local function close_dbout_win()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(win) then
      local buf = vim.api.nvim_win_get_buf(win)
      if vim.bo[buf].filetype == 'dbout' then
        pcall(vim.api.nvim_win_close, win, true)
      end
    end
  end
end

-- Helper to close visible Snacks terminal window without killing the persistent shell
local function hide_terminal_if_visible()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(win) then
      local buf = vim.api.nvim_win_get_buf(win)
      local bname = vim.api.nvim_buf_get_name(buf):lower()
      local ft = vim.bo[buf].filetype
      local is_opencode = ft:match('opencode') ~= nil or bname:find('opencode') ~= nil or (vim.b[buf].snacks_terminal and tostring(vim.b[buf].snacks_terminal.cmd):find('opencode') ~= nil)
      if (ft == 'snacks_terminal' or ft == 'terminal' or bname:find('term://')) and not is_opencode then
        pcall(vim.api.nvim_win_close, win, true)
      end
    end
  end
end

-- Helper to get currently visible bottom terminal window and its instance ID
local function get_visible_terminal_info()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(win) then
      local buf = vim.api.nvim_win_get_buf(win)
      local bname = vim.api.nvim_buf_get_name(buf):lower()
      local ft = vim.bo[buf].filetype
      local is_opencode = ft:match('opencode') ~= nil or bname:find('opencode') ~= nil or (vim.b[buf].snacks_terminal and tostring(vim.b[buf].snacks_terminal.cmd):find('opencode') ~= nil)
      if (ft == 'snacks_terminal' or ft == 'terminal' or bname:find('term://')) and not is_opencode then
        local term_id = vim.b[buf].snacks_terminal and vim.b[buf].snacks_terminal.id or 1
        return win, buf, term_id
      end
    end
  end
  return nil, nil, nil
end

-- Close any open bottom panel (Terminal or SQL Results)
function BottomPanel.close_all()
  close_dbout_win()
  hide_terminal_if_visible()
end

-- Open or toggle the persistent terminal by count (preserves command history & running processes)
function BottomPanel.open_terminal(count)
  local explicit = (count and count > 0 and count) or (vim.v.count > 0 and vim.v.count) or nil
  if explicit then
    BottomPanel.active_terminal_count = explicit
  end
  local target_count = BottomPanel.active_terminal_count or 1

  close_dbout_win()
  BottomPanel.active_mode = 'terminal'

  local vis_win, vis_buf, vis_id = get_visible_terminal_info()
  -- If a DIFFERENT terminal instance is visible, close it first so we don't stack multiple splits
  if vis_win and vis_id ~= target_count then
    pcall(vim.api.nvim_win_close, vis_win, true)
  end

  local ed = get_editor_win()
  if ed and vim.api.nvim_win_is_valid(ed) then
    vim.api.nvim_set_current_win(ed)
  end

  Snacks.terminal.toggle(nil, {
    count = target_count,
    win = {
      position = 'bottom',
      relative = 'win',
      height = 0.38,
      wo = {
        winbar = '',
        winfixheight = true,
        winfixbuf = true,
      },
    },
  })
  vim.schedule(ensure_right_sidebar_precedence)
end

-- Open or toggle the SQL Query Output window (dbout)
function BottomPanel.open_dbout()
  local info = get_win_info()
  if info.is_terminal and vim.bo[info.buf].filetype == 'dbout' then
    close_dbout_win()
    local ed = get_editor_win()
    if ed and vim.api.nvim_win_is_valid(ed) then
      vim.api.nvim_set_current_win(ed)
    end
    return
  end

  -- Find last dbout buffer
  local dbout_buf = BottomPanel.last_dbout_buf
  if not (dbout_buf and vim.api.nvim_buf_is_valid(dbout_buf)) then
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].filetype == 'dbout' then
        dbout_buf = buf
        BottomPanel.last_dbout_buf = buf
        break
      end
    end
  end

  if not dbout_buf or not vim.api.nvim_buf_is_valid(dbout_buf) then
    vim.notify('No query output available yet. Run a query with <leader>br', vim.log.levels.INFO, { title = 'Database' })
    return
  end

  hide_terminal_if_visible()
  BottomPanel.active_mode = 'dbout'
  local ed = get_editor_win()
  if ed and vim.api.nvim_win_is_valid(ed) then
    vim.api.nvim_set_current_win(ed)
  end

  local results_height = math.floor(vim.o.lines * 0.35)
  vim.cmd('belowright ' .. results_height .. 'split')
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, dbout_buf)
  vim.wo[win].winfixheight = true
  vim.wo[win].winfixbuf = true
  vim.schedule(ensure_right_sidebar_precedence)
end

-- Unified <C-j> Action: Toggle / Focus bottom output zone preserving terminal instances & count
function BottomPanel.toggle_active(count)
  local explicit_count = (count and count > 0 and count) or (vim.v.count > 0 and vim.v.count) or nil
  if explicit_count then
    BottomPanel.active_terminal_count = explicit_count
  end
  local target_count = BottomPanel.active_terminal_count or 1

  local info = get_win_info()

  -- 1. If currently inside dbout, close it
  if info.is_terminal and vim.bo[info.buf].filetype == 'dbout' then
    close_dbout_win()
    local ed = get_editor_win()
    if ed and vim.api.nvim_win_is_valid(ed) then
      vim.api.nvim_set_current_win(ed)
    end
    return
  end

  -- 2. If currently inside a terminal:
  if info.is_terminal and vim.bo[info.buf].filetype ~= 'dbout' then
    local current_term_id = (vim.b[info.buf].snacks_terminal and vim.b[info.buf].snacks_terminal.id) or target_count
    -- If no explicit count was passed or requested count matches current terminal: hide it!
    if not explicit_count or explicit_count == current_term_id then
      hide_terminal_if_visible()
      local ed = get_editor_win()
      if ed and vim.api.nvim_win_is_valid(ed) then
        vim.api.nvim_set_current_win(ed)
      end
      return
    else
      -- Explicit count for a different terminal passed: switch to it in the single bottom panel
      BottomPanel.open_terminal(explicit_count)
      return
    end
  end

  -- 3. If currently in an explorer/sidebar, focus existing bottom output or open it
  local existing_bot = find_win_type('is_terminal')
  if existing_bot and vim.api.nvim_win_is_valid(existing_bot) then
    vim.api.nvim_set_current_win(existing_bot)
    return
  end

  -- 4. If in editor and dbout mode is active AND no numeric count was given
  if BottomPanel.active_mode == 'dbout' and not explicit_count and BottomPanel.last_dbout_buf and vim.api.nvim_buf_is_valid(BottomPanel.last_dbout_buf) then
    BottomPanel.open_dbout()
    return
  end

  -- 5. Otherwise, toggle the persistent Snacks terminal with target_count
  BottomPanel.open_terminal(target_count)
end

_G.BottomPanel = BottomPanel

-- Track query results buffer automatically
vim.api.nvim_create_autocmd('FileType', {
  pattern = 'dbout',
  callback = function(args)
    BottomPanel.last_dbout_buf = args.buf
    BottomPanel.active_mode = 'dbout'
  end,
})

-- Track active terminal instance automatically when entering a terminal buffer
vim.api.nvim_create_autocmd({ 'BufEnter', 'TermOpen' }, {
  callback = function(args)
    local st = vim.b[args.buf].snacks_terminal
    if st and st.id and not tostring(st.cmd or ''):find('opencode') then
      BottomPanel.active_terminal_count = st.id
      BottomPanel.active_mode = 'terminal'
    end
  end,
})

-------------------------------------------------------------------------------
-- Smart Buffer Management & Layout Preservation
-------------------------------------------------------------------------------

local function smart_close()
  local cur_win = vim.api.nvim_get_current_win()
  if not vim.api.nvim_win_is_valid(cur_win) then return end

  local cur_buf = vim.api.nvim_win_get_buf(cur_win)
  local info = get_win_info(cur_win)

  -- 1. If inside Right Panel (Explorer, DBUI, AI): close/hide the Right Panel
  if info.is_explorer or info.is_dbui or info.is_opencode then
    RightPanel.close_all()
    local ed = get_editor_win()
    if ed and vim.api.nvim_win_is_valid(ed) then
      vim.api.nvim_set_current_win(ed)
    end
    return
  end

  -- 2. If inside Bottom Panel (Terminal, SQL Results): hide the Bottom Panel
  if info.is_terminal then
    BottomPanel.close_all()
    local ed = get_editor_win()
    if ed and vim.api.nvim_win_is_valid(ed) then
      vim.api.nvim_set_current_win(ed)
    end
    return
  end

  -- 3. If inside Snacks Dashboard: do nothing
  if vim.bo[cur_buf].filetype == 'snacks_dashboard' then
    return
  end

  -- 4. In Code Editor: safely close buffer while preserving window splits!
  local ok, snacks = pcall(require, 'snacks')
  if ok and snacks.bufdelete then
    snacks.bufdelete({ buf = cur_buf })
  else
    vim.cmd('bprevious')
    if vim.api.nvim_get_current_buf() ~= cur_buf then
      pcall(vim.cmd, 'bdelete ' .. cur_buf)
    else
      vim.cmd('enew')
      pcall(vim.cmd, 'bdelete ' .. cur_buf)
    end
  end
end

local function smart_bnext()
  local info = get_win_info()
  if not info.is_editor then
    local ed = get_editor_win()
    if ed and vim.api.nvim_win_is_valid(ed) then
      vim.api.nvim_set_current_win(ed)
    end
  end
  vim.cmd('bnext')
end

local function smart_bprev()
  local info = get_win_info()
  if not info.is_editor then
    local ed = get_editor_win()
    if ed and vim.api.nvim_win_is_valid(ed) then
      vim.api.nvim_set_current_win(ed)
    end
  end
  vim.cmd('bprevious')
end

vim.keymap.set('n', '<leader>q', smart_close, { desc = 'Close Buffer' })
vim.keymap.set('n', '<leader>Q', '<cmd>confirm qa<CR>', { desc = 'Quit Neovim' })
vim.keymap.set('n', '<leader><Tab>', smart_bnext, { desc = 'Next Buffer' })
vim.keymap.set('n', '<leader><S-Tab>', smart_bprev, { desc = 'Previous Buffer' })
vim.keymap.set('n', '<leader>r', '<C-6>', { desc = 'Alternate Buffer' })

-------------------------------------------------------------------------------
-- Window Split Management (<leader>w)
-------------------------------------------------------------------------------

local function editor_split(direction)
  local ed = get_editor_win()
  if ed and vim.api.nvim_win_is_valid(ed) then
    vim.api.nvim_set_current_win(ed)
  end
  if direction == 'horizontal' then
    vim.cmd('split')
  else
    vim.cmd('vsplit')
  end
end

vim.keymap.set('n', '<leader>ws', function() editor_split('horizontal') end, { desc = 'Split Horizontally' })
vim.keymap.set('n', '<leader>wv', function() editor_split('vertical') end, { desc = 'Split Vertically' })
vim.keymap.set('n', '<leader>we', function() _G.reset_window_layout() end, { desc = 'Balance Window Splits' })
vim.keymap.set('n', '<leader>wq', '<cmd>close<CR>', { desc = 'Close Window Split' })
vim.keymap.set('n', '<leader>wo', function()
  local ed = get_editor_win()
  if ed and vim.api.nvim_win_is_valid(ed) then
    vim.api.nvim_set_current_win(ed)
    vim.cmd('only')
  end
end, { desc = 'Close Other Splits' })

-------------------------------------------------------------------------------
-- Session Stability & Database Isolation: Save only clean editor files
-------------------------------------------------------------------------------

local session_stability_group = vim.api.nvim_create_augroup('UserSessionStability', { clear = true })

local function is_database_or_transient_buf(buf)
  if not vim.api.nvim_buf_is_valid(buf) then return false end
  local ft = vim.bo[buf].filetype
  if ft == 'dbui' or ft == 'dbout' or ft == 'snacks_dashboard' or ft == 'snacks_terminal' then return true end
  local bname = vim.api.nvim_buf_get_name(buf)
  if bname:find('/db_ui/') ~= nil then return true end
  if bname:match('%.sqlite%d?$') or bname:match('%.db$') then return true end
  if vim.b[buf].dbui_db_key_name ~= nil then return true end
  return false
end

local function cleanup_panels_before_save()
  if _G.RightPanel and _G.RightPanel.close_all then
    _G.RightPanel.close_all()
  end
  if _G.BottomPanel and _G.BottomPanel.close_all then
    _G.BottomPanel.close_all()
  end

  -- Close any floating windows or auxiliary windows showing database buffers
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(win) then
      local cfg = vim.api.nvim_win_get_config(win)
      if cfg.relative ~= '' then
        pcall(vim.api.nvim_win_close, win, true)
      else
        local buf = vim.api.nvim_win_get_buf(win)
        if is_database_or_transient_buf(buf) and #vim.api.nvim_list_wins() > 1 then
          pcall(vim.api.nvim_win_close, win, true)
        end
      end
    end
  end

  -- Delete all database and transient buffers from memory so mksession never writes them
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if is_database_or_transient_buf(buf) then
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
  end
end

local function get_real_editor_bufs()
  local real_bufs = {}
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buflisted and vim.bo[buf].buftype == '' and vim.api.nvim_buf_get_name(buf) ~= '' then
      if not is_database_or_transient_buf(buf) then
        table.insert(real_bufs, buf)
      end
    end
  end
  return real_bufs
end

-- Snacks Dashboard (Clean transition without corrupting window splits or session)
vim.keymap.set('n', '<leader>d', function()
  if vim.bo.filetype == 'snacks_dashboard' then
    return
  end
  cleanup_panels_before_save()
  local real_bufs = get_real_editor_bufs()
  if #real_bufs > 0 then
    pcall(function() require('persistence').save() end)
  end
  vim.cmd('only')
  Snacks.dashboard.open({ win = vim.api.nvim_get_current_win() })
end, { desc = 'Dashboard' })

-------------------------------------------------------------------------------
-- Layout Permanence & Window Locking Autocommands
-------------------------------------------------------------------------------

local layout_lock_group = vim.api.nvim_create_augroup('UserLayoutLock', { clear = true })

vim.api.nvim_create_autocmd({ 'FileType', 'BufWinEnter' }, {
  group = layout_lock_group,
  pattern = '*',
  callback = function(args)
    local buf = args.buf
    if not vim.api.nvim_buf_is_valid(buf) then return end

    local ft = vim.bo[buf].filetype
    local buftype = vim.bo[buf].buftype
    local bname = vim.api.nvim_buf_get_name(buf):lower()

    local is_sidebar = ft == 'dbui'
      or ft:match('opencode') ~= nil
      or bname:find('opencode') ~= nil
      or ft:match('^snacks_picker') ~= nil
      or ft:match('^snacks_layout') ~= nil

    local is_bottom = (not is_sidebar) and (
      ft == 'dbout'
      or ft == 'snacks_terminal'
      or ft == 'terminal'
      or buftype == 'terminal'
      or bname:find('term://') ~= nil
      or ft == 'qf'
    )

    if is_sidebar then
      vim.bo[buf].buflisted = false
      vim.schedule(function()
        local win = vim.fn.bufwinid(buf)
        if win and win ~= -1 and vim.api.nvim_win_is_valid(win) then
          vim.wo[win].winfixbuf = true
          vim.wo[win].winfixwidth = true
        end
      end)
    elseif is_bottom then
      vim.bo[buf].buflisted = false
      vim.schedule(function()
        local win = vim.fn.bufwinid(buf)
        if win and win ~= -1 and vim.api.nvim_win_is_valid(win) then
          vim.wo[win].winfixbuf = true
          vim.wo[win].winfixheight = true
          ensure_right_sidebar_precedence()
        end
      end)
    end
  end,
})

vim.api.nvim_create_autocmd('User', {
  pattern = 'PersistenceSavePre',
  group = session_stability_group,
  callback = cleanup_panels_before_save,
})

vim.api.nvim_create_autocmd('VimLeavePre', {
  group = session_stability_group,
  callback = function()
    cleanup_panels_before_save()
    local real_bufs = get_real_editor_bufs()
    -- If no real project files are open (e.g. only database was opened), prevent saving an empty/corrupted session
    if #real_bufs == 0 then
      pcall(function() require('persistence').stop() end)
    end
  end,
})

local function handle_post_session_load()
  vim.schedule(function()
    -- Close any ghost panels or database windows restored from old session files
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_is_valid(win) then
        local buf = vim.api.nvim_win_get_buf(win)
        if is_database_or_transient_buf(buf) then
          if #vim.api.nvim_list_wins() > 1 then
            pcall(vim.api.nvim_win_close, win, true)
          end
          pcall(vim.api.nvim_buf_delete, buf, { force = true })
        end
      end
    end

    -- If any window is stuck on snacks_dashboard or empty [No Name], clean it up
    local real_bufs = get_real_editor_bufs()
    if #real_bufs > 0 then
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_is_valid(win) then
          local b = vim.api.nvim_win_get_buf(win)
          local ft = vim.bo[b].filetype
          local bname = vim.api.nvim_buf_get_name(b)
          if ft == 'snacks_dashboard' then
            if #vim.api.nvim_list_wins() > 1 then
              pcall(vim.api.nvim_win_close, win, true)
            else
              pcall(vim.api.nvim_win_set_buf, win, real_bufs[1])
            end
          elseif bname == '' and not vim.bo[b].modified and vim.bo[b].buftype == '' then
            pcall(vim.api.nvim_win_set_buf, win, real_bufs[1])
          end
        end
      end
    end
  end)
end

vim.api.nvim_create_autocmd('User', {
  pattern = 'PersistenceLoadPost',
  group = session_stability_group,
  callback = handle_post_session_load,
})

vim.api.nvim_create_autocmd('SessionLoadPost', {
  group = session_stability_group,
  callback = handle_post_session_load,
})



-------------------------------------------------------------------------------
-- Spatial Navigation Keybindings
-------------------------------------------------------------------------------

-- <C-l>: Right Panel Focus & Toggle (File Explorer | DBUI | OpenCode AI)
vim.keymap.set({ 'n', 't', 'i' }, '<C-l>', function()
  RightPanel.toggle_active()
end, { desc = 'Right Panel' })

-- <C-h>: Move Left to Code Editor (from right panel or between editor splits)
vim.keymap.set({ 'n', 't', 'i' }, '<C-h>', function()
  local info = get_win_info()

  -- If currently inside any right-side panel, jump directly back into the Code Editor
  if info.is_explorer or info.is_dbui or info.is_opencode then
    local ed = get_editor_win()
    if ed and vim.api.nvim_win_is_valid(ed) then
      vim.api.nvim_set_current_win(ed)
    end
    return
  end

  -- Move left between code editor splits if any exist
  try_wincmd('h')
end, { desc = 'Editor Left' })

-- <C-k>: Move Up to Code Editor (from terminal / results)
vim.keymap.set({ 'n', 't', 'i' }, '<C-k>', function()
  local info = get_win_info()
  if info.is_terminal then
    local ed = get_editor_win()
    if ed and vim.api.nvim_win_is_valid(ed) then
      vim.api.nvim_set_current_win(ed)
    end
    return
  end
  try_wincmd('k')
end, { desc = 'Editor Up' })

-- <C-j>: Bottom Output Focus & Toggle (Terminal | SQL Results)
vim.keymap.set({ 'n', 't', 'i' }, '<C-j>', function()
  local count = vim.v.count > 0 and vim.v.count or nil
  BottomPanel.toggle_active(count)
end, { desc = 'Bottom Output' })

-- <leader>/: Direct Terminal Toggle & Switch Bottom Mode
vim.keymap.set({ 'n', 't' }, '<leader>/', function()
  local count = vim.v.count > 0 and vim.v.count or nil
  BottomPanel.open_terminal(count)
end, { desc = 'Terminal' })

-------------------------------------------------------------------------------
-- Window Resizing & Default Layout Reset (<M-h/j/k/l> & <C-w>=)
-------------------------------------------------------------------------------

-- Smart width resizing: handles right-side explorer expansion on <M-h>
local function smart_resize_width(delta)
  local cur_win = vim.api.nvim_get_current_win()
  if not vim.api.nvim_win_is_valid(cur_win) then return end

  local info = get_win_info(cur_win)

  -- On right-side panels (Explorer, DBUI, AI), <M-h> pulls border left (expands), <M-l> pushes border right (shrinks)
  if info.is_explorer or info.is_dbui or info.is_opencode then
    delta = -delta
  end

  local cur_w = vim.api.nvim_win_get_width(cur_win)
  local new_w = math.max(12, cur_w + delta)
  pcall(vim.api.nvim_win_set_width, cur_win, new_w)
end

-- Smart height resizing
local function smart_resize_height(delta)
  local cur_win = vim.api.nvim_get_current_win()
  if not vim.api.nvim_win_is_valid(cur_win) then return end

  local cur_h = vim.api.nvim_win_get_height(cur_win)
  local new_h = math.max(4, cur_h + delta)
  pcall(vim.api.nvim_win_set_height, cur_win, new_h)
end

-- Reset and balance all windows back to clean default IDE geometry
local function reset_window_layout()
  local default_bot_height = math.floor(vim.o.lines * 0.4)

  -- Balance all editor splits
  local cur = vim.api.nvim_get_current_win()
  vim.cmd('wincmd =')

  -- Re-apply exact sidebar widths and bottom panel heights
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(win) then
      local buf = vim.api.nvim_win_get_buf(win)
      local ft = vim.bo[buf].filetype
      local bname = vim.api.nvim_buf_get_name(buf):lower()

      if ft == 'dbui' or ft:match('^snacks_') then
        pcall(vim.api.nvim_win_set_width, win, 35)
      elseif ft:match('opencode') or bname:find('opencode') then
        pcall(vim.api.nvim_win_set_width, win, math.floor(vim.o.columns * 0.38))
      elseif (ft == 'dbout' or ft == 'snacks_terminal' or ft == 'terminal' or bname:find('term://')) and not (ft:match('opencode') or bname:find('opencode')) then
        pcall(vim.api.nvim_win_set_height, win, default_bot_height)
      end
    end
  end

  ensure_right_sidebar_precedence()

  if vim.api.nvim_win_is_valid(cur) then
    vim.api.nvim_set_current_win(cur)
  end
end

_G.smart_resize_width = smart_resize_width
_G.smart_resize_height = smart_resize_height

vim.keymap.set('n', '<C-w>=', reset_window_layout, { desc = 'Reset Default Window Layout' })

-- Alt + h/j/k/l continuous smart split resizing across Normal, Insert, and Terminal modes
vim.keymap.set({ 'n', 'i', 't' }, '<M-h>', function() smart_resize_width(-3) end, { desc = 'Resize Width / Expand Explorer' })
vim.keymap.set({ 'n', 'i', 't' }, '<M-l>', function() smart_resize_width(3) end, { desc = 'Resize Width / Shrink Explorer' })
vim.keymap.set({ 'n', 'i', 't' }, '<M-k>', function() smart_resize_height(2) end, { desc = 'Expand Bottom Height +2' })
vim.keymap.set({ 'n', 'i', 't' }, '<M-j>', function() smart_resize_height(-2) end, { desc = 'Shrink Bottom Height -2' })
