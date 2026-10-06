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

-- Toggle Markdown Dictionary Autocomplete in Blink.cmp (Disabled by default to prevent lag)
local function toggle_markdown_dict()
  vim.g.markdown_dict_completion = not vim.g.markdown_dict_completion
  local state = vim.g.markdown_dict_completion and 'Enabled' or 'Disabled'
  vim.notify('Markdown Dictionary Autocomplete: ' .. state, vim.log.levels.INFO, { title = 'Completion' })
end
_G.toggle_markdown_dict = toggle_markdown_dict
vim.api.nvim_create_user_command('MarkdownDictToggle', toggle_markdown_dict, { desc = 'Toggle Markdown Dictionary Autocomplete' })
vim.keymap.set('n', '<leader>ms', toggle_markdown_dict, { desc = 'Toggle Dictionary Completion' })

-- Toggle Markdown Autocomplete (Disabled by default)
vim.g.markdown_autocomplete_enabled = false
local function toggle_markdown_autocomplete()
  vim.g.markdown_autocomplete_enabled = not vim.g.markdown_autocomplete_enabled
  local state = vim.g.markdown_autocomplete_enabled and 'Enabled (Normal Auto-Popups)' or 'Disabled'
  vim.notify('Markdown Autocomplete: ' .. state, vim.log.levels.INFO, { title = 'Completion' })
end
_G.toggle_markdown_autocomplete = toggle_markdown_autocomplete
vim.api.nvim_create_user_command('MarkdownAutocompleteToggle', toggle_markdown_autocomplete, { desc = 'Toggle Markdown Autocomplete' })
vim.keymap.set('n', '<leader>mp', toggle_markdown_autocomplete, { desc = 'Toggle Markdown Autocomplete' })



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

local RightPanel = {
  active_mode = 'explorer',
  custom_widths = {},
  has_custom_editor_widths = false,
  has_custom_bottom_widths = false,
}

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

  -- Check Database Explorer Drawer (DBUI or Sqmeow)
  local is_dbui = ft == 'dbui' or ft == 'sqmeow-drawer'

  -- Check OpenCode Terminal (differentiate from bottom terminals)
  local is_opencode = ft:match('opencode') ~= nil
    or bname:find('opencode') ~= nil
    or (vim.b[buf].snacks_terminal and vim.b[buf].snacks_terminal.cmd and tostring(vim.b[buf].snacks_terminal.cmd):find('opencode') ~= nil)
    or (RightPanel.active_mode == 'opencode' and (ft == 'snacks_terminal' or ft == 'terminal') and not bname:find('term://'))

  -- Check Terminal / Database Query Results Table (only if NOT opencode)
  local is_terminal = (not is_opencode) and (ft == 'dbout' or ft == 'sqmeow-result' or ft == 'snacks_terminal' or ft == 'terminal' or bname:find('term://') ~= nil)

  -- Check Editor (any non-sidebar, non-terminal, non-dashboard tiled window)
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

-- Dynamically equalize split widths in Editor and Bottom zones (accounting for open sidebars)
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

_G.equalize_splits = equalize_splits

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

local function get_editor_win()
  -- If current window is an editor window, keep focus on it
  local cur = vim.api.nvim_get_current_win()
  if vim.api.nvim_win_is_valid(cur) then
    local cfg = vim.api.nvim_win_get_config(cur)
    if (not cfg.relative or cfg.relative == '') and get_win_info(cur).is_editor then
      return cur
    end
  end

  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(win) then
      local cfg = vim.api.nvim_win_get_config(win)
      if not cfg.relative or cfg.relative == '' then
        local info = get_win_info(win)
        if info.is_editor then
          return win
        end
      end
    end
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

RightPanel.get_editor_win = get_editor_win
RightPanel.close = function() RightPanel.close_all() end

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
      if ft == 'dbui' or ft == 'sqmeow-drawer' then
        pcall(function()
          local ok_v, view = pcall(require, 'sqmeow.api.view')
          if ok_v and view then
            view.close_drawer()
          else
            require('sqmeow.api').close_drawer()
          end
        end)
        pcall(vim.api.nvim_win_close, win, true)
      elseif (ft:match('opencode') or bname:find('opencode')) and not (ok_t and term and term.win == win) then
        pcall(vim.api.nvim_win_close, win, true)
      end
    end
  end

  vim.schedule(function()
    equalize_splits()
  end)
end

-- Ensure explorer git status cache is populated so frame 1 renders without flashing gitignored files
local function ensure_explorer_git_ready(cwd)
  local ok_git, Git = pcall(require, 'snacks.explorer.git')
  if not ok_git or not Git.is_dirty then return end
  cwd = cwd or vim.fn.getcwd()
  if Git.is_dirty(cwd) then
    local root = (Snacks.git and Snacks.git.get_root(cwd)) or cwd
    if root and vim.fn.isdirectory(root .. '/.git') == 1 then
      local ok_sys, obj = pcall(function()
        return vim.system({
          'git',
          '--no-pager',
          '--no-optional-locks',
          'status',
          '--porcelain=v1',
          '--ignored=matching',
          '-z',
          '-unormal',
        }, { cwd = root }):wait()
      end)
      if ok_sys and obj and obj.code == 0 and obj.stdout then
        local ret = {}
        for _, line in ipairs(vim.split(obj.stdout, '\0')) do
          if line ~= '' then
            local status, file = line:match('^(..) (.+)$')
            if status then
              ret[#ret + 1] = { status = status, file = root .. '/' .. file }
            end
          end
        end
        Git.state[root] = Git.state[root] or { tick = 0, last = 0 }
        Git.state[root].last = os.time()
        Git.state[root].tick = Git.state[root].tick + 1
        if Git._update then
          Git._update(cwd, ret)
        end
      end
    end
  end
end

-- Open File Explorer on the right (35 cols default) and set active_mode = 'explorer'
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

-- Open Database Explorer on the right (35 cols default) and set active_mode = 'dbui'
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

-- Open OpenCode AI on the right (38% width default, persistent background session)
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
        -- OpenCode uses spaces in prompts, so never treat Space+t as a terminal toggle here.
        vim.keymap.set('t', '<leader>t', '<Space>t', { buffer = term.buf, noremap = true, silent = true })
      end,
    },
  })
  vim.schedule(ensure_right_sidebar_precedence)
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
      local ft = vim.bo[buf].filetype
      if ft == 'dbout' or ft == 'sqmeow-result' then
        pcall(function()
          local ok_v, view = pcall(require, 'sqmeow.api.view')
          if ok_v and view then
            view.close()
          else
            require('sqmeow.api').close()
          end
        end)
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
  pcall(function()
    require('utils.terminal-tracker').invalidate()
    require('lualine').refresh()
  end)
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

  -- If a DIFFERENT terminal instance is visible, hide it first so we show the target terminal cleanly
  if vis_win and vis_id ~= target_count then
    hide_terminal_if_visible()
  end

  local ed = get_editor_win()
  if ed and vim.api.nvim_win_is_valid(ed) then
    vim.api.nvim_set_current_win(ed)
  end

  local r_win = get_right_sidebar_win()
  local ed_wins = {}
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(w) then
      local cfg = vim.api.nvim_win_get_config(w)
      if not cfg.relative or cfg.relative == '' then
        local info = get_win_info(w)
        if info.is_editor then
          table.insert(ed_wins, w)
        end
      end
    end
  end

  local win_opts = {
    position = 'bottom',
    height = 0.38,
    wo = {
      winbar = '',
      winfixheight = true,
      winfixbuf = true,
    },
  }

  local target_term = nil

  local function open_or_show(wopts)
    local term = Snacks.terminal.get(nil, {
      count = target_count,
      create = true,
      win = wopts,
    })
    if term then
      term:show()
      target_term = term
    end
  end

  if r_win and #ed_wins <= 1 and ed and vim.api.nvim_win_is_valid(ed) then
    win_opts.relative = 'win'
    win_opts.win = ed
    open_or_show(win_opts)
  elseif r_win and #ed_wins > 1 then
    table.sort(ed_wins, function(a, b)
      return vim.api.nvim_win_get_position(a)[2] < vim.api.nvim_win_get_position(b)[2]
    end)
    local ed1 = ed_wins[1]
    local other_bufs = {}
    for i = 2, #ed_wins do
      table.insert(other_bufs, vim.api.nvim_win_get_buf(ed_wins[i]))
      pcall(vim.api.nvim_win_close, ed_wins[i], true)
    end

    win_opts.relative = 'win'
    win_opts.win = ed1
    open_or_show(win_opts)

    vim.api.nvim_win_call(ed1, function()
      for _, b in ipairs(other_bufs) do
        vim.cmd('vsplit')
        local nw = vim.api.nvim_get_current_win()
        vim.api.nvim_win_set_buf(nw, b)
      end
    end)
  else
    win_opts.relative = 'editor'
    open_or_show(win_opts)
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

-- Split terminal vertically inside the bottom panel (side-by-side terminal instances)
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

  -- Use Snacks native terminal stacking: opening another terminal when position='bottom'
  -- automatically creates a side-by-side split inside the bottom panel
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

-- Open or toggle the SQL Query Output window (dbout / sqmeow-result)
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

    -- Ensure focus moves directly to the query result window instead of remaining in editor
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

  -- Find last dbout buffer
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

-- Unified <C-j> Action: Toggle / Focus bottom output zone preserving terminal instances & count
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
  pattern = { 'dbout', 'sqmeow-result' },
  callback = function(args)
    BottomPanel.last_dbout_buf = args.buf
    BottomPanel.active_mode = 'dbout'
    -- Sqmeow creates its result split directly, so hide the shell before both remain visible.
    hide_terminal_if_visible()
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
  if vim.api.nvim_get_mode().mode == 't' then
    vim.cmd('stopinsert')
  end
  local cur_win = vim.api.nvim_get_current_win()
  if not vim.api.nvim_win_is_valid(cur_win) then return end

  local cur_buf = vim.api.nvim_win_get_buf(cur_win)
  local info = get_win_info(cur_win)

  -- 0. If inside any floating window: close cleanly
  local cfg = vim.api.nvim_win_get_config(cur_win)
  if cfg.relative and cfg.relative ~= '' then
    pcall(vim.api.nvim_win_close, cur_win, true)
    return
  end

  -- 1. If inside Right Panel (Explorer, DBUI, AI): close/hide the Right Panel
  if info.is_explorer or info.is_dbui or info.is_opencode then
    RightPanel.close_all()
    local ed = get_editor_win()
    if ed and vim.api.nvim_win_is_valid(ed) then
      vim.api.nvim_set_current_win(ed)
    end
    return
  end

  -- 2. If inside Bottom Panel (Terminal, SQL Results): terminate terminal or close panel
  if info.is_terminal then
    local is_real_term = (vim.bo[cur_buf].buftype == 'terminal' or vim.bo[cur_buf].filetype == 'snacks_terminal' or vim.bo[cur_buf].filetype == 'terminal' or vim.api.nvim_buf_get_name(cur_buf):match('^term://') ~= nil)

    local cur_term_id = (vim.b[cur_buf].snacks_terminal and vim.b[cur_buf].snacks_terminal.id) or BottomPanel.active_terminal_count or 1

    if is_real_term then
      local job_id = vim.api.nvim_buf_is_valid(cur_buf) and vim.b[cur_buf].terminal_job_id or nil
      -- Detach Snacks terminal event listeners so intentional quit does not trigger "Terminal exited with code -1"
      local ok_list, list = pcall(function() return Snacks.terminal.list() end)
      if ok_list and type(list) == 'table' then
        for _, t in ipairs(list) do
          if t and t.buf == cur_buf then
            if t.augroup then
              pcall(vim.api.nvim_del_augroup_by_id, t.augroup)
            end
            pcall(function() t:destroy() end)
          end
        end
      end

      if job_id then
        pcall(vim.fn.jobstop, job_id)
      end
      if vim.api.nvim_buf_is_valid(cur_buf) then
        pcall(vim.api.nvim_buf_delete, cur_buf, { force = true })
      end
      pcall(function()
        local tracker = require('utils.terminal-tracker')
        tracker.invalidate()
      end)
    end

    local bot_wins = {}
    for _, w in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_is_valid(w) and w ~= cur_win and get_win_info(w).is_terminal then
        table.insert(bot_wins, w)
      end
    end

    if #bot_wins > 0 then
      if vim.api.nvim_win_is_valid(cur_win) then
        pcall(vim.api.nvim_win_close, cur_win, true)
      end
      if vim.api.nvim_win_is_valid(bot_wins[1]) then
        vim.api.nvim_set_current_win(bot_wins[1])
        vim.cmd('startinsert')
      end
      equalize_splits()
    else
      -- Check if any other terminal instances exist in background
      local tracker_ok, tracker = pcall(require, 'utils.terminal-tracker')
      local remaining = {}
      if tracker_ok and tracker.get_terminals then
        tracker.invalidate()
        remaining = tracker.get_terminals()
      end

      if #remaining > 0 then
        -- Move to the next available terminal instance (staying inside terminal)
        local next_id = remaining[1].id
        for _, t in ipairs(remaining) do
          if t.id > cur_term_id then
            next_id = t.id
            break
          end
        end

        BottomPanel.active_terminal_count = next_id
        if vim.api.nvim_win_is_valid(cur_win) then
          pcall(vim.api.nvim_win_close, cur_win, true)
        end
        BottomPanel.open_terminal(next_id)
        return
      else
        -- No terminals left: close bottom panel and return to code editor
        BottomPanel.close_all()
        BottomPanel.active_terminal_count = 1
        local ed = get_editor_win()
        if ed and vim.api.nvim_win_is_valid(ed) then
          vim.api.nvim_set_current_win(ed)
        end
      end
    end

    pcall(function() require('lualine').refresh() end)
    return
  end

  -- 3. If inside Snacks Dashboard: do nothing
  if vim.bo[cur_buf].filetype == 'snacks_dashboard' then
    return
  end

  -- 4. In Code Editor: safely close buffer while preserving window splits!
  local ring_ok, ring = pcall(require, 'utils.buffer-ring')
  local next_target = nil

  if ring_ok and ring then
    ring.clean_slots()
    -- Look for another valid buffer in the buffer ring
    for i = 1, ring.max_slots do
      local b = ring.slots[i]
      if b and b ~= cur_buf and vim.api.nvim_buf_is_valid(b) then
        next_target = b
        break
      end
    end
    ring.on_buf_delete(cur_buf)
  end

  if next_target and vim.api.nvim_buf_is_valid(next_target) then
    -- Switch to the next active buffer in the user's buffer ring
    pcall(vim.api.nvim_win_set_buf, cur_win, next_target)
    local ok, snacks = pcall(require, 'snacks')
    if ok and snacks.bufdelete then
      snacks.bufdelete({ buf = cur_buf })
    else
      pcall(vim.cmd, 'bdelete ' .. cur_buf)
    end
  else
    -- cur_buf was the ONLY buffer open in the ring!
    -- Leave the user with no open buffers (a clean [No Name] buffer),
    -- wiping cur_buf and any background ghost buffers so nothing else opens.
    local new_buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_win_set_buf(cur_win, new_buf)

    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      if b ~= new_buf and vim.api.nvim_buf_is_valid(b) and vim.bo[b].buflisted then
        pcall(vim.api.nvim_buf_delete, b, { force = true })
      end
    end

    if ring_ok and ring and ring.clean_slots then
      ring.clean_slots()
    end
    pcall(function() require('lualine').refresh() end)

    -- If all buffers were closed, remove the project session file so it doesn't restore old files later
    local ok_p, persistence = pcall(require, 'persistence')
    if ok_p and persistence.current then
      local sfile = persistence.current()
      if sfile and vim.fn.filereadable(sfile) == 1 then
        pcall(vim.fn.delete, sfile)
      end
      local fallback = persistence.current({ branch = false })
      if fallback and vim.fn.filereadable(fallback) == 1 then
        pcall(vim.fn.delete, fallback)
      end
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
  local ok, ring = pcall(require, 'utils.buffer-ring')
  if ok and ring.next_buffer then
    ring.next_buffer()
  else
    vim.cmd('bnext')
  end
end

local function smart_bprev()
  local info = get_win_info()
  if not info.is_editor then
    local ed = get_editor_win()
    if ed and vim.api.nvim_win_is_valid(ed) then
      vim.api.nvim_set_current_win(ed)
    end
  end
  local ok, ring = pcall(require, 'utils.buffer-ring')
  if ok and ring.prev_buffer then
    ring.prev_buffer()
  else
    vim.cmd('bprevious')
  end
end

_G.smart_close = smart_close
vim.keymap.set('n', '<leader>q', smart_close, { desc = 'Close Buffer' })
vim.keymap.set({ 'n', 't', 'i' }, '<C-q>', smart_close, { desc = 'Close Buffer / Quit Terminal' })

-- Smart slot navigation (<C-1> through <C-4>) across Editor, Terminal, and Sidebar
local function smart_goto_slot(n)
  local cur_win = vim.api.nvim_get_current_win()
  local info = get_win_info(cur_win)

  -- 1. In Terminal: switch to terminal instance n directly in terminal mode
  if info.is_terminal then
    BottomPanel.open_terminal(n)
    return
  end

  if vim.api.nvim_get_mode().mode == 't' then
    vim.cmd('stopinsert')
  end

  -- 2. In Right Panel (Explorer, DBUI, AI): return to editor first
  if info.is_explorer or info.is_dbui or info.is_opencode then
    local ed = get_editor_win()
    if ed and vim.api.nvim_win_is_valid(ed) then
      vim.api.nvim_set_current_win(ed)
    end
  end

  -- 3. In Editor: jump to buffer slot n, or trigger filetype creation picker (<leader>n)
  local ring_ok, ring = pcall(require, 'utils.buffer-ring')
  if ring_ok and ring then
    ring.clean_slots()
    local target = ring.slots[n]
    if target and vim.api.nvim_buf_is_valid(target) then
      ring.jump(n)
    else
      if ring.create_filetype_buffer then
        ring.create_filetype_buffer(n)
      else
        vim.cmd('enew')
      end
    end
  else
    pcall(vim.cmd, 'buffer ' .. n)
  end
end

for i = 1, 4 do
  vim.keymap.set({ 'n', 't', 'i' }, '<C-' .. i .. '>', function()
    smart_goto_slot(i)
  end, { desc = 'Go to / Create Buffer or Terminal ' .. i })

  vim.keymap.set('n', '<leader>' .. i, function()
    smart_goto_slot(i)
  end, { desc = 'Go to / Create Buffer or Terminal ' .. i })

  vim.keymap.set({ 'n', 't', 'i' }, '<M-' .. i .. '>', function()
    smart_goto_slot(i)
  end, { desc = 'Go to / Create Buffer or Terminal ' .. i .. ' (Alt fallback)' })
end
-- Terminal emulator fallback: <C-2> often sends NUL (<C-@>)
vim.keymap.set({ 'n', 't', 'i' }, '<C-@>', function()
  smart_goto_slot(2)
end, { desc = 'Go to / Create Buffer or Terminal 2 (C-2 fallback)' })
vim.keymap.set('n', '<leader>n', function()
  local ok, ring = pcall(require, 'utils.buffer-ring')
  if ok and ring.create_filetype_buffer then
    ring.create_filetype_buffer()
  else
    vim.cmd('enew')
  end
end, { desc = 'New Buffer (with Filetype)' })
vim.keymap.set('n', '<leader>ct', function()
  local ok, ring = pcall(require, 'utils.buffer-ring')
  if ok and ring.change_filetype then
    ring.change_filetype()
  end
end, { desc = 'Change Filetype' })
vim.keymap.set('n', '<leader>p', function()
  require('utils.buffer-ring').toggle_pin()
end, { desc = 'Toggle Pin Buffer' })
vim.keymap.set('n', '<leader>Q', '<cmd>confirm qa<CR>', { desc = 'Quit Neovim' })
vim.keymap.set('n', '<leader><Tab>', smart_bnext, { desc = 'Next Buffer' })
vim.keymap.set('n', '<leader><S-Tab>', smart_bprev, { desc = 'Previous Buffer' })
vim.keymap.set('n', '<leader>r', '<C-6>', { desc = 'Alternate Buffer' })

-------------------------------------------------------------------------------
-- Window Split Management (<leader>w)
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

local function smart_close_window()
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

  -- Inside Code Editor:
  local editor_count = 0
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(w) and get_win_info(w).is_editor then
      editor_count = editor_count + 1
    end
  end

  if editor_count > 1 then
    pcall(vim.api.nvim_win_close, cur_win, false)
    ensure_right_sidebar_precedence()
  else
    -- Last editor window: do not collapse the editor zone!
    smart_close()
  end
end

vim.keymap.set('n', '<leader>ws', function() editor_split('horizontal') end, { desc = 'Split Horizontally' })
vim.keymap.set('n', '<leader>wv', function() editor_split('vertical') end, { desc = 'Split Vertically' })
vim.keymap.set('n', '<leader>we', function() _G.reset_window_layout() end, { desc = 'Balance Window Splits' })
vim.keymap.set('n', '<leader>wq', smart_close_window, { desc = 'Close Window Split' })
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
  if ft == 'sqmeow-drawer' or ft == 'sqmeow-output' or ft == 'dbui' or ft == 'dbout' or ft == 'snacks_dashboard' or ft == 'snacks_terminal' then return true end
  local bname = vim.api.nvim_buf_get_name(buf)
  if bname:match('^%[') or vim.b[buf].is_preview_buffer then return true end
  if bname:find('/sqmeow/') ~= nil or bname:find('/db_ui/') ~= nil then return true end
  if bname:match('%.sqlite%d?$') or bname:match('%.db$') then return true end
  if vim.b[buf].sqmeow_connection ~= nil or vim.b[buf].dbui_db_key_name ~= nil then return true end
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
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buflisted and vim.bo[buf].modified then
      vim.notify('Save or discard modified buffers before opening dashboard', vim.log.levels.WARN, { title = 'Dashboard' })
      return
    end
  end

  cleanup_panels_before_save()
  local real_bufs = get_real_editor_bufs()
  if #real_bufs > 0 then
    pcall(function() require('persistence').save() end)
  end

  local ok_snacks, snacks = pcall(require, 'snacks')
  if ok_snacks and snacks.bufdelete then
    snacks.bufdelete.all()
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
      vim.schedule(function()
        if vim.api.nvim_win_is_valid(win) then
          vim.wo[win].winfixbuf = true
          vim.wo[win].winfixwidth = true
          ensure_right_sidebar_precedence()
        end
      end)
    elseif info.is_terminal then
      vim.bo[buf].buflisted = false
      vim.schedule(function()
        if vim.api.nvim_win_is_valid(win) then
          vim.wo[win].winfixbuf = true
          vim.wo[win].winfixheight = true
          ensure_right_sidebar_precedence()
        end
      end)
    end
  end,
})

-- Prevent Right Panel or Bottom Panel from expanding to 100% when editor split closes
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

-- Re-balance splits and enforce sidebar geometry on terminal emulator window resize
vim.api.nvim_create_autocmd('VimResized', {
  group = layout_lock_group,
  callback = function()
    vim.schedule(function()
      ensure_right_sidebar_precedence()
    end)
  end,
  desc = 'Auto-equalize splits and enforce sidebar geometry on terminal resize',
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

-- Smart directional navigation & Right Panel Toggle
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

    -- In editor: move to the rightward editor split
    if info.is_editor and target_info.is_editor then
      vim.api.nvim_set_current_win(target_win)
      return
    end

    -- In bottom panel: move to the rightward bottom split (e.g. terminal 2)
    if info.is_terminal and target_info.is_terminal then
      vim.api.nvim_set_current_win(target_win)
      return
    end

    -- Target window is a right-side panel: focus into it!
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

    -- In editor: move to the leftward editor split
    if info.is_editor and target_info.is_editor then
      vim.api.nvim_set_current_win(target_win)
      return
    end

    -- In bottom panel: move to the leftward bottom split
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

  -- 4. Otherwise try standard wincmd h
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

  -- If currently inside bottom panel: toggle/hide it
  if info.is_terminal then
    BottomPanel.toggle_active(count)
    return
  end

  -- If a bottom panel is already visible:
  local bot_win = find_win_type('is_terminal')
  if bot_win and vim.api.nvim_win_is_valid(bot_win) then
    if count then
      BottomPanel.open_terminal(count)
    else
      vim.api.nvim_set_current_win(bot_win)
    end
    return
  end

  -- Otherwise toggle/open bottom panel
  BottomPanel.toggle_active(count)
end

-- <C-l>: Spatial navigation right / Right Panel Toggle
vim.keymap.set({ 'n', 't', 'i' }, '<C-l>', smart_navigate_right, { desc = 'Right / Right Panel' })

-- <C-h>: Spatial navigation left / Return from Right Panel
vim.keymap.set({ 'n', 't', 'i' }, '<C-h>', smart_navigate_left, { desc = 'Left / Editor' })

-- <C-k>: Spatial navigation up / Return from Bottom Panel
vim.keymap.set({ 'n', 't', 'i' }, '<C-k>', smart_navigate_up, { desc = 'Up / Editor' })

-- <C-j>: Spatial navigation down / Focus or Toggle Bottom Output
vim.keymap.set({ 'n', 't', 'i' }, '<C-j>', smart_navigate_down, { desc = 'Down / Bottom Output' })

-- <leader>t: Direct Terminal Toggle & Switch Bottom Mode
vim.keymap.set({ 'n', 't' }, '<leader>t', function()
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
  local default_bot_height = math.floor(vim.o.lines * 0.38)

  RightPanel.custom_widths = {}
  RightPanel.has_custom_editor_widths = false
  RightPanel.has_custom_bottom_widths = false

  local cur = vim.api.nvim_get_current_win()

  -- Re-apply exact sidebar widths and bottom panel heights, clear custom ratios
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(win) then
      vim.w[win].custom_split_ratio = nil
      local cfg = vim.api.nvim_win_get_config(win)
      if not cfg.relative or cfg.relative == '' then
        local info = get_win_info(win)
        if info.is_opencode then
          pcall(vim.api.nvim_win_set_width, win, math.max(45, math.floor(vim.o.columns * 0.38)))
        elseif info.is_explorer or info.is_dbui then
          pcall(vim.api.nvim_win_set_width, win, 35)
        elseif info.is_terminal then
          pcall(vim.api.nvim_win_set_height, win, default_bot_height)
        end
      end
    end
  end

  ensure_right_sidebar_precedence()
  equalize_splits()

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
