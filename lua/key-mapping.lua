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
-- 3-Zone IDE Layout Engine Bridge
-------------------------------------------------------------------------------

local layout = require('utils.layout')

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
  local info = layout.get_win_info(cur_win)

  -- 0. If inside any floating window: close cleanly
  local cfg = vim.api.nvim_win_get_config(cur_win)
  if cfg.relative and cfg.relative ~= '' then
    pcall(vim.api.nvim_win_close, cur_win, true)
    return
  end

  -- 1. If inside Right Panel (Explorer, DBUI, AI): close/hide the Right Panel
  if info.is_explorer or info.is_dbui or info.is_opencode then
    layout.RightPanel.close_all()
    local ed = layout.get_editor_win()
    if ed and vim.api.nvim_win_is_valid(ed) then
      vim.api.nvim_set_current_win(ed)
    end
    return
  end

  -- 2. If inside Bottom Panel (Terminal, SQL Results): terminate terminal or close panel
  if info.is_terminal then
    local is_real_term = (vim.bo[cur_buf].buftype == 'terminal' or vim.bo[cur_buf].filetype == 'snacks_terminal' or vim.bo[cur_buf].filetype == 'terminal' or vim.api.nvim_buf_get_name(cur_buf):match('^term://') ~= nil)

    local cur_term_id = (vim.b[cur_buf].snacks_terminal and vim.b[cur_buf].snacks_terminal.id) or layout.BottomPanel.active_terminal_count or 1

    if is_real_term then
      local job_id = vim.api.nvim_buf_is_valid(cur_buf) and vim.b[cur_buf].terminal_job_id or nil
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
      if vim.api.nvim_win_is_valid(w) and w ~= cur_win and layout.get_win_info(w).is_terminal then
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
      layout.equalize_splits()
    else
      local tracker_ok, tracker = pcall(require, 'utils.terminal-tracker')
      local remaining = {}
      if tracker_ok and tracker.get_terminals then
        tracker.invalidate()
        remaining = tracker.get_terminals()
      end

      if #remaining > 0 then
        local next_id = remaining[1].id
        for _, t in ipairs(remaining) do
          if t.id > cur_term_id then
            next_id = t.id
            break
          end
        end

        layout.BottomPanel.active_terminal_count = next_id
        if vim.api.nvim_win_is_valid(cur_win) then
          pcall(vim.api.nvim_win_close, cur_win, true)
        end
        layout.BottomPanel.open_terminal(next_id)
        return
      else
        layout.BottomPanel.close_all()
        layout.BottomPanel.active_terminal_count = 1
        local ed = layout.get_editor_win()
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
    pcall(vim.api.nvim_win_set_buf, cur_win, next_target)
    local ok, snacks = pcall(require, 'snacks')
    if ok and snacks.bufdelete then
      snacks.bufdelete({ buf = cur_buf })
    else
      pcall(vim.cmd, 'bdelete ' .. cur_buf)
    end
  else
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
  local info = layout.get_win_info()
  if not info.is_editor then
    local ed = layout.get_editor_win()
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
  local info = layout.get_win_info()
  if not info.is_editor then
    local ed = layout.get_editor_win()
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
  local info = layout.get_win_info(cur_win)

  -- 1. In Terminal: switch to terminal instance n directly in terminal mode
  if info.is_terminal then
    layout.BottomPanel.open_terminal(n)
    return
  end

  if vim.api.nvim_get_mode().mode == 't' then
    vim.cmd('stopinsert')
  end

  -- 2. In Right Panel (Explorer, DBUI, AI): return to editor first
  if info.is_explorer or info.is_dbui or info.is_opencode then
    local ed = layout.get_editor_win()
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

vim.keymap.set('n', '<leader>ws', function() layout.editor_split('horizontal') end, { desc = 'Split Horizontally' })
vim.keymap.set('n', '<leader>wv', function() layout.editor_split('vertical') end, { desc = 'Split Vertically' })
vim.keymap.set('n', '<leader>we', layout.reset_window_layout, { desc = 'Balance Window Splits' })
vim.keymap.set('n', '<leader>wq', function() layout.smart_close_window(smart_close) end, { desc = 'Close Window Split' })
vim.keymap.set('n', '<leader>wo', function()
  local ed = layout.get_editor_win()
  if ed and vim.api.nvim_win_is_valid(ed) then
    vim.api.nvim_set_current_win(ed)
    vim.cmd('only')
  end
end, { desc = 'Close Other Splits' })

-------------------------------------------------------------------------------
-- Snacks Dashboard (<leader>d)
-------------------------------------------------------------------------------

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

  layout.cleanup_panels_before_save()
  local real_bufs = layout.get_real_editor_bufs()
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
-- Spatial Navigation Keybindings (<C-h/j/k/l>)
-------------------------------------------------------------------------------

-- <C-l>: Spatial navigation right / Right Panel Toggle
vim.keymap.set({ 'n', 't', 'i' }, '<C-l>', layout.navigate_right, { desc = 'Right / Right Panel' })

-- <C-h>: Spatial navigation left / Return from Right Panel
vim.keymap.set({ 'n', 't', 'i' }, '<C-h>', layout.navigate_left, { desc = 'Left / Editor' })

-- <C-k>: Spatial navigation up / Return from Bottom Panel
vim.keymap.set({ 'n', 't', 'i' }, '<C-k>', layout.navigate_up, { desc = 'Up / Editor' })

-- <C-j>: Spatial navigation down / Focus or Toggle Bottom Output
vim.keymap.set({ 'n', 't', 'i' }, '<C-j>', layout.navigate_down, { desc = 'Down / Bottom Output' })

-- <leader>t: Direct Terminal Toggle & Switch Bottom Mode
vim.keymap.set({ 'n', 't' }, '<leader>t', function()
  local count = vim.v.count > 0 and vim.v.count or nil
  layout.BottomPanel.open_terminal(count)
end, { desc = 'Terminal' })

-------------------------------------------------------------------------------
-- Window Resizing (<M-h/j/k/l> & <C-w>=)
-------------------------------------------------------------------------------

vim.keymap.set('n', '<C-w>=', layout.reset_window_layout, { desc = 'Reset Default Window Layout' })

vim.keymap.set({ 'n', 'i', 't' }, '<M-h>', function() layout.resize_width(-3) end, { desc = 'Resize Width / Expand Explorer' })
vim.keymap.set({ 'n', 'i', 't' }, '<M-l>', function() layout.resize_width(3) end, { desc = 'Resize Width / Shrink Explorer' })
vim.keymap.set({ 'n', 'i', 't' }, '<M-k>', function() layout.resize_height(2) end, { desc = 'Expand Bottom Height +2' })
vim.keymap.set({ 'n', 'i', 't' }, '<M-j>', function() layout.resize_height(-2) end, { desc = 'Shrink Bottom Height -2' })
