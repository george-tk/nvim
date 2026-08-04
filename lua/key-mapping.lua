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

-- Buffer Management (Preserved 100%)
vim.keymap.set('n', '<leader><Tab>', ':bn<CR>', { desc = 'Next Buffer' })
vim.keymap.set('n', '<leader><S-Tab>', ':bp<CR>', { desc = 'Previous Buffer' })
vim.keymap.set('n', '<leader>q', ':bd<CR>', { desc = 'Close Buffer' })
vim.keymap.set('n', '<leader>r', '<C-6>', { desc = 'Alternate Buffer' })

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

-- Snacks Dashboard
vim.keymap.set('n', '<leader>d', function()
  if vim.bo.filetype == 'snacks_dashboard' then
    return
  end
  pcall(function() require('persistence').save() end)
  Snacks.dashboard.open({ win = vim.api.nvim_get_current_win() })
  local dashboard_buf = vim.api.nvim_get_current_buf()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if buf ~= dashboard_buf and vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buflisted then
      vim.cmd('silent! bd ' .. buf)
    end
  end
end, { desc = 'Dashboard' })

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
  local is_explorer = ft:match('snacks_picker') ~= nil or vim.b[buf].snacks_type == 'explorer'
  if not is_explorer then
    local ok, pickers = pcall(function() return Snacks.picker.get({ source = 'explorer' }) end)
    if ok and pickers and #pickers > 0 then
      for _, p in ipairs(pickers) do
        for _, w in ipairs({ p.win, p.input, p.list, p.preview }) do
          if type(w) == 'table' and w.win == win then
            is_explorer = true
            break
          end
        end
      end
    end
  end

  -- Check DBUI Drawer
  local is_dbui = ft == 'dbui'

  -- Check OpenCode Terminal
  local is_opencode = ft:match('opencode') ~= nil or bname:find('opencode') ~= nil

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
        or ft == 'terminal'
        or ft == 'neo-tree'
        or ft == 'dbui'
        or ft == 'dbout'
        or buftype == 'terminal'
        or buftype == 'nofile'
        or bname:find('opencode') ~= nil
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

local RightPanel = {
  active_mode = 'explorer', -- Default mode on startup: 'explorer' ('explorer' | 'dbui' | 'opencode')
}

-- Close any currently open right-side panel
function RightPanel.close_all()
  local ok, pickers = pcall(function() return Snacks.picker.get({ source = 'explorer' }) end)
  if ok and pickers and #pickers > 0 then
    for _, p in ipairs(pickers) do
      pcall(function() p:close() end)
    end
  end

  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(win) then
      local buf = vim.api.nvim_win_get_buf(win)
      local bname = vim.api.nvim_buf_get_name(buf):lower()
      local ft = vim.bo[buf].filetype
      if ft == 'dbui' or ft:match('opencode') or bname:find('opencode') then
        pcall(vim.api.nvim_win_close, win, true)
      end
    end
  end
end

-- Open File Explorer on the right (25 cols) and set active_mode = 'explorer'
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
  Snacks.explorer({ layout = { layout = { position = 'right', width = 25 } } })
end

-- Open Database Explorer on the right (25 cols) and set active_mode = 'dbui'
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
  vim.cmd('DBUI')
end

-- Open OpenCode AI on the right (38% width) and set active_mode = 'opencode'
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
  local binary = vim.fn.exepath('opencode')
  if binary == '' then binary = vim.fn.expand('~/.opencode/bin/opencode') end
  Snacks.terminal.open(binary .. ' --port', { win = { position = 'right', width = 0.38, relative = 'editor', wo = { winbar = '' } } })
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
  local visible_right = find_win_type('is_explorer') or find_win_type('is_dbui') or find_win_type('is_opencode')
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
      if ft == 'snacks_terminal' or ft == 'terminal' or bname:find('term://') then
        pcall(vim.api.nvim_win_close, win, true)
      end
    end
  end
end

-- Close any open bottom panel (Terminal or SQL Results)
function BottomPanel.close_all()
  close_dbout_win()
  hide_terminal_if_visible()
end

-- Open or toggle the persistent terminal by count (preserves command history & running processes)
function BottomPanel.open_terminal(count)
  count = count or vim.v.count1
  close_dbout_win()
  BottomPanel.active_mode = 'terminal'

  local ed = get_editor_win()
  if ed and vim.api.nvim_win_is_valid(ed) then
    vim.api.nvim_set_current_win(ed)
  end

  Snacks.terminal.toggle(nil, {
    count = count,
    win = {
      position = 'bottom',
      relative = 'win',
      height = 0.4,
      wo = { winbar = '' },
    },
  })
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
end

-- Unified <C-j> Action: Toggle / Focus bottom output zone preserving terminal instances & count
function BottomPanel.toggle_active(count)
  count = count or vim.v.count1
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

  -- 2. If currently inside a terminal and count is NOT explicitly passed, toggle/hide it
  if info.is_terminal and vim.bo[info.buf].filetype ~= 'dbout' and vim.v.count == 0 then
    Snacks.terminal.toggle(nil, { count = count })
    return
  end

  -- 3. If currently in an explorer/sidebar, focus existing bottom output or open it
  local existing_bot = find_win_type('is_terminal')
  if existing_bot and vim.api.nvim_win_is_valid(existing_bot) then
    vim.api.nvim_set_current_win(existing_bot)
    return
  end

  -- 4. If in editor and dbout mode is active AND no numeric count was given
  if BottomPanel.active_mode == 'dbout' and vim.v.count == 0 and BottomPanel.last_dbout_buf and vim.api.nvim_buf_is_valid(BottomPanel.last_dbout_buf) then
    BottomPanel.open_dbout()
    return
  end

  -- 5. Otherwise, toggle the persistent Snacks terminal with requested count
  BottomPanel.open_terminal(count)
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
  BottomPanel.toggle_active(vim.v.count1)
end, { desc = 'Bottom Output' })

-- <leader>/: Direct Terminal Toggle & Switch Bottom Mode
vim.keymap.set({ 'n', 't' }, '<leader>/', function()
  BottomPanel.open_terminal(vim.v.count1)
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

      if ft == 'dbui' or vim.b[buf].snacks_type == 'explorer' then
        pcall(vim.api.nvim_win_set_width, win, 25)
      elseif ft:match('opencode') or bname:find('opencode') then
        pcall(vim.api.nvim_win_set_width, win, math.floor(vim.o.columns * 0.38))
      elseif ft == 'dbout' or ft == 'snacks_terminal' or ft == 'terminal' or bname:find('term://') then
        pcall(vim.api.nvim_win_set_height, win, default_bot_height)
      end
    end
  end

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
