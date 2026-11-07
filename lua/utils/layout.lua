-- lua/utils/layout.lua
-- Unified 3-Zone IDE Layout Engine (Editor | Right Sidebar | Bottom Panel)

local Layout = {}

-------------------------------------------------------------------------------
-- Panel State Tables
-------------------------------------------------------------------------------

local RightPanel = {
  custom_widths = {},
  active_mode = 'explorer', -- 'explorer' | 'dbui' | 'opencode' | 'neogit' | 'dockyard' | 'grugfar'
  has_custom_editor_widths = false,
  has_custom_bottom_widths = false,
}

local BottomPanel = {
  active_mode = 'terminal', -- 'terminal' | 'dbout' | 'qf'
  active_terminal_count = 1,
  last_dbout_buf = nil,
  dbout_open = false,
  last_qf_buf = nil,
  qf_open = false,
}

local last_editor_win = nil

-------------------------------------------------------------------------------
-- Window Classification & Detection Helpers
-------------------------------------------------------------------------------

local function get_win_info(win)
  win = win or vim.api.nvim_get_current_win()
  if not vim.api.nvim_win_is_valid(win) then
    return {}
  end

  local buf = vim.api.nvim_win_get_buf(win)
  local ft = vim.bo[buf].filetype
  local bname = vim.api.nvim_buf_get_name(buf):lower()

  -- Check explicit buffer tag first
  local zone = vim.b[buf].panel_zone
  local ptype = vim.b[buf].panel_type

  local cfg = vim.api.nvim_win_get_config(win)
  local is_float = (cfg.relative ~= nil and cfg.relative ~= '')

  local bt = vim.bo[buf].buftype
  local is_explorer = (ptype == 'explorer') or (ft:match '^snacks_picker' ~= nil or ft:match '^snacks_layout' ~= nil)
  local is_dbui = (ptype == 'dbui') or (ft == 'dbui' or ft == 'sqmeow-drawer' or bname:find 'sqmeow://drawer' ~= nil)
  local is_opencode = (ptype == 'opencode')
    or (
      bt ~= ''
      and (
        (ft:match 'opencode' ~= nil and ft ~= 'opencode_ask')
        or (bt == 'terminal' and bname:find ':%S*opencode' ~= nil)
        or (vim.b[buf].snacks_terminal and vim.b[buf].snacks_terminal.cmd and tostring(vim.b[buf].snacks_terminal.cmd):find 'opencode' ~= nil)
      )
    )
  local is_neogit = not is_float
    and ((ptype == 'neogit') or (ft:match '^Neogit' ~= nil) or (ft == 'gitcommit' and (bname:find 'commit_editmsg' ~= nil or bname:find 'merge_msg' ~= nil)))
  local is_dockyard = not is_float
    and ((ptype == 'dockyard') or (ft == 'dockyard' or ft == 'dockyard-logs' or ft == 'dockyard-files' or ft == 'dockyard_popup'))
  local is_grugfar = not is_float and ((ptype == 'grugfar') or (ft == 'grug-far'))

  -- Right panel zone takes absolute precedence over bottom terminal
  if is_explorer or is_dbui or is_opencode or is_neogit or is_dockyard or is_grugfar or zone == 'right' then
    return {
      win = win,
      buf = buf,
      ft = ft,
      zone = 'right',
      is_explorer = is_explorer,
      is_dbui = is_dbui,
      is_opencode = is_opencode,
      is_neogit = is_neogit,
      is_dockyard = is_dockyard,
      is_grugfar = is_grugfar,
      is_terminal = false,
      is_editor = false,
    }
  end

  local is_dbout = (ptype == 'dbout') or (ft == 'dbout' or ft == 'sqmeow-result' or bname:find 'sqmeow://result' ~= nil)
  local is_qf = (ptype == 'qf') or (ft == 'qf' or vim.bo[buf].buftype == 'quickfix')
  local is_term = (ptype == 'terminal') or (ft == 'snacks_terminal' or ft == 'terminal' or vim.bo[buf].buftype == 'terminal' or bname:find 'term://' ~= nil)
  local is_terminal = (zone == 'bottom') or is_dbout or is_qf or is_term

  local is_editor = not is_terminal and ft ~= 'snacks_dashboard'

  return {
    win = win,
    buf = buf,
    ft = ft,
    zone = is_terminal and 'bottom' or (is_editor and 'editor' or 'unknown'),
    is_explorer = false,
    is_dbui = false,
    is_opencode = false,
    is_neogit = false,
    is_dockyard = false,
    is_grugfar = false,
    is_terminal = is_terminal,
    is_editor = is_editor,
  }
end

local function is_right_panel(info)
  return info ~= nil and (info.is_explorer or info.is_dbui or info.is_opencode or info.is_neogit or info.is_dockyard or info.is_grugfar)
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
  local fallback = nil
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(win) then
      local cfg = vim.api.nvim_win_get_config(win)
      if not cfg.relative or cfg.relative == '' then
        local info = get_win_info(win)
        if is_right_panel(info) then
          if info.ft == 'NeogitStatus' or info.ft == 'dockyard' or info.ft == 'grug-far' then
            return win
          end
          fallback = fallback or win
        end
      end
    end
  end
  return fallback
end

local function get_editor_win()
  local cur = vim.api.nvim_get_current_win()
  local cfg = vim.api.nvim_win_get_config(cur)
  if (not cfg.relative or cfg.relative == '') and get_win_info(cur).is_editor then
    last_editor_win = cur
    return cur
  end

  if last_editor_win and vim.api.nvim_win_is_valid(last_editor_win) and vim.api.nvim_win_get_tabpage(last_editor_win) == vim.api.nvim_get_current_tabpage() then
    local lcfg = vim.api.nvim_win_get_config(last_editor_win)
    if (not lcfg.relative or lcfg.relative == '') and get_win_info(last_editor_win).is_editor then
      return last_editor_win
    end
  end

  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_is_valid(win) then
      local wcfg = vim.api.nvim_win_get_config(win)
      if not wcfg.relative or wcfg.relative == '' then
        local info = get_win_info(win)
        if info.is_editor then
          last_editor_win = win
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
        if is_right_panel(info) then
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
    if #wins <= 1 then
      return
    end

    -- Group windows by unique horizontal column position
    local col_map = {}
    local cols = {}
    for _, w in ipairs(wins) do
      local c = vim.api.nvim_win_get_position(w)[2]
      if not col_map[c] then
        col_map[c] = w
        table.insert(cols, c)
      end
    end

    if #cols <= 1 then
      return
    end
    table.sort(cols)

    local n = #cols
    local seps = n - 1
    local net_w = avail_w - seps
    if net_w <= 0 then
      return
    end

    if not has_custom_flag then
      local target = math.floor(net_w / n)
      for i = 1, n - 1 do
        local w = col_map[cols[i]]
        pcall(vim.api.nvim_win_set_width, w, target)
      end
    else
      for i = 1, n - 1 do
        local w = col_map[cols[i]]
        local r = vim.w[w].custom_split_ratio or (1 / n)
        local target = math.max(12, math.floor(net_w * r))
        pcall(vim.api.nvim_win_set_width, w, target)
      end
    end
  end

  balance_group(editor_wins, RightPanel.has_custom_editor_widths)
  balance_group(bottom_wins, RightPanel.has_custom_bottom_widths)
end

local function ensure_right_sidebar_precedence()
  local right_wins = {}
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(w) then
      local cfg = vim.api.nvim_win_get_config(w)
      if not cfg.relative or cfg.relative == '' then
        local wi = get_win_info(w)
        if is_right_panel(wi) then
          table.insert(right_wins, w)
        end
      end
    end
  end

  local r_win = get_right_sidebar_win()
  if r_win and vim.api.nvim_win_is_valid(r_win) then
    vim.api.nvim_win_call(r_win, function()
      -- Only force `wincmd L` when there is a single right-panel window;
      -- if Neogit or Dockyard has a stacked sub-view/popup split inside the Right Panel, preserve the vertical stack!
      if #right_wins <= 1 then
        vim.cmd 'wincmd L'
      end
      local info = get_win_info(r_win)
      local custom = RightPanel.custom_widths or {}
      local width
      if info.is_neogit then
        width = custom['neogit'] or math.max(60, math.floor(vim.o.columns * 0.48))
      elseif info.is_dockyard then
        width = custom['dockyard'] or math.max(60, math.floor(vim.o.columns * 0.48))
      elseif info.is_grugfar then
        width = custom['grugfar'] or math.max(56, math.floor(vim.o.columns * 0.45))
      elseif info.is_opencode then
        width = custom['opencode'] or math.max(45, math.floor(vim.o.columns * 0.38))
      elseif info.is_dbui then
        width = custom['dbui'] or 35
      else
        width = custom['explorer'] or 35
      end
      vim.cmd('vertical resize ' .. width)
    end)

    for _, w in ipairs(right_wins) do
      if vim.api.nvim_win_is_valid(w) then
        local wi = get_win_info(w)
        if wi.is_neogit or wi.is_grugfar or (wi.is_dockyard and (wi.ft == 'dockyard_popup' or wi.ft == 'dockyard-logs')) then
          vim.wo[w].wrap = true
          vim.wo[w].linebreak = true
          vim.wo[w].breakindent = true
        end
      end
    end
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

  ensure_right_sidebar_precedence()

  local bot_win = find_win_type 'is_terminal'
  if bot_win and vim.api.nvim_win_is_valid(bot_win) then
    pcall(vim.api.nvim_win_set_height, bot_win, default_bot_height)
  end

  equalize_splits()
  vim.notify('Window layout reset & balanced', vim.log.levels.INFO, { title = 'Layout' })
end

local function prepare_nav()
  local m = vim.api.nvim_get_mode().mode
  if m:match '^[it]' then
    vim.cmd 'stopinsert'
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
  local binary = vim.fn.exepath 'opencode'
  if binary == '' then
    local fallback = vim.fn.expand '~/.opencode/bin/opencode'
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
  local ok, pickers = pcall(function()
    return Snacks.picker.get { source = 'explorer' }
  end)
  if ok and pickers and #pickers > 0 then
    for _, p in ipairs(pickers) do
      pcall(function()
        p:close()
      end)
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
    pcall(function()
      opencode_term:hide()
    end)
    closed = true
  end

  -- Close visible Neogit status buffer and any Neogit sub-buffers cleanly
  if package.loaded['neogit.buffers.status'] then
    pcall(function()
      local status = require 'neogit.buffers.status'
      local inst = status.instance and status.instance()
      if inst and inst.buffer and inst.buffer:is_visible() then
        inst:close()
        closed = true
      end
    end)
  end

  -- Close visible Dockyard LogLens & main UI cleanly
  if package.loaded['dockyard.ui.loglens'] then
    pcall(function()
      require('dockyard.ui.loglens').close()
    end)
  end
  if package.loaded['dockyard.ui'] then
    pcall(function()
      local dy_ui = require 'dockyard.ui'
      if dy_ui.is_open and dy_ui.is_open() then
        dy_ui.close()
        closed = true
      end
    end)
  end

  -- Fallback: check all open windows for any lingering right-side panels or auxiliary floats
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(win) then
      local buf = vim.api.nvim_win_get_buf(win)
      local ft = vim.bo[buf].filetype
      local bname = vim.api.nvim_buf_get_name(win and buf or 0):lower()
      local info = get_win_info(win)
      if is_right_panel(info) or ft == 'grug-far-help' or ft == 'grug-far-history' then
        pcall(vim.api.nvim_win_close, win, true)
        closed = true
      end
      if ft == 'gitcommit' and (bname:find 'commit_editmsg' ~= nil or bname:find 'merge_msg' ~= nil) then
        pcall(vim.api.nvim_buf_delete, buf, { force = true })
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

function RightPanel.open_explorer(no_toggle)
  local info = get_win_info()
  if info.is_explorer then
    if no_toggle then
      return
    end
    RightPanel.close_all()
    local ed = get_editor_win()
    if ed then
      vim.api.nvim_set_current_win(ed)
    end
    return
  end

  local existing_exp = find_win_type 'is_explorer'
  if existing_exp and vim.api.nvim_win_is_valid(existing_exp) then
    RightPanel.active_mode = 'explorer'
    vim.api.nvim_set_current_win(existing_exp)
    pcall(function()
      require('lualine').refresh()
    end)
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

  Snacks.explorer {
    layout = { layout = { position = 'right', width = width_opt } },
    jump = { close = false },
  }
  vim.schedule(function()
    ensure_right_sidebar_precedence()
    pcall(function()
      require('lualine').refresh()
    end)
  end)
end

function RightPanel.open_dbui(no_toggle)
  local info = get_win_info()
  if info.is_dbui then
    if no_toggle then
      return
    end
    RightPanel.close_all()
    local ed = get_editor_win()
    if ed then
      vim.api.nvim_set_current_win(ed)
    end
    return
  end

  local existing_dbui = find_win_type 'is_dbui'
  if existing_dbui and vim.api.nvim_win_is_valid(existing_dbui) then
    RightPanel.active_mode = 'dbui'
    vim.api.nvim_set_current_win(existing_dbui)
    pcall(function()
      require('lualine').refresh()
    end)
    return
  end

  RightPanel.close_all()
  RightPanel.active_mode = 'dbui'

  if _G.DatabaseUtils and _G.DatabaseUtils.open_drawer then
    _G.DatabaseUtils.open_drawer()
  elseif vim.fn.exists ':Sqmeow' == 2 then
    vim.cmd 'Sqmeow drawer'
  elseif vim.fn.exists ':DBUI' == 2 then
    vim.cmd 'DBUI'
  end
  vim.schedule(function()
    ensure_right_sidebar_precedence()
    pcall(function()
      require('lualine').refresh()
    end)
  end)
end

function RightPanel.open_opencode(no_toggle, opts)
  local focus = not (opts and opts.focus == false)
  local info = get_win_info()
  if info.is_opencode then
    if no_toggle then
      if focus then
        vim.cmd 'startinsert'
      end
      return
    end
    RightPanel.close_all()
    local ed = get_editor_win()
    if ed then
      vim.api.nvim_set_current_win(ed)
    end
    return
  end

  local existing_oc = find_win_type 'is_opencode'
  if existing_oc and vim.api.nvim_win_is_valid(existing_oc) then
    RightPanel.active_mode = 'opencode'
    if focus then
      vim.api.nvim_set_current_win(existing_oc)
      vim.cmd 'startinsert'
    end
    pcall(function()
      require('lualine').refresh()
    end)
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

  local term = Snacks.terminal.get(cmd, {
    create = true,
    start_insert = false,
    auto_insert = true,
    win = {
      position = 'right',
      width = width_opt,
      relative = 'editor',
      enter = false,
      wo = { winbar = '', winfixwidth = true, winfixbuf = true },
      on_buf = function(t)
        vim.b[t.buf].panel_zone = 'right'
        vim.b[t.buf].panel_type = 'opencode'
        vim.keymap.set('t', '<leader>t', '<Space>t', { buffer = t.buf, noremap = true, silent = true })
      end,
    },
  })
  if term then
    term:show()
    if term.buf and vim.api.nvim_buf_is_valid(term.buf) then
      vim.b[term.buf].panel_zone = 'right'
      vim.b[term.buf].panel_type = 'opencode'
    end
    if focus and term.win and vim.api.nvim_win_is_valid(term.win) then
      vim.api.nvim_set_current_win(term.win)
      vim.cmd 'startinsert'
    elseif ed and vim.api.nvim_win_is_valid(ed) then
      vim.api.nvim_set_current_win(ed)
    end
  end
  vim.schedule(function()
    ensure_right_sidebar_precedence()
    local cur_win = vim.api.nvim_get_current_win()
    local cur_cfg = vim.api.nvim_win_is_valid(cur_win) and vim.api.nvim_win_get_config(cur_win) or {}
    local in_float = cur_cfg.relative and cur_cfg.relative ~= ''
    if not focus and not in_float and ed and vim.api.nvim_win_is_valid(ed) and cur_win ~= ed then
      pcall(vim.api.nvim_set_current_win, ed)
    end
    pcall(function()
      require('lualine').refresh()
    end)
  end)
end

function RightPanel.open_neogit(no_toggle)
  local info = get_win_info()
  if info.is_neogit then
    if no_toggle then
      return
    end
    RightPanel.close_all()
    local ed = get_editor_win()
    if ed and vim.api.nvim_win_is_valid(ed) then
      vim.api.nvim_set_current_win(ed)
    end
    return
  end

  local existing_ng = find_win_type 'is_neogit'
  if existing_ng and vim.api.nvim_win_is_valid(existing_ng) then
    RightPanel.active_mode = 'neogit'
    vim.api.nvim_set_current_win(existing_ng)
    ensure_right_sidebar_precedence()
    pcall(function()
      require('lualine').refresh()
    end)
    return
  end

  RightPanel.close_all()
  RightPanel.active_mode = 'neogit'

  local ed = get_editor_win()
  if ed and vim.api.nvim_win_is_valid(ed) then
    vim.api.nvim_set_current_win(ed)
  end

  local ok, neogit = pcall(require, 'neogit')
  if ok and neogit and neogit.open then
    neogit.open { kind = 'vsplit' }
  else
    vim.cmd 'Neogit kind=vsplit'
  end

  local function style_neogit_win()
    local ng_win = find_win_type 'is_neogit'
    if ng_win and vim.api.nvim_win_is_valid(ng_win) then
      local ng_buf = vim.api.nvim_win_get_buf(ng_win)
      vim.b[ng_buf].panel_zone = 'right'
      vim.b[ng_buf].panel_type = 'neogit'
      vim.bo[ng_buf].buflisted = false
      vim.wo[ng_win].spell = false
      vim.wo[ng_win].wrap = true
      vim.wo[ng_win].linebreak = true
      vim.wo[ng_win].breakindent = true
      vim.wo[ng_win].winfixbuf = false
      vim.wo[ng_win].winfixwidth = true
      ensure_right_sidebar_precedence()
      vim.api.nvim_set_current_win(ng_win)
      pcall(function()
        require('lualine').refresh()
      end)
      return true
    end
    return false
  end

  if not style_neogit_win() then
    vim.schedule(function()
      if not style_neogit_win() then
        vim.defer_fn(style_neogit_win, 60)
      end
    end)
  end
end

function RightPanel.open_dockyard(no_toggle)
  local info = get_win_info()
  if info.is_dockyard then
    if no_toggle then
      return
    end
    RightPanel.close_all()
    local ed = get_editor_win()
    if ed and vim.api.nvim_win_is_valid(ed) then
      vim.api.nvim_set_current_win(ed)
    end
    return
  end

  local existing_dy = find_win_type 'is_dockyard'
  if existing_dy and vim.api.nvim_win_is_valid(existing_dy) then
    RightPanel.active_mode = 'dockyard'
    vim.api.nvim_set_current_win(existing_dy)
    ensure_right_sidebar_precedence()
    pcall(function()
      require('lualine').refresh()
    end)
    return
  end

  RightPanel.close_all()
  RightPanel.active_mode = 'dockyard'

  local ed = get_editor_win()
  if ed and vim.api.nvim_win_is_valid(ed) then
    vim.api.nvim_set_current_win(ed)
  end

  pcall(function()
    require('lazy').load { plugins = { 'dockyard.nvim' } }
  end)

  local ok_dy, dy_ui = pcall(require, 'dockyard.ui')
  if ok_dy and dy_ui and dy_ui.open then
    dy_ui.open()
  else
    vim.cmd 'Dockyard'
  end

  vim.schedule(function()
    ensure_right_sidebar_precedence()
    pcall(function()
      require('lualine').refresh()
    end)
  end)
end

function RightPanel.open_grugfar(no_toggle, opts)
  opts = opts or {}
  local has_prefills = opts.prefills ~= nil and next(opts.prefills) ~= nil
  local info = get_win_info()
  if info.is_grugfar then
    if no_toggle or has_prefills then
      if has_prefills then
        pcall(function()
          local gf = require 'grug-far'
          local inst = gf.get_instance 'right_panel'
          if inst then
            inst:update_input_values(opts.prefills, false)
            inst:search()
          end
        end)
      end
      return
    end
    RightPanel.close_all()
    local ed = get_editor_win()
    if ed and vim.api.nvim_win_is_valid(ed) then
      vim.api.nvim_set_current_win(ed)
    end
    return
  end

  local existing_gf = find_win_type 'is_grugfar'
  if existing_gf and vim.api.nvim_win_is_valid(existing_gf) then
    RightPanel.active_mode = 'grugfar'
    vim.api.nvim_set_current_win(existing_gf)
    if has_prefills then
      pcall(function()
        local gf = require 'grug-far'
        local inst = gf.get_instance 'right_panel'
        if inst then
          inst:update_input_values(opts.prefills, false)
          inst:search()
        end
      end)
    end
    ensure_right_sidebar_precedence()
    pcall(function()
      require('lualine').refresh()
    end)
    return
  end

  RightPanel.close_all()
  RightPanel.active_mode = 'grugfar'

  local ed = get_editor_win()
  if ed and vim.api.nvim_win_is_valid(ed) then
    vim.api.nvim_set_current_win(ed)
  end

  pcall(function()
    require('lazy').load { plugins = { 'grug-far.nvim' } }
  end)

  local ok_gf, grug = pcall(require, 'grug-far')
  if ok_gf and grug then
    local reused = false
    if grug.has_instance and grug.has_instance 'right_panel' then
      local ok_inst, inst = pcall(grug.get_instance, 'right_panel')
      local buf = ok_inst and inst and inst.get_buf and inst:get_buf() or nil
      local is_valid_buf = buf and vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_line_count(buf) > 2 and inst._is_ready == true
      if is_valid_buf and inst.open then
        if inst._context and inst._context.options then
          inst._context.options.windowCreationCommand = 'botright vsplit | setlocal nowinfixbuf'
        end
        inst:open()
        pcall(function()
          require 'grug-far.render'(buf, inst._context)
        end)
        if has_prefills and inst.update_input_values then
          inst:update_input_values(opts.prefills, false)
          inst:search()
        end
        reused = true
      else
        if ok_inst and inst and inst.close then
          pcall(function()
            inst:close()
          end)
        end
        if buf and vim.api.nvim_buf_is_valid(buf) then
          pcall(vim.api.nvim_buf_delete, buf, { force = true })
        end
        pcall(function()
          require('grug-far.instances').remove_instance 'right_panel'
        end)
      end
    end
    if not reused then
      grug.open(vim.tbl_deep_extend('force', { instanceName = 'right_panel', windowCreationCommand = 'botright vsplit | setlocal nowinfixbuf' }, opts))
    end
  else
    vim.cmd 'GrugFar'
  end

  local function style_grugfar_win()
    local gf_win = find_win_type 'is_grugfar'
    if gf_win and vim.api.nvim_win_is_valid(gf_win) then
      local gf_buf = vim.api.nvim_win_get_buf(gf_win)
      vim.b[gf_buf].panel_zone = 'right'
      vim.b[gf_buf].panel_type = 'grugfar'
      vim.bo[gf_buf].buflisted = false
      vim.wo[gf_win].spell = false
      vim.wo[gf_win].wrap = true
      vim.wo[gf_win].linebreak = true
      vim.wo[gf_win].breakindent = true
      vim.wo[gf_win].winfixbuf = false
      vim.wo[gf_win].winfixwidth = true
      ensure_right_sidebar_precedence()
      vim.api.nvim_set_current_win(gf_win)
      pcall(function()
        require('lualine').refresh()
      end)
      return true
    end
    return false
  end

  if not style_grugfar_win() then
    vim.schedule(function()
      if not style_grugfar_win() then
        vim.defer_fn(style_grugfar_win, 60)
      end
    end)
  end
end

function RightPanel.open_slot(slot_idx)
  local m = vim.api.nvim_get_mode().mode
  if m:match '^[it]' then
    vim.cmd 'stopinsert'
  end
  if slot_idx == 1 then
    RightPanel.open_explorer(true)
  elseif slot_idx == 2 then
    RightPanel.open_dbui(true)
  elseif slot_idx == 3 then
    RightPanel.open_opencode(true)
  elseif slot_idx == 4 then
    RightPanel.open_neogit(true)
  elseif slot_idx == 5 then
    RightPanel.open_dockyard(true)
  elseif slot_idx == 6 then
    RightPanel.open_grugfar(true)
  end
end

function RightPanel.lualine_component()
  local ok_hl, hl = pcall(require, 'lualine.highlight')
  local active_hl = 'BufferRingActive'
  local inactive_hl = 'BufferRingInactive'
  local active_cap = 'LualinePillCapActive_normal'
  if ok_hl and hl.get_mode_suffix then
    local suffix = hl.get_mode_suffix()
    local a_name = 'lualine_a' .. suffix
    if vim.fn.hlexists(a_name) == 1 then
      active_hl = a_name
    end
    local b_name = 'lualine_b' .. suffix
    if vim.fn.hlexists(b_name) == 1 then
      inactive_hl = b_name
    end
    local cap_name = 'LualinePillCapActive' .. suffix
    if vim.fn.hlexists(cap_name) == 1 then
      active_cap = cap_name
    end
  end

  local info = get_win_info(vim.api.nvim_get_current_win())
  local cur_mode = RightPanel.active_mode or 'explorer'
  if info.is_explorer then
    cur_mode = 'explorer'
    RightPanel.active_mode = 'explorer'
  elseif info.is_dbui then
    cur_mode = 'dbui'
    RightPanel.active_mode = 'dbui'
  elseif info.is_opencode then
    cur_mode = 'opencode'
    RightPanel.active_mode = 'opencode'
  elseif info.is_neogit then
    cur_mode = 'neogit'
    RightPanel.active_mode = 'neogit'
  elseif info.is_dockyard then
    cur_mode = 'dockyard'
    RightPanel.active_mode = 'dockyard'
  elseif info.is_grugfar then
    cur_mode = 'grugfar'
    RightPanel.active_mode = 'grugfar'
  end

  local slots = {
    { mode = 'explorer', label = '󰙅' },
    { mode = 'dbui', label = '󰆼' },
    { mode = 'opencode', label = '󰚩', is_running = _G.OpencodePromptRunning == true },
    { mode = 'neogit', label = '󰊢' },
    { mode = 'dockyard', label = '󰡨' },
    { mode = 'grugfar', label = '󰛔' },
  }

  local entries = {}
  local num_slots = #slots
  for idx, s in ipairs(slots) do
    local is_active = (s.mode == cur_mode)
    local group = is_active and active_hl or (s.is_running and 'TerminalTrackerRunning' or inactive_hl)
    -- `` provides 1 visual cell on the left of Slot 1, and `` provides 1 visual cell on the right of the last Slot.
    -- Pad inner edges with 2 spaces and cap-adjacent edges with 1 space so every segment is 5 cells wide with the icon at cell 3.
    local left_pad = (idx == 1) and ' ' or '  '
    local right_pad = (idx == num_slots) and ' ' or '  '
    table.insert(entries, {
      is_active = is_active,
      text = string.format('%%#%s#%s%s%s%%*', group, left_pad, s.label, right_pad),
    })
  end

  local left_cap_hl = entries[1].is_active and active_cap or 'LualinePillCap'
  local right_cap_hl = entries[#entries].is_active and active_cap or 'LualinePillCap'

  local parts = {}
  for idx, entry in ipairs(entries) do
    table.insert(parts, entry.text)
    if idx < #entries then
      local next_entry = entries[idx + 1]
      if not entry.is_active and not next_entry.is_active then
        table.insert(parts, '%#LualinePillSep#|%*')
      end
    end
  end

  return string.format('%%#%s#%%*%s%%#%s#%%*', left_cap_hl, table.concat(parts, ''), right_cap_hl)
end

function RightPanel.toggle_active()
  local info = get_win_info()

  -- 1. If currently inside any right panel: close it!
  if is_right_panel(info) then
    RightPanel.close_all()
    local ed = get_editor_win()
    if ed then
      vim.api.nvim_set_current_win(ed)
    end
    return
  end

  -- 2. If a right panel is already visible on screen: focus into it!
  local visible_right = get_right_sidebar_win()

  if visible_right and vim.api.nvim_win_is_valid(visible_right) then
    vim.api.nvim_set_current_win(visible_right)
    return
  end

  -- 3. Otherwise: open the currently active right-side tool
  local mode = RightPanel.active_mode or 'explorer'
  if mode == 'grugfar' then
    RightPanel.open_grugfar()
  elseif mode == 'dockyard' then
    RightPanel.open_dockyard()
  elseif mode == 'neogit' then
    RightPanel.open_neogit()
  elseif mode == 'opencode' then
    RightPanel.open_opencode()
  elseif mode == 'dbui' then
    RightPanel.open_dbui()
  else
    RightPanel.open_explorer()
  end
end

RightPanel.get_editor_win = get_editor_win
RightPanel.get_opencode_cmd = get_opencode_cmd
RightPanel.ensure_precedence = ensure_right_sidebar_precedence
RightPanel.equalize_splits = equalize_splits

-------------------------------------------------------------------------------
-- Unified Bottom-Panel Manager (Persistent Terminals | SQL Results)
-------------------------------------------------------------------------------

local function close_dbout_win(explicit)
  if explicit then
    BottomPanel.dbout_open = false
    if BottomPanel.last_dbout_buf and vim.api.nvim_buf_is_valid(BottomPanel.last_dbout_buf) then
      vim.b[BottomPanel.last_dbout_buf].bottom_order_seq = nil
    end
  end

  local ok_v, view_api = pcall(require, 'sqmeow.api.view')
  if ok_v and view_api and view_api.close then
    pcall(view_api.close)
  end

  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(win) then
      local buf = vim.api.nvim_win_get_buf(win)
      local ft = vim.bo[buf].filetype
      local name = vim.api.nvim_buf_get_name(buf)
      if (ft == 'dbout' or ft == 'sqmeow-result' or name:find 'sqmeow://result') and not name:find 'drawer' then
        if explicit then
          vim.b[buf].bottom_order_seq = nil
        end
        pcall(vim.api.nvim_win_close, win, true)
      end
    end
  end
end

local function close_qf_win(explicit)
  if explicit then
    BottomPanel.qf_open = false
    if BottomPanel.last_qf_buf and vim.api.nvim_buf_is_valid(BottomPanel.last_qf_buf) then
      vim.b[BottomPanel.last_qf_buf].bottom_order_seq = nil
    end
  end

  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(win) then
      local buf = vim.api.nvim_win_get_buf(win)
      if vim.bo[buf].filetype == 'qf' or vim.bo[buf].buftype == 'quickfix' then
        if explicit then
          vim.b[buf].bottom_order_seq = nil
        end
        pcall(vim.api.nvim_win_close, win, true)
      end
    end
  end
end

local function hide_terminal_if_visible()
  local ok, list = pcall(function()
    return Snacks.terminal.list()
  end)
  if ok and type(list) == 'table' then
    for _, t in ipairs(list) do
      if t and t.win and vim.api.nvim_win_is_valid(t.win) and vim.b[t.buf].panel_zone == 'bottom' then
        pcall(function()
          t:hide()
        end)
      end
    end
  end

  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(win) then
      local info = get_win_info(win)
      local ft = vim.bo[info.buf].filetype
      if info.is_terminal and ft ~= 'dbout' and ft ~= 'sqmeow-result' and ft ~= 'qf' and vim.bo[info.buf].buftype ~= 'quickfix' then
        pcall(vim.api.nvim_win_close, win, true)
      end
    end
  end
end

local function get_visible_terminal_info()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(win) then
      local info = get_win_info(win)
      local ft = vim.bo[info.buf].filetype
      if info.is_terminal and ft ~= 'dbout' and ft ~= 'sqmeow-result' and ft ~= 'qf' and vim.bo[info.buf].buftype ~= 'quickfix' then
        local st = vim.b[info.buf].snacks_terminal
        local term_id = st and st.id or 1
        return win, info.buf, term_id
      end
    end
  end
  return nil, nil, nil
end

function BottomPanel.close_all(explicit)
  hide_terminal_if_visible()
  close_dbout_win(explicit)
  close_qf_win(explicit)
  equalize_splits()
  pcall(function()
    require('utils.terminal-tracker').invalidate()
    require('lualine').refresh()
  end)
end

function BottomPanel.open_terminal(count, no_toggle)
  local explicit = (count and count > 0 and count) or (vim.v.count > 0 and vim.v.count) or nil
  if explicit then
    BottomPanel.active_terminal_count = explicit
  end
  local target_count = BottomPanel.active_terminal_count or 1

  close_dbout_win(false)
  close_qf_win(false)
  BottomPanel.active_mode = 'terminal'

  local vis_win, vis_buf, vis_id = get_visible_terminal_info()

  -- If the requested terminal is already visible and no explicit count was given: toggle/hide it
  if vis_win and vis_id == target_count and not explicit and not no_toggle then
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

  local r_win = get_right_sidebar_win()
  local relative = (r_win and vim.api.nvim_win_is_valid(r_win) and ed) and 'win' or 'editor'
  local win_target = (relative == 'win') and ed or nil

  local win_opts = {
    position = 'bottom',
    relative = relative,
    win = win_target,
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
    target_term.opts.relative = relative
    target_term.opts.win = win_target
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
  vim.cmd 'startinsert'
  vim.schedule(function()
    if target_term and target_term.win and vim.api.nvim_win_is_valid(target_term.win) then
      vim.api.nvim_set_current_win(target_term.win)
      vim.cmd 'startinsert'
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
    local bot_win = find_win_type 'is_terminal'
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
  local ed = get_editor_win()
  local r_win = get_right_sidebar_win()
  local relative = (r_win and vim.api.nvim_win_is_valid(r_win) and ed) and 'win' or 'editor'
  local win_target = (relative == 'win') and ed or nil

  Snacks.terminal.open(nil, {
    count = target_count,
    win = {
      position = 'bottom',
      relative = relative,
      win = win_target,
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

  vim.cmd 'startinsert'
  vim.schedule(function()
    ensure_right_sidebar_precedence()
    equalize_splits()
    pcall(function()
      require('utils.terminal-tracker').invalidate()
      require('lualine').refresh()
    end)
  end)
end

function BottomPanel.open_dbout(no_toggle)
  local info = get_win_info()
  if not no_toggle and info.is_terminal and (vim.bo[info.buf].filetype == 'dbout' or vim.bo[info.buf].filetype == 'sqmeow-result') then
    close_dbout_win(false)
    local ed = get_editor_win()
    if ed and vim.api.nvim_win_is_valid(ed) then
      vim.api.nvim_set_current_win(ed)
    end
    return
  end

  local ok_v, view_api = pcall(require, 'sqmeow.api.view')
  if not ok_v then
    pcall(function()
      require('lazy').load { plugins = { 'sqmeow.nvim' } }
    end)
    ok_v, view_api = pcall(require, 'sqmeow.api.view')
  end
  if not ok_v then
    ok_v, view_api = pcall(require, 'sqmeow.api')
  end
  if ok_v and view_api and view_api.open then
    hide_terminal_if_visible()
    close_qf_win(false)
    BottomPanel.active_mode = 'dbout'
    BottomPanel.dbout_open = true
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

    vim.schedule(function()
      ensure_right_sidebar_precedence()
      pcall(function()
        require('utils.terminal-tracker').invalidate()
        require('lualine').refresh()
      end)
    end)
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
  close_qf_win(false)
  BottomPanel.active_mode = 'dbout'
  BottomPanel.dbout_open = true
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
  pcall(function()
    require('utils.terminal-tracker').invalidate()
    require('lualine').refresh()
  end)
end

function BottomPanel.open_qf(no_toggle)
  local info = get_win_info()
  if not no_toggle and info.is_terminal and (vim.bo[info.buf].filetype == 'qf' or vim.bo[info.buf].buftype == 'quickfix') then
    close_qf_win(false)
    local ed = get_editor_win()
    if ed and vim.api.nvim_win_is_valid(ed) then
      vim.api.nvim_set_current_win(ed)
    end
    return
  end

  hide_terminal_if_visible()
  close_dbout_win(false)
  BottomPanel.active_mode = 'qf'
  BottomPanel.qf_open = true

  local ed = get_editor_win()
  if ed and vim.api.nvim_win_is_valid(ed) then
    vim.api.nvim_set_current_win(ed)
  end

  local r_win = get_right_sidebar_win()
  local qf_height = math.floor(vim.o.lines * 0.35)
  if r_win and ed and vim.api.nvim_win_is_valid(ed) then
    vim.api.nvim_set_current_win(ed)
    vim.cmd('belowright copen ' .. qf_height)
  else
    vim.cmd('botright copen ' .. qf_height)
  end
  local win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_win_get_buf(win)
  vim.b[buf].panel_zone = 'bottom'
  vim.b[buf].panel_type = 'qf'
  BottomPanel.last_qf_buf = buf
  vim.wo[win].winfixheight = true
  vim.wo[win].winfixbuf = true
  ensure_right_sidebar_precedence()
  equalize_splits()
  pcall(function()
    require('utils.terminal-tracker').invalidate()
    require('lualine').refresh()
  end)
end

function BottomPanel.open_slot(slot_idx)
  local tracker_ok, tracker = pcall(require, 'utils.terminal-tracker')
  local items = {}
  if tracker_ok and tracker.get_terminals then
    tracker.invalidate()
    items = tracker.get_terminals()
  end

  local target = items[slot_idx]
  if target then
    if target.kind == 'dbout' then
      if vim.api.nvim_get_mode().mode == 't' then
        vim.cmd 'stopinsert'
      end
      BottomPanel.open_dbout(true)
      return
    elseif target.kind == 'qf' then
      if vim.api.nvim_get_mode().mode == 't' then
        vim.cmd 'stopinsert'
      end
      BottomPanel.open_qf(true)
      return
    else
      BottomPanel.open_terminal(target.id, true)
      return
    end
  end

  -- Pressing an empty slot number spawns a new terminal with the lowest unused ID
  local used_ids = {}
  for _, it in ipairs(items) do
    if it.kind == 'terminal' and type(it.id) == 'number' then
      used_ids[it.id] = true
    end
  end
  local new_id = 1
  while used_ids[new_id] do
    new_id = new_id + 1
  end
  BottomPanel.open_terminal(new_id, true)
end

function BottomPanel.toggle_active(count)
  local explicit_count = (count and count > 0 and count) or (vim.v.count > 0 and vim.v.count) or nil
  if explicit_count then
    BottomPanel.open_slot(explicit_count)
    return
  end
  local target_count = BottomPanel.active_terminal_count or 1

  local info = get_win_info()

  -- 1. If currently inside dbout / sqmeow-result, hide it
  if info.is_terminal and (vim.bo[info.buf].filetype == 'dbout' or vim.bo[info.buf].filetype == 'sqmeow-result') then
    close_dbout_win(false)
    local ed = get_editor_win()
    if ed and vim.api.nvim_win_is_valid(ed) then
      vim.api.nvim_set_current_win(ed)
    end
    return
  end

  -- 1b. If currently inside quickfix, hide it
  if info.is_terminal and (vim.bo[info.buf].filetype == 'qf' or vim.bo[info.buf].buftype == 'quickfix') then
    close_qf_win(false)
    local ed = get_editor_win()
    if ed and vim.api.nvim_win_is_valid(ed) then
      vim.api.nvim_set_current_win(ed)
    end
    return
  end

  -- 2. If currently inside a terminal:
  if info.is_terminal and vim.bo[info.buf].filetype ~= 'dbout' and vim.bo[info.buf].filetype ~= 'sqmeow-result' then
    hide_terminal_if_visible()
    local ed = get_editor_win()
    if ed and vim.api.nvim_win_is_valid(ed) then
      vim.api.nvim_set_current_win(ed)
    end
    return
  end

  -- 3. If currently in an explorer/sidebar, focus existing bottom output or open it
  local existing_bot = find_win_type 'is_terminal'
  if existing_bot and vim.api.nvim_win_is_valid(existing_bot) then
    vim.api.nvim_set_current_win(existing_bot)
    return
  end

  -- 4. If in editor and dbout or qf mode is active
  if BottomPanel.active_mode == 'dbout' and BottomPanel.dbout_open and BottomPanel.last_dbout_buf and vim.api.nvim_buf_is_valid(BottomPanel.last_dbout_buf) then
    BottomPanel.open_dbout(true)
    return
  end
  if BottomPanel.active_mode == 'qf' and BottomPanel.qf_open then
    BottomPanel.open_qf(true)
    return
  end

  -- 5. Otherwise, toggle the persistent Snacks terminal with target_count
  BottomPanel.open_terminal(target_count)
end

BottomPanel.hide_terminal = hide_terminal_if_visible
BottomPanel.close_dbout = close_dbout_win
BottomPanel.close_qf = close_qf_win
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
  if is_right_panel(info) then
    RightPanel.close_all()
    local ed = get_editor_win()
    if ed and vim.api.nvim_win_is_valid(ed) then
      vim.api.nvim_set_current_win(ed)
    end
    return
  end

  -- 2. Check if there is a window to the right
  local target_winnr = vim.fn.winnr 'l'
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

    if is_right_panel(target_info) then
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
  if is_right_panel(info) then
    local ed = get_editor_win()
    if ed and vim.api.nvim_win_is_valid(ed) then
      vim.api.nvim_set_current_win(ed)
    end
    return
  end

  -- 2. Check if there is a window to the left
  local target_winnr = vim.fn.winnr 'h'
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

  -- 3. If in bottom panel and at leftmost boundary: cycle to next bottom panel item!
  if info.is_terminal then
    local tracker_ok, tracker = pcall(require, 'utils.terminal-tracker')
    if tracker_ok and tracker.get_terminals then
      local terms = tracker.get_terminals()
      if #terms > 1 then
        local next_slot = 1
        for i, t in ipairs(terms) do
          if t.buf == info.buf then
            next_slot = (i % #terms) + 1
            break
          end
        end
        BottomPanel.open_slot(next_slot)
        return
      end
    end
    return
  end

  try_wincmd 'h'
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

  try_wincmd 'k'
end

local function smart_navigate_down()
  prepare_nav()
  local cur_win = vim.api.nvim_get_current_win()
  local info = get_win_info(cur_win)
  local count = vim.v.count > 0 and vim.v.count or nil

  -- If inside a stacked Right Panel (e.g. Neogit Commit Editor above NeogitStatus, or Dockyard above LogLens/Detail), step down within the Right Panel first
  if info.is_neogit or info.is_dockyard then
    local target_winnr = vim.fn.winnr 'j'
    if target_winnr ~= vim.fn.winnr() then
      local target_win = vim.fn.win_getid(target_winnr)
      local tinfo = get_win_info(target_win)
      if tinfo.is_neogit or tinfo.is_dockyard then
        vim.api.nvim_set_current_win(target_win)
        return
      end
    end
  end

  if info.is_terminal then
    BottomPanel.toggle_active(count)
    return
  end

  local bot_win = find_win_type 'is_terminal'
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
  if not vim.api.nvim_win_is_valid(cur_win) then
    return
  end

  local info = get_win_info(cur_win)

  if is_right_panel(info) then
    delta = -delta
  end

  local cur_w = vim.api.nvim_win_get_width(cur_win)
  local new_w = math.max(12, cur_w + delta)
  pcall(vim.api.nvim_win_set_width, cur_win, new_w)

  RightPanel.custom_widths = RightPanel.custom_widths or {}
  if info.is_neogit then
    RightPanel.custom_widths['neogit'] = new_w
  elseif info.is_dockyard then
    RightPanel.custom_widths['dockyard'] = new_w
  elseif info.is_grugfar then
    RightPanel.custom_widths['grugfar'] = new_w
  elseif info.is_opencode then
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
  if not vim.api.nvim_win_is_valid(cur_win) then
    return
  end

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
    vim.cmd 'split'
  else
    RightPanel.has_custom_editor_widths = false
    for _, w in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_is_valid(w) and get_win_info(w).is_editor then
        vim.w[w].custom_split_ratio = nil
      end
    end
    vim.cmd 'vsplit'
  end
  ensure_right_sidebar_precedence()
end

local function smart_close_window(fallback_close_fn)
  local cur_win = vim.api.nvim_get_current_win()
  if not vim.api.nvim_win_is_valid(cur_win) then
    return
  end
  local info = get_win_info(cur_win)

  if is_right_panel(info) then
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
  if not vim.api.nvim_buf_is_valid(buf) then
    return false
  end
  local ft = vim.bo[buf].filetype
  if
    ft == 'sqmeow-drawer'
    or ft == 'sqmeow-result'
    or ft == 'sqmeow-output'
    or ft == 'dbui'
    or ft == 'dbout'
    or ft == 'snacks_dashboard'
    or ft == 'snacks_terminal'
    or ft:match '^Neogit' ~= nil
    or ft == 'dockyard'
    or ft == 'dockyard-logs'
    or ft == 'dockyard-files'
    or ft == 'dockyard_popup'
    or ft == 'grug-far'
    or ft == 'grug-far-help'
    or ft == 'grug-far-history'
  then
    return true
  end
  local bname = vim.api.nvim_buf_get_name(buf)
  if
    (bname:match '^%[Preview:' or bname:match '^%[Alter:' or bname:match '^%[Routine:' or vim.b[buf].is_preview_buffer) and vim.bo[buf].buftype == 'nofile'
  then
    return true
  end
  if bname:find '/db_ui/' ~= nil then
    return true
  end
  if bname:match '%.sqlite%d?$' or bname:match '%.db$' then
    return true
  end
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

  vim.api.nvim_create_autocmd({ 'WinEnter', 'BufWinEnter' }, {
    group = layout_lock_group,
    callback = function()
      local win = vim.api.nvim_get_current_win()
      if not vim.api.nvim_win_is_valid(win) then
        return
      end
      local cfg = vim.api.nvim_win_get_config(win)
      if (not cfg.relative or cfg.relative == '') and get_win_info(win).is_editor then
        last_editor_win = win
        vim.wo[win].winfixbuf = false
        vim.wo[win].winfixwidth = false
        vim.wo[win].winfixheight = false
      end
    end,
    desc = 'Track last focused non-floating editor window for multi-split navigation',
  })

  vim.api.nvim_create_autocmd({ 'FileType', 'BufWinEnter' }, {
    group = layout_lock_group,
    pattern = '*',
    callback = function(args)
      local buf = args.buf
      if not vim.api.nvim_buf_is_valid(buf) then
        return
      end

      local ft = vim.bo[buf].filetype
      if ft == 'snacks_picker_preview' or ft == 'snacks_picker_input' then
        vim.bo[buf].buflisted = false
        return
      end

      local win = vim.fn.bufwinid(buf)
      if not (win and win ~= -1 and vim.api.nvim_win_is_valid(win)) then
        return
      end

      local cfg = vim.api.nvim_win_get_config(win)
      if cfg.relative and cfg.relative ~= '' then
        return
      end

      local info = get_win_info(win)

      if is_right_panel(info) then
        vim.bo[buf].buflisted = false
        if vim.api.nvim_win_is_valid(win) then
          -- Allow in-place buffer switching for Neogit (log/commit/refs views), Dockyard (f/q), and GrugFar (history/preview)
          vim.wo[win].winfixbuf = not (info.is_neogit or info.is_dockyard or info.is_grugfar)
          vim.wo[win].winfixwidth = true
        end
        if info.is_neogit then
          vim.b[buf].panel_zone = 'right'
          vim.b[buf].panel_type = 'neogit'
          vim.wo[win].spell = false
          vim.wo[win].wrap = true
          vim.wo[win].linebreak = true
          vim.wo[win].breakindent = true
          RightPanel.active_mode = 'neogit'
          vim.schedule(function()
            if vim.api.nvim_win_is_valid(win) then
              vim.wo[win].wrap = true
              vim.wo[win].linebreak = true
              vim.wo[win].breakindent = true
            end
            ensure_right_sidebar_precedence()
            pcall(function()
              require('lualine').refresh()
            end)
          end)
        elseif info.is_dockyard then
          vim.b[buf].panel_zone = 'right'
          vim.b[buf].panel_type = 'dockyard'
          vim.wo[win].spell = false
          RightPanel.active_mode = 'dockyard'
          vim.schedule(function()
            ensure_right_sidebar_precedence()
            pcall(function()
              require('lualine').refresh()
            end)
          end)
        elseif info.is_grugfar then
          vim.b[buf].panel_zone = 'right'
          vim.b[buf].panel_type = 'grugfar'
          vim.wo[win].spell = false
          vim.wo[win].wrap = true
          vim.wo[win].linebreak = true
          vim.wo[win].breakindent = true
          RightPanel.active_mode = 'grugfar'
          vim.schedule(function()
            if vim.api.nvim_win_is_valid(win) then
              vim.wo[win].wrap = true
              vim.wo[win].linebreak = true
              vim.wo[win].breakindent = true
            end
            ensure_right_sidebar_precedence()
            pcall(function()
              require('lualine').refresh()
            end)
          end)
        end
      elseif info.is_terminal then
        vim.bo[buf].buflisted = false
        if vim.api.nvim_win_is_valid(win) then
          vim.wo[win].winfixbuf = true
          vim.wo[win].winfixheight = true
        end
      elseif info.is_editor then
        if vim.api.nvim_win_is_valid(win) then
          vim.wo[win].winfixbuf = false
          vim.wo[win].winfixwidth = false
          vim.wo[win].winfixheight = false
        end
      end
    end,
  })

  vim.api.nvim_create_autocmd('WinClosed', {
    group = layout_lock_group,
    callback = function()
      if vim.v.exiting ~= vim.NIL and vim.v.exiting ~= nil then
        return
      end
      vim.schedule(function()
        if vim.v.exiting ~= vim.NIL and vim.v.exiting ~= nil then
          return
        end

        local editor_win = get_editor_win()
        if not editor_win then
          local non_editor_exists = false
          for _, w in ipairs(vim.api.nvim_list_wins()) do
            if vim.api.nvim_win_is_valid(w) then
              local cfg = vim.api.nvim_win_get_config(w)
              if not cfg.relative or cfg.relative == '' then
                local info = get_win_info(w)
                if is_right_panel(info) or info.is_terminal then
                  non_editor_exists = true
                  break
                end
              end
            end
          end

          if non_editor_exists then
            vim.cmd 'topleft split'
            local new_win = vim.api.nvim_get_current_win()
            vim.wo[new_win].winfixbuf = false
            vim.wo[new_win].winfixwidth = false
            vim.wo[new_win].winfixheight = false
            vim.cmd 'enew'
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
        pcall(function()
          require('persistence').stop()
        end)
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
    pattern = '*',
    callback = function(args)
      local buf = args.buf
      if not vim.api.nvim_buf_is_valid(buf) then
        return
      end
      local ft = vim.bo[buf].filetype
      local name = vim.api.nvim_buf_get_name(buf)
      if (ft == 'dbout' or ft == 'sqmeow-result' or name:find 'sqmeow://result' ~= nil) and ft ~= 'sqmeow-drawer' and not name:find 'drawer' then
        vim.b[buf].panel_zone = 'bottom'
        vim.b[buf].panel_type = 'dbout'
        BottomPanel.last_dbout_buf = buf
        BottomPanel.dbout_open = true
        BottomPanel.active_mode = 'dbout'
        hide_terminal_if_visible()
        close_qf_win(false)
        local win = vim.fn.bufwinid(buf)
        if win and win ~= -1 and vim.api.nvim_win_is_valid(win) then
          vim.schedule(ensure_right_sidebar_precedence)
        end
      elseif ft == 'qf' or vim.bo[buf].buftype == 'quickfix' then
        vim.b[buf].panel_zone = 'bottom'
        vim.b[buf].panel_type = 'qf'
        BottomPanel.last_qf_buf = buf
        BottomPanel.qf_open = true
        BottomPanel.active_mode = 'qf'
        hide_terminal_if_visible()
        close_dbout_win(false)
        local win = vim.fn.bufwinid(buf)
        if win and win ~= -1 and vim.api.nvim_win_is_valid(win) then
          vim.wo[win].winfixheight = true
          vim.wo[win].winfixbuf = true
          vim.schedule(ensure_right_sidebar_precedence)
        end
      end
    end,
  })

  -- Track active terminal instance automatically when entering a terminal buffer
  vim.api.nvim_create_autocmd({ 'BufEnter', 'TermOpen' }, {
    callback = function(args)
      local st = vim.b[args.buf].snacks_terminal
      local is_opencode = tostring(st and st.cmd or ''):find 'opencode' or vim.b[args.buf].panel_type == 'opencode'
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
