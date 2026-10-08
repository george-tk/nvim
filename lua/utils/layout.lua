-- lua/utils/layout.lua
-- Unified 3-Zone IDE Layout Engine (Editor | Right Sidebar | Bottom Panel)

local Layout = {}

-------------------------------------------------------------------------------
-- Panel State Tables
-------------------------------------------------------------------------------

local RightPanel = {
  custom_widths = {},
  active_mode = 'explorer', -- 'explorer' | 'dbui' | 'opencode'
  has_custom_editor_widths = false,
  has_custom_bottom_widths = false,
}

local BottomPanel = {
  active_mode = 'terminal', -- 'terminal' | 'dbout'
  active_terminal_count = 1,
  last_dbout_buf = nil,
}

-------------------------------------------------------------------------------
-- Window Classification & Detection Helpers
-------------------------------------------------------------------------------

local function get_win_info(win)
  win = win or vim.api.nvim_get_current_win()
  if not vim.api.nvim_win_is_valid(win) then return {} end

  local buf = vim.api.nvim_win_get_buf(win)
  local ft = vim.bo[buf].filetype
  local bname = vim.api.nvim_buf_get_name(buf):lower()

  -- Check explicit buffer tag first
  local zone = vim.b[buf].panel_zone
  local ptype = vim.b[buf].panel_type

  local is_explorer = (ptype == 'explorer') or (ft:match('^snacks_picker') ~= nil or ft:match('^snacks_layout') ~= nil)
  local is_dbui = (ptype == 'dbui') or (ft == 'dbui' or ft == 'sqmeow-drawer' or bname:find('sqmeow://drawer') ~= nil)
  local is_opencode = (ptype == 'opencode') or (ft:match('opencode') ~= nil or bname:find('opencode') ~= nil or (vim.b[buf].snacks_terminal and vim.b[buf].snacks_terminal.cmd and tostring(vim.b[buf].snacks_terminal.cmd):find('opencode') ~= nil))

  -- Right panel zone takes absolute precedence over bottom terminal
  if is_explorer or is_dbui or is_opencode or zone == 'right' then
    return {
      win = win,
      buf = buf,
      ft = ft,
      zone = 'right',
      is_explorer = is_explorer,
      is_dbui = is_dbui,
      is_opencode = is_opencode,
      is_terminal = false,
      is_editor = false,
    }
  end

  local is_dbout = (ptype == 'dbout') or (ft == 'dbout' or ft == 'sqmeow-result' or bname:find('sqmeow://result') ~= nil)
  local is_term = (ptype == 'terminal') or (ft == 'snacks_terminal' or ft == 'terminal' or vim.bo[buf].buftype == 'terminal' or bname:find('term://') ~= nil)
  local is_terminal = (zone == 'bottom') or is_dbout or is_term

  local is_editor = not is_terminal and ft ~= 'snacks_dashboard'

  return {
    win = win,
    buf = buf,
    ft = ft,
    zone = is_terminal and 'bottom' or (is_editor and 'editor' or 'unknown'),
    is_explorer = false,
    is_dbui = false,
    is_opencode = false,
    is_terminal = is_terminal,
    is_editor = is_editor,
  }
end

local function find_win_type(key)
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(win) then
      local cfg = vim.api.nvim_win_get_config(win)
      if not cfg.relative or cfg.relative == '' then
        local info = get_win_info(win)
        if info[key] then
          return win
        end
      end
    end
  end
  return nil
end

local function get_right_sidebar_win()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(win) then
      local cfg = vim.api.nvim_win_get_config(win)
      if not cfg.relative or cfg.relative == '' then
        local info = get_win_info(win)
        if info.is_explorer or info.is_dbui or info.is_opencode then
          return win
        end
      end
    end
  end
  return nil
end

local function get_editor_win()
  local cur = vim.api.nvim_get_current_win()
  local cfg = vim.api.nvim_win_get_config(cur)
  if (not cfg.relative or cfg.relative == '') and get_win_info(cur).is_editor then
    return cur
  end

  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(win) then
      local wcfg = vim.api.nvim_win_get_config(win)
      if not wcfg.relative or wcfg.relative == '' then
        local info = get_win_info(win)
        if info.is_editor then
          return win
        end
      end
    end
  end
  return nil
end

-------------------------------------------------------------------------------
-- Layout Geometry, Sizing & Precedence
-------------------------------------------------------------------------------

local function equalize_splits()
  local editor_wins = {}
  local bottom_wins = {}
  local sidebar_w = 0
  local has_sidebar = false

  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(w) then
      local cfg = vim.api.nvim_win_get_config(w)
      if not cfg.relative or cfg.relative == '' then
        local info = get_win_info(w)
        if info.is_explorer or info.is_dbui or info.is_opencode then
          has_sidebar = true
          sidebar_w = math.max(sidebar_w, vim.api.nvim_win_get_width(w))
        elseif info.is_terminal then
          table.insert(bottom_wins, w)
        elseif info.is_editor then
          table.insert(editor_wins, w)
        end
      end
    end
  end

  local avail_w = vim.o.columns - (has_sidebar and (sidebar_w + 1) or 0)

  local function balance_group(wins, has_custom_flag)
    if #wins <= 1 then return end
    table.sort(wins, function(a, b)
      return vim.api.nvim_win_get_position(a)[2] < vim.api.nvim_win_get_position(b)[2]
    end)

    local n = #wins
    local seps = n - 1
    local net_w = avail_w - seps
    if net_w <= 0 then return end

    if not has_custom_flag then
      local target = math.floor(net_w / n)
      for i = 1, n - 1 do
        pcall(vim.api.nvim_win_set_width, wins[i], target)
      end
    else
      for i = 1, n - 1 do
        local r = vim.w[wins[i]].custom_split_ratio or (1 / n)
        local target = math.max(12, math.floor(net_w * r))
        pcall(vim.api.nvim_win_set_width, wins[i], target)
      end
    end
  end

  balance_group(editor_wins, RightPanel.has_custom_editor_widths)
  balance_group(bottom_wins, RightPanel.has_custom_bottom_widths)
end

local function ensure_right_sidebar_precedence()
  local r_win = get_right_sidebar_win()
  if r_win and vim.api.nvim_win_is_valid(r_win) then
    vim.api.nvim_win_call(r_win, function()
      vim.cmd('wincmd L')
      local info = get_win_info(r_win)
      local custom = RightPanel.custom_widths or {}
      local width
      if info.is_opencode then
        width = custom['opencode'] or math.max(45, math.floor(vim.o.columns * 0.38))
      elseif info.is_dbui then
        width = custom['dbui'] or 35
      else
        width = custom['explorer'] or 35
      end
      vim.cmd('vertical resize ' .. width)
    end)
  end
  equalize_splits()
end

local function reset_window_layout()
  local default_bot_height = math.floor(vim.o.lines * 0.38)

  RightPanel.custom_widths = {}
  RightPanel.has_custom_editor_widths = false
  RightPanel.has_custom_bottom_widths = false

  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(win) then
      vim.w[win].custom_split_ratio = nil
    end
  end

  local r_win = get_right_sidebar_win()
  if r_win and vim.api.nvim_win_is_valid(r_win) then
    vim.api.nvim_win_call(r_win, function()
      vim.cmd('wincmd L')
      local info = get_win_info(r_win)
      local width = info.is_opencode and math.max(45, math.floor(vim.o.columns * 0.38)) or 35
      vim.cmd('vertical resize ' .. width)
    end)
  end

  local bot_win = find_win_type('is_terminal')
  if bot_win and vim.api.nvim_win_is_valid(bot_win) then
    pcall(vim.api.nvim_win_set_height, bot_win, default_bot_height)
  end

  equalize_splits()
  vim.notify('Window layout reset & balanced', vim.log.levels.INFO, { title = 'Layout' })
end

local function prepare_nav()
  if vim.api.nvim_get_mode().mode == 't' then
    vim.cmd('stopinsert')
  end
end

local function try_wincmd(dir)
  local cur_winnr = vim.fn.winnr()
  vim.cmd('wincmd ' .. dir)
  return vim.fn.winnr() ~= cur_winnr
end

-------------------------------------------------------------------------------
-- Unified Right-Side Panel Manager (Explorer | DBUI | OpenCode AI)
-------------------------------------------------------------------------------

local function get_opencode_cmd()
  local binary = vim.fn.exepath('opencode')
  if binary == '' then
    local fallback = vim.fn.expand('~/.opencode/bin/opencode')
    if (vim.uv or vim.loop).fs_stat(fallback) then
      binary = fallback
    else
      binary = 'opencode'
    end
  end
  return binary .. ' --port'
end

function RightPanel.close_all()
  local closed = false

  -- Close Snacks File Explorer picker if open
  local ok, pickers = pcall(function() return Snacks.picker.get({ source = 'explorer' }) end)
  if ok and pickers and #pickers > 0 then
    for _, p in ipairs(pickers) do
      pcall(function() p:close() end)
      closed = true
    end
  end

  -- Close Database Explorer Drawer (sqmeow)
  local ok_v, view_api = pcall(require, 'sqmeow.api.view')
  if ok_v and view_api and view_api.close_drawer then
    pcall(view_api.close_drawer)
  end

  -- Close visible OpenCode terminal without killing background session
  local opencode_cmd = get_opencode_cmd()
  local opencode_term = Snacks.terminal.get(opencode_cmd, { create = false })
  if opencode_term and opencode_term.win and vim.api.nvim_win_is_valid(opencode_term.win) then
    pcall(function() opencode_term:hide() end)
    closed = true
  end

  -- Fallback: check all open windows for any lingering right-side panels
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(win) then
      local info = get_win_info(win)
      if info.is_explorer or info.is_dbui or info.is_opencode then
        pcall(vim.api.nvim_win_close, win, true)
        closed = true
      end
    end
  end

  equalize_splits()
  return closed
end

local function ensure_explorer_git_ready(cwd)
  local ok, git = pcall(require, 'snacks.explorer.git')
  if ok and git and git.update then
    local target_cwd = cwd or vim.fn.getcwd()
    pcall(git.update, target_cwd, { untracked = true })
  end
end

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

  ensure_explorer_git_ready()

  local width_opt = (RightPanel.custom_widths and RightPanel.custom_widths['explorer']) or 35

  Snacks.explorer({
    layout = { layout = { position = 'right', width = width_opt } },
    jump = { close = false },
  })
  vim.schedule(ensure_right_sidebar_precedence)
end

function RightPanel.open_dbui()
  local info = get_win_info()
  if info.is_dbui then
    RightPanel.close_all()
    local ed = get_editor_win()
    if ed then vim.api.nvim_set_current_win(ed) end
    return
  end

  local existing_dbui = find_win_type('is_dbui')
  if existing_dbui and vim.api.nvim_win_is_valid(existing_dbui) then
    vim.api.nvim_set_current_win(existing_dbui)
    return
  end

  RightPanel.close_all()
  RightPanel.active_mode = 'dbui'

  if _G.DatabaseUtils and _G.DatabaseUtils.open_drawer then
    _G.DatabaseUtils.open_drawer()
  elseif vim.fn.exists(':Sqmeow') == 2 then
    vim.cmd('Sqmeow drawer')
  elseif vim.fn.exists(':DBUI') == 2 then
    vim.cmd('DBUI')
  end
  vim.schedule(ensure_right_sidebar_precedence)
end

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

  local width_opt = (RightPanel.custom_widths and RightPanel.custom_widths['opencode']) or 0.38
  local cmd = get_opencode_cmd()

  Snacks.terminal.toggle(cmd, {
    win = {
      position = 'right',
      width = width_opt,
      relative = 'editor',
      wo = { winbar = '', winfixwidth = true, winfixbuf = true },
      on_buf = function(term)
        vim.b[term.buf].panel_zone = 'right'
        vim.b[term.buf].panel_type = 'opencode'
        vim.keymap.set('t', '<leader>t', '<Space>t', { buffer = term.buf, noremap = true, silent = true })
      end,
    },
  })
  vim.schedule(ensure_right_sidebar_precedence)
end

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

  -- 3. Otherwise: open the currently active right-side tool
  local mode = RightPanel.active_mode or 'explorer'
  if mode == 'opencode' then
    RightPanel.open_opencode()
  elseif mode == 'dbui' then
    RightPanel.open_dbui()
  else
    RightPanel.open_explorer()
  end
end

RightPanel.get_editor_win = get_editor_win

-------------------------------------------------------------------------------
-- Unified Bottom-Panel Manager (Persistent Terminals | SQL Results)
-------------------------------------------------------------------------------

local function close_dbout_win()
  local ok_v, view_api = pcall(require, 'sqmeow.api.view')
  if ok_v and view_api and view_api.close then
    pcall(view_api.close)
  end

  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(win) then
      local buf = vim.api.nvim_win_get_buf(win)
      local ft = vim.bo[buf].filetype
      local name = vim.api.nvim_buf_get_name(buf)
      if (ft == 'dbout' or ft == 'sqmeow-result' or name:find('sqmeow://result')) and not name:find('drawer') then
        pcall(vim.api.nvim_win_close, win, true)
      end
    end
  end
end

local function hide_terminal_if_visible()
  local tracker_ok, tracker = pcall(require, 'utils.terminal-tracker')
  if tracker_ok and tracker.get_terminals then
    tracker.invalidate()
    local terms = tracker.get_terminals()
    for _, t in ipairs(terms) do
      if t.term then
        pcall(function() t.term:hide() end)
      end
    end
  end

  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(win) then
      local info = get_win_info(win)
      if info.is_terminal and vim.bo[info.buf].filetype ~= 'dbout' and vim.bo[info.buf].filetype ~= 'sqmeow-result' then
        pcall(vim.api.nvim_win_close, win, true)
      end
    end
  end
end

local function get_visible_terminal_info()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(win) then
      local info = get_win_info(win)
      if info.is_terminal and vim.bo[info.buf].filetype ~= 'dbout' and vim.bo[info.buf].filetype ~= 'sqmeow-result' then
        local st = vim.b[info.buf].snacks_terminal
        local term_id = st and st.id or 1
        return win, info.buf, term_id
      end
    end
  end
  return nil, nil, nil
end

function BottomPanel.close_all()
  hide_terminal_if_visible()
  close_dbout_win()
  equalize_splits()
  pcall(function()
    require('utils.terminal-tracker').invalidate()
    require('lualine').refresh()
  end)
end

function BottomPanel.open_terminal(count)
  local explicit = (count and count > 0 and count) or (vim.v.count > 0 and vim.v.count) or nil
  if explicit then
    BottomPanel.active_terminal_count = explicit
  end
  local target_count = BottomPanel.active_terminal_count or 1

  close_dbout_win()
  BottomPanel.active_mode = 'terminal'

  local vis_win, vis_buf, vis_id = get_visible_terminal_info()

  -- If the requested terminal is already visible and no explicit count was given: toggle/hide it
  if vis_win and vis_id == target_count and not explicit then
    hide_terminal_if_visible()
    local ed = get_editor_win()
    if ed and vim.api.nvim_win_is_valid(ed) then
      vim.api.nvim_set_current_win(ed)
    end
    pcall(function()
      require('utils.terminal-tracker').invalidate()
      require('lualine').refresh()
    end)
    return
  end

  if vis_win and vis_id ~= target_count then
    hide_terminal_if_visible()
  end

  local ed = get_editor_win()
  if ed and vim.api.nvim_win_is_valid(ed) then
    vim.api.nvim_set_current_win(ed)
  end

  local win_opts = {
    position = 'bottom',
    relative = 'editor',
    height = 0.38,
    wo = {
      winbar = '',
      winfixheight = true,
      winfixbuf = true,
    },
  }

  local target_term = Snacks.terminal.get(nil, {
    count = target_count,
    create = true,
    win = win_opts,
  })
  if target_term then
    target_term:show()
    if target_term.buf and vim.api.nvim_buf_is_valid(target_term.buf) then
      vim.b[target_term.buf].panel_zone = 'bottom'
      vim.b[target_term.buf].panel_type = 'terminal'
    end
  end

  ensure_right_sidebar_precedence()
  equalize_splits()

  if target_term and target_term.win and vim.api.nvim_win_is_valid(target_term.win) then
    vim.api.nvim_set_current_win(target_term.win)
  end
  vim.cmd('startinsert')
  vim.schedule(function()
    if target_term and target_term.win and vim.api.nvim_win_is_valid(target_term.win) then
      vim.api.nvim_set_current_win(target_term.win)
      vim.cmd('startinsert')
    end
  end)

  pcall(function()
    require('utils.terminal-tracker').invalidate()
    require('lualine').refresh()
  end)
end

function BottomPanel.split_terminal(count)
  local cur_win = vim.api.nvim_get_current_win()
  local info = get_win_info(cur_win)

  if not info.is_terminal then
    local bot_win = find_win_type('is_terminal')
    if bot_win and vim.api.nvim_win_is_valid(bot_win) then
      vim.api.nvim_set_current_win(bot_win)
    else
      BottomPanel.open_terminal(count)
      return
    end
  end

  local max_id = 1
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(w) then
      local b = vim.api.nvim_win_get_buf(w)
      local st = vim.b[b].snacks_terminal
      if st and st.id then
        max_id = math.max(max_id, st.id)
      end
    end
  end
  local target_count = (count and count > 0 and count) or (max_id + 1)

  Snacks.terminal.open(nil, {
    count = target_count,
    win = {
      position = 'bottom',
      relative = 'editor',
      height = 0.38,
      wo = {
        winbar = '',
        winfixheight = true,
        winfixbuf = true,
      },
      on_buf = function(term)
        vim.b[term.buf].panel_zone = 'bottom'
        vim.b[term.buf].panel_type = 'terminal'
      end,
    },
  })

  RightPanel.has_custom_bottom_widths = false
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(w) and get_win_info(w).is_terminal then
      vim.w[w].custom_split_ratio = nil
    end
  end

  BottomPanel.active_terminal_count = target_count
  BottomPanel.active_mode = 'terminal'

  vim.cmd('startinsert')
  vim.schedule(function()
    ensure_right_sidebar_precedence()
    equalize_splits()
    pcall(function()
      require('utils.terminal-tracker').invalidate()
      require('lualine').refresh()
    end)
  end)
end

function BottomPanel.open_dbout()
  local info = get_win_info()
  if info.is_terminal and (vim.bo[info.buf].filetype == 'dbout' or vim.bo[info.buf].filetype == 'sqmeow-result') then
    close_dbout_win()
    local ed = get_editor_win()
    if ed and vim.api.nvim_win_is_valid(ed) then
      vim.api.nvim_set_current_win(ed)
    end
    return
  end

  local ok_v, view_api = pcall(require, 'sqmeow.api.view')
  if not ok_v then
    pcall(function() require('lazy').load({ plugins = { 'sqmeow.nvim' } }) end)
    ok_v, view_api = pcall(require, 'sqmeow.api.view')
  end
  if not ok_v then
    ok_v, view_api = pcall(require, 'sqmeow.api')
  end
  if ok_v and view_api and view_api.open then
    hide_terminal_if_visible()
    BottomPanel.active_mode = 'dbout'
    view_api.open()

    local res_win = nil
    local ok_res, res_mod = pcall(require, 'sqmeow.ui.result')
    if ok_res and res_mod.window then
      res_win = res_mod.window()
    end
    if not (res_win and vim.api.nvim_win_is_valid(res_win)) then
      for _, w in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_is_valid(w) and vim.bo[vim.api.nvim_win_get_buf(w)].filetype == 'sqmeow-result' then
          res_win = w
          break
        end
      end
    end
    if res_win and vim.api.nvim_win_is_valid(res_win) then
      vim.api.nvim_set_current_win(res_win)
      vim.wo[res_win].spell = false
      vim.wo[res_win].winfixheight = true
      vim.wo[res_win].winfixbuf = true
    end

    vim.schedule(ensure_right_sidebar_precedence)
    return
  end

  local dbout_buf = BottomPanel.last_dbout_buf
  if not (dbout_buf and vim.api.nvim_buf_is_valid(dbout_buf)) then
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_valid(buf) and (vim.bo[buf].filetype == 'dbout' or vim.bo[buf].filetype == 'sqmeow-result') then
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

  local r_win = get_right_sidebar_win()
  local results_height = math.floor(vim.o.lines * 0.35)
  local win
  if r_win and ed and vim.api.nvim_win_is_valid(ed) then
    vim.api.nvim_win_call(ed, function()
      vim.cmd('belowright ' .. results_height .. 'split')
      win = vim.api.nvim_get_current_win()
    end)
  else
    vim.cmd('botright ' .. results_height .. 'split')
    win = vim.api.nvim_get_current_win()
  end
  vim.api.nvim_win_set_buf(win, dbout_buf)
  vim.wo[win].winfixheight = true
  vim.wo[win].winfixbuf = true
  ensure_right_sidebar_precedence()
  equalize_splits()
end

function BottomPanel.toggle_active(count)
  local explicit_count = (count and count > 0 and count) or (vim.v.count > 0 and vim.v.count) or nil
  if explicit_count then
    BottomPanel.active_terminal_count = explicit_count
  end
  local target_count = BottomPanel.active_terminal_count or 1

  local info = get_win_info()

  -- 1. If currently inside dbout / sqmeow-result, close it
  if info.is_terminal and (vim.bo[info.buf].filetype == 'dbout' or vim.bo[info.buf].filetype == 'sqmeow-result') then
    close_dbout_win()
    local ed = get_editor_win()
    if ed and vim.api.nvim_win_is_valid(ed) then
      vim.api.nvim_set_current_win(ed)
    end
    return
  end

  -- 2. If currently inside a terminal:
  if info.is_terminal and vim.bo[info.buf].filetype ~= 'dbout' and vim.bo[info.buf].filetype ~= 'sqmeow-result' then
    local current_term_id = (vim.b[info.buf].snacks_terminal and vim.b[info.buf].snacks_terminal.id) or target_count
    if not explicit_count or explicit_count == current_term_id then
      hide_terminal_if_visible()
      local ed = get_editor_win()
      if ed and vim.api.nvim_win_is_valid(ed) then
        vim.api.nvim_set_current_win(ed)
      end
      return
    else
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

BottomPanel.hide_terminal = hide_terminal_if_visible
BottomPanel.close_dbout = close_dbout_win
BottomPanel.ensure_precedence = ensure_right_sidebar_precedence
BottomPanel.equalize_splits = equalize_splits
BottomPanel.reset_layout = reset_window_layout

-------------------------------------------------------------------------------
-- Spatial Navigation Functions
-------------------------------------------------------------------------------

local function smart_navigate_right()
  prepare_nav()
  local cur_win = vim.api.nvim_get_current_win()
  local info = get_win_info(cur_win)

  -- 1. If currently inside any right panel: close it and return to editor
  if info.is_explorer or info.is_dbui or info.is_opencode then
    RightPanel.close_all()
    local ed = get_editor_win()
    if ed and vim.api.nvim_win_is_valid(ed) then
      vim.api.nvim_set_current_win(ed)
    end
    return
  end

  -- 2. Check if there is a window to the right
  local target_winnr = vim.fn.winnr('l')
  local cur_winnr = vim.fn.winnr()

  if target_winnr ~= cur_winnr then
    local target_win = vim.fn.win_getid(target_winnr)
    local target_info = get_win_info(target_win)

    if info.is_editor and target_info.is_editor then
      vim.api.nvim_set_current_win(target_win)
      return
    end

    if info.is_terminal and target_info.is_terminal then
      vim.api.nvim_set_current_win(target_win)
      return
    end

    if target_info.is_explorer or target_info.is_dbui or target_info.is_opencode then
      vim.api.nvim_set_current_win(target_win)
      return
    end
  end

  -- 3. We are at the rightmost boundary: toggle/focus the active right panel
  RightPanel.toggle_active()
end

local function smart_navigate_left()
  prepare_nav()
  local cur_win = vim.api.nvim_get_current_win()
  local info = get_win_info(cur_win)

  -- 1. If inside any right-side panel, jump directly back into the Code Editor
  if info.is_explorer or info.is_dbui or info.is_opencode then
    local ed = get_editor_win()
    if ed and vim.api.nvim_win_is_valid(ed) then
      vim.api.nvim_set_current_win(ed)
    end
    return
  end

  -- 2. Check if there is a window to the left
  local target_winnr = vim.fn.winnr('h')
  local cur_winnr = vim.fn.winnr()

  if target_winnr ~= cur_winnr then
    local target_win = vim.fn.win_getid(target_winnr)
    local target_info = get_win_info(target_win)

    if info.is_editor and target_info.is_editor then
      vim.api.nvim_set_current_win(target_win)
      return
    end

    if info.is_terminal and target_info.is_terminal then
      vim.api.nvim_set_current_win(target_win)
      return
    end
  end

  -- 3. If in bottom terminal and at leftmost boundary: cycle to next terminal instance!
  if info.is_terminal then
    local tracker_ok, tracker = pcall(require, 'utils.terminal-tracker')
    if tracker_ok and tracker.get_terminals then
      local terms = tracker.get_terminals()
      if #terms > 1 then
        local cur_id = (vim.b[info.buf].snacks_terminal and vim.b[info.buf].snacks_terminal.id) or BottomPanel.active_terminal_count or 1
        local next_id = terms[1].id
        for i, t in ipairs(terms) do
          if t.id == cur_id then
            local next_idx = (i % #terms) + 1
            next_id = terms[next_idx].id
            break
          end
        end
        BottomPanel.open_terminal(next_id)
        return
      end
    end
    return
  end

  try_wincmd('h')
end

local function smart_navigate_up()
  prepare_nav()
  local cur_win = vim.api.nvim_get_current_win()
  local info = get_win_info(cur_win)

  if info.is_terminal then
    local ed = get_editor_win()
    if ed and vim.api.nvim_win_is_valid(ed) then
      vim.api.nvim_set_current_win(ed)
    end
    return
  end

  try_wincmd('k')
end

local function smart_navigate_down()
  prepare_nav()
  local cur_win = vim.api.nvim_get_current_win()
  local info = get_win_info(cur_win)
  local count = vim.v.count > 0 and vim.v.count or nil

  if info.is_terminal then
    BottomPanel.toggle_active(count)
    return
  end

  local bot_win = find_win_type('is_terminal')
  if bot_win and vim.api.nvim_win_is_valid(bot_win) then
    if count then
      BottomPanel.open_terminal(count)
    else
      vim.api.nvim_set_current_win(bot_win)
    end
    return
  end

  BottomPanel.toggle_active(count)
end

-------------------------------------------------------------------------------
-- Window Resizing (<M-h/j/k/l> & <C-w>=)
-------------------------------------------------------------------------------

local function smart_resize_width(delta)
  local cur_win = vim.api.nvim_get_current_win()
  if not vim.api.nvim_win_is_valid(cur_win) then return end

  local info = get_win_info(cur_win)

  if info.is_explorer or info.is_dbui or info.is_opencode then
    delta = -delta
  end

  local cur_w = vim.api.nvim_win_get_width(cur_win)
  local new_w = math.max(12, cur_w + delta)
  pcall(vim.api.nvim_win_set_width, cur_win, new_w)

  RightPanel.custom_widths = RightPanel.custom_widths or {}
  if info.is_opencode then
    RightPanel.custom_widths['opencode'] = new_w
  elseif info.is_dbui then
    RightPanel.custom_widths['dbui'] = new_w
  elseif info.is_explorer then
    RightPanel.custom_widths['explorer'] = new_w
  elseif info.is_editor then
    RightPanel.has_custom_editor_widths = true
    vim.schedule(function()
      local ed_wins = {}
      local total_w = 0
      for _, w in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_is_valid(w) and get_win_info(w).is_editor then
          table.insert(ed_wins, w)
          total_w = total_w + vim.api.nvim_win_get_width(w)
        end
      end
      if total_w > 0 then
        for _, w in ipairs(ed_wins) do
          vim.w[w].custom_split_ratio = vim.api.nvim_win_get_width(w) / total_w
        end
      end
    end)
  elseif info.is_terminal then
    RightPanel.has_custom_bottom_widths = true
    vim.schedule(function()
      local bot_wins = {}
      local total_w = 0
      for _, w in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_is_valid(w) and get_win_info(w).is_terminal then
          table.insert(bot_wins, w)
          total_w = total_w + vim.api.nvim_win_get_width(w)
        end
      end
      if total_w > 0 then
        for _, w in ipairs(bot_wins) do
          vim.w[w].custom_split_ratio = vim.api.nvim_win_get_width(w) / total_w
        end
      end
    end)
  end
end

local function smart_resize_height(delta)
  local cur_win = vim.api.nvim_get_current_win()
  if not vim.api.nvim_win_is_valid(cur_win) then return end

  local cur_h = vim.api.nvim_win_get_height(cur_win)
  local new_h = math.max(4, cur_h + delta)
  pcall(vim.api.nvim_win_set_height, cur_win, new_h)
end

-------------------------------------------------------------------------------
-- Window Split Actions
-------------------------------------------------------------------------------

local function editor_split(direction)
  local cur_win = vim.api.nvim_get_current_win()
  local info = get_win_info(cur_win)
  if info.is_terminal and direction == 'vertical' then
    BottomPanel.split_terminal()
    return
  end

  local ed = get_editor_win()
  if ed and vim.api.nvim_win_is_valid(ed) then
    vim.api.nvim_set_current_win(ed)
  end
  if direction == 'horizontal' then
    vim.cmd('split')
  else
    RightPanel.has_custom_editor_widths = false
    for _, w in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_is_valid(w) and get_win_info(w).is_editor then
        vim.w[w].custom_split_ratio = nil
      end
    end
    vim.cmd('vsplit')
  end
  ensure_right_sidebar_precedence()
end

local function smart_close_window(fallback_close_fn)
  local cur_win = vim.api.nvim_get_current_win()
  if not vim.api.nvim_win_is_valid(cur_win) then return end
  local info = get_win_info(cur_win)

  if info.is_explorer or info.is_dbui or info.is_opencode then
    RightPanel.close_all()
    local ed = get_editor_win()
    if ed and vim.api.nvim_win_is_valid(ed) then
      vim.api.nvim_set_current_win(ed)
    end
    return
  end

  if info.is_terminal then
    local bot_wins = {}
    for _, w in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_is_valid(w) and get_win_info(w).is_terminal then
        table.insert(bot_wins, w)
      end
    end
    if #bot_wins > 1 then
      pcall(vim.api.nvim_win_close, cur_win, true)
    else
      BottomPanel.close_all()
    end
    local ed = get_editor_win()
    if ed and vim.api.nvim_win_is_valid(ed) then
      vim.api.nvim_set_current_win(ed)
    end
    return
  end

  local editor_count = 0
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(w) and get_win_info(w).is_editor then
      editor_count = editor_count + 1
    end
  end

  if editor_count > 1 then
    pcall(vim.api.nvim_win_close, cur_win, false)
    ensure_right_sidebar_precedence()
  elseif fallback_close_fn then
    fallback_close_fn()
  end
end

-------------------------------------------------------------------------------
-- Session Stability Helpers
-------------------------------------------------------------------------------

local function is_database_or_transient_buf(buf)
  if not vim.api.nvim_buf_is_valid(buf) then return false end
  local ft = vim.bo[buf].filetype
  if ft == 'sqmeow-drawer' or ft == 'sqmeow-result' or ft == 'sqmeow-output' or ft == 'dbui' or ft == 'dbout' or ft == 'snacks_dashboard' or ft == 'snacks_terminal' then return true end
  local bname = vim.api.nvim_buf_get_name(buf)
  if (bname:match('^%[Preview:') or vim.b[buf].is_preview_buffer) and vim.bo[buf].buftype == 'nofile' then return true end
  if bname:find('/db_ui/') ~= nil then return true end
  if bname:match('%.sqlite%d?$') or bname:match('%.db$') then return true end
  return false
end

local function cleanup_panels_before_save()
  RightPanel.close_all()
  BottomPanel.close_all()

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

-------------------------------------------------------------------------------
-- Autocommand Setup
-------------------------------------------------------------------------------

local function setup_autocmds()
  local layout_lock_group = vim.api.nvim_create_augroup('UserLayoutLock', { clear = true })

  vim.api.nvim_create_autocmd({ 'FileType', 'BufWinEnter' }, {
    group = layout_lock_group,
    pattern = '*',
    callback = function(args)
      local buf = args.buf
      if not vim.api.nvim_buf_is_valid(buf) then return end

      local ft = vim.bo[buf].filetype
      if ft == 'snacks_picker_preview' or ft == 'snacks_picker_input' then
        vim.bo[buf].buflisted = false
        return
      end

      local win = vim.fn.bufwinid(buf)
      if not (win and win ~= -1 and vim.api.nvim_win_is_valid(win)) then return end

      local cfg = vim.api.nvim_win_get_config(win)
      if cfg.relative and cfg.relative ~= '' then return end

      local info = get_win_info(win)

      if info.is_explorer or info.is_dbui or info.is_opencode then
        vim.bo[buf].buflisted = false
        if vim.api.nvim_win_is_valid(win) then
          vim.wo[win].winfixbuf = true
          vim.wo[win].winfixwidth = true
        end
      elseif info.is_terminal then
        vim.bo[buf].buflisted = false
        if vim.api.nvim_win_is_valid(win) then
          vim.wo[win].winfixbuf = true
          vim.wo[win].winfixheight = true
        end
      end
    end,
  })

  vim.api.nvim_create_autocmd('WinClosed', {
    group = layout_lock_group,
    callback = function()
      if vim.v.exiting ~= vim.NIL and vim.v.exiting ~= nil then return end
      vim.schedule(function()
        if vim.v.exiting ~= vim.NIL and vim.v.exiting ~= nil then return end

        local editor_win = get_editor_win()
        if not editor_win then
          local non_editor_exists = false
          for _, w in ipairs(vim.api.nvim_list_wins()) do
            if vim.api.nvim_win_is_valid(w) then
              local cfg = vim.api.nvim_win_get_config(w)
              if not cfg.relative or cfg.relative == '' then
                local info = get_win_info(w)
                if info.is_explorer or info.is_dbui or info.is_opencode or info.is_terminal then
                  non_editor_exists = true
                  break
                end
              end
            end
          end

          if non_editor_exists then
            vim.cmd('topleft split')
            vim.cmd('enew')
            ensure_right_sidebar_precedence()
          end
        else
          ensure_right_sidebar_precedence()
        end
      end)
    end,
    desc = 'Prevent sidebars from overtaking screen when editor windows close and auto-equalize splits',
  })

  vim.api.nvim_create_autocmd('VimResized', {
    group = layout_lock_group,
    callback = function()
      vim.schedule(ensure_right_sidebar_precedence)
    end,
    desc = 'Auto-equalize splits and enforce sidebar geometry on terminal resize',
  })

  local session_stability_group = vim.api.nvim_create_augroup('UserSessionStability', { clear = true })

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
      if #real_bufs == 0 then
        pcall(function() require('persistence').stop() end)
      end
    end,
  })

  vim.api.nvim_create_autocmd('User', {
    pattern = 'PersistenceLoadPost',
    group = session_stability_group,
    callback = function()
      vim.schedule(function()
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
    end,
  })

  -- Track query results buffer automatically
  vim.api.nvim_create_autocmd({ 'FileType', 'BufWinEnter' }, {
    pattern = { 'dbout', 'sqmeow-result' },
    callback = function(args)
      local ft = vim.bo[args.buf].filetype
      local name = vim.api.nvim_buf_get_name(args.buf)
      if ft == 'sqmeow-drawer' or name:find('drawer') then return end
      vim.b[args.buf].panel_zone = 'bottom'
      vim.b[args.buf].panel_type = 'dbout'
      BottomPanel.last_dbout_buf = args.buf
      BottomPanel.active_mode = 'dbout'
      hide_terminal_if_visible()
      ensure_right_sidebar_precedence()
    end,
  })

  -- Track active terminal instance automatically when entering a terminal buffer
  vim.api.nvim_create_autocmd({ 'BufEnter', 'TermOpen' }, {
    callback = function(args)
      local st = vim.b[args.buf].snacks_terminal
      local is_opencode = tostring(st and st.cmd or ''):find('opencode') or vim.b[args.buf].panel_type == 'opencode'
      if is_opencode then
        vim.b[args.buf].panel_zone = 'right'
        vim.b[args.buf].panel_type = 'opencode'
      elseif st and st.id then
        vim.b[args.buf].panel_zone = 'bottom'
        vim.b[args.buf].panel_type = 'terminal'
        BottomPanel.active_terminal_count = st.id
        BottomPanel.active_mode = 'terminal'
      end
    end,
  })
end

-------------------------------------------------------------------------------
-- Module Exports & Global Bridges
-------------------------------------------------------------------------------

Layout.RightPanel = RightPanel
Layout.BottomPanel = BottomPanel
Layout.get_win_info = get_win_info
Layout.find_win_type = find_win_type
Layout.get_editor_win = get_editor_win
Layout.get_right_sidebar_win = get_right_sidebar_win
Layout.equalize_splits = equalize_splits
Layout.ensure_right_sidebar_precedence = ensure_right_sidebar_precedence
Layout.reset_window_layout = reset_window_layout
Layout.editor_split = editor_split
Layout.smart_close_window = smart_close_window
Layout.navigate_right = smart_navigate_right
Layout.navigate_left = smart_navigate_left
Layout.navigate_up = smart_navigate_up
Layout.navigate_down = smart_navigate_down
Layout.resize_width = smart_resize_width
Layout.resize_height = smart_resize_height
Layout.cleanup_panels_before_save = cleanup_panels_before_save
Layout.is_database_or_transient_buf = is_database_or_transient_buf
Layout.get_real_editor_bufs = get_real_editor_bufs
Layout.setup = setup_autocmds

-- Global backward-compatibility bridges
_G.RightPanel = RightPanel
_G.BottomPanel = BottomPanel
_G.ensure_right_sidebar_precedence = ensure_right_sidebar_precedence
_G.equalize_splits = equalize_splits
_G.reset_window_layout = reset_window_layout
_G.smart_resize_width = smart_resize_width
_G.smart_resize_height = smart_resize_height

-- Initialize autocommands immediately upon load
setup_autocmds()

return Layout
