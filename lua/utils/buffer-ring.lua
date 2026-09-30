-- lua/utils/buffer-ring.lua
-- Fixed 4-slot LRU buffer ring with non-shifting slots and safe eviction

local M = {}

M.max_slots = 4
M.slots = { nil, nil, nil, nil }
M.access_times = {}
M.pinned = {}

local access_counter = 0
local last_full_warn_time = 0

--- Check if a buffer qualifies to be tracked in the 4-slot ring
---@param buf integer
---@return boolean
function M.is_qualifying(buf)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return false
  end

  local name = vim.api.nvim_buf_get_name(buf)

  -- Preview buffers from database relation viewer are allowed
  if vim.b[buf].is_preview_buffer or name:match('%[Preview: ') then
    return true
  end

  local buftype = vim.bo[buf].buftype
  local filetype = vim.bo[buf].filetype

  -- Only standard file buffers qualify (buftype == '')
  if buftype ~= '' then
    return false
  end

  -- Skip empty unnamed scratchpads without filetype or disk backing
  if name == '' and filetype == '' then
    return false
  end

  -- Blacklisted filetypes: tools, panels, git, terminal
  local excluded = {
    snacks_dashboard = true,
    snacks_terminal = true,
    snacks_picker_input = true,
    TelescopePrompt = true,
    neo_tree = true,
    qf = true,
    help = true,
    notify = true,
    toggleterm = true,
    sqmeow = true,
    dbout = true,
    dbui = true,
    gitcommit = true,
    gitrebase = true,
  }
  if excluded[filetype] then
    return false
  end

  -- Pattern checks for Git and external tools
  if filetype:match('^Neogit') or filetype:match('^Diffview') or filetype:match('^fugitive') then
    return false
  end

  if name:match('^fugitive://') or name:match('^diffview://') or name:match('^term://') or name:match('^octo://') then
    return false
  end

  return true
end

--- Clean up any invalid or closed buffers from slots
function M.clean_slots()
  for i = 1, M.max_slots do
    local b = M.slots[i]
    if b and (not vim.api.nvim_buf_is_valid(b) or not M.is_qualifying(b)) then
      M.slots[i] = nil
      M.access_times[b] = nil
      M.pinned[b] = nil
    end
  end
end

--- Find the slot index (1..4) of a given buffer, if present
---@param buf integer
---@return integer|nil
function M.find_slot(buf)
  for i = 1, M.max_slots do
    if M.slots[i] == buf then
      return i
    end
  end
  return nil
end

--- Update access timestamp for LRU ordering
---@param buf integer
function M.touch(buf)
  access_counter = access_counter + 1
  M.access_times[buf] = access_counter
end

--- Handle buffer entry: assign to vacant slot or evict oldest LRU saved buffer
---@param buf? integer
function M.on_buf_enter(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  if not M.is_qualifying(buf) then
    return
  end

  M.clean_slots()
  M.touch(buf)

  -- Already tracked in a fixed slot? Nothing to allocate
  local existing_slot = M.find_slot(buf)
  if existing_slot then
    return
  end

  -- 1. Check for the lowest available vacant slot (1..4)
  for i = 1, M.max_slots do
    if M.slots[i] == nil then
      M.slots[i] = buf
      return
    end
  end

  -- 2. All 4 slots are occupied: find LRU candidate to evict
  -- Candidate must NOT be pinned, must NOT be current buffer, and must NOT be modified
  local lru_slot = nil
  local oldest_time = math.huge

  for i = 1, M.max_slots do
    local b = M.slots[i]
    if b and b ~= buf and not M.pinned[b] then
      -- Option A: Skip modified buffers to guarantee zero data loss
      if not vim.bo[b].modified then
        local t = M.access_times[b] or 0
        if t < oldest_time then
          oldest_time = t
          lru_slot = i
        end
      end
    end
  end

  if lru_slot then
    local victim = M.slots[lru_slot]
    -- Put new buffer in that exact fixed slot
    M.slots[lru_slot] = buf
    M.access_times[victim] = nil
    M.pinned[victim] = nil

    -- Safely close the evicted buffer without disturbing window splits
    vim.schedule(function()
      if victim and vim.api.nvim_buf_is_valid(victim) and not vim.bo[victim].modified then
        local ok, snacks = pcall(require, 'snacks')
        if ok and snacks.bufdelete then
          snacks.bufdelete({ buf = victim })
        else
          pcall(vim.api.nvim_buf_delete, victim, { unload = false })
        end
      end
    end)
  else
    -- All 4 slots are modified/pinned!
    local now = vim.uv and vim.uv.now() or os.time()
    if (now - last_full_warn_time) > 5000 then
      last_full_warn_time = now
      vim.notify(
        'Buffer ring full (all slots unsaved or pinned). Save a file (:w) to allow auto-eviction.',
        vim.log.levels.WARN,
        { title = 'Buffer Ring' }
      )
    end
  end
end

--- Remove buffer from tracking when closed
---@param buf integer
function M.on_buf_delete(buf)
  local slot = M.find_slot(buf)
  if slot then
    M.slots[slot] = nil
    M.access_times[buf] = nil
    M.pinned[buf] = nil
  end
end

--- Find an appropriate editor window that can accept buffer changes
---@return integer win The window ID
local function get_target_window()
  local cur_win = vim.api.nvim_get_current_win()

  -- Check if a window is an ordinary editor window (not a sidebar, drawer, bottom panel, or terminal)
  local function is_editor_win(w)
    if not w or not vim.api.nvim_win_is_valid(w) then return false end
    if vim.api.nvim_win_get_tabpage(w) ~= vim.api.nvim_get_current_tabpage() then return false end
    if vim.api.nvim_win_get_config(w).relative ~= '' then return false end
    local b = vim.api.nvim_win_get_buf(w)
    local ft = vim.bo[b].filetype
    local bname = vim.api.nvim_buf_get_name(b):lower()
    if ft:match('^sqmeow%-') or ft == 'sqmeow' or ft == 'dbui' or ft == 'dbout'
       or ft:match('opencode') or bname:find('opencode')
       or ft:match('terminal') or bname:find('term://')
       or ft:match('^snacks_') or ft == 'neo-tree' or ft == 'qf' then
      return false
    end
    return true
  end

  -- 1. If the current window is an editor window, use it
  if is_editor_win(cur_win) then
    if vim.fn.exists('&winfixbuf') == 1 and vim.wo[cur_win].winfixbuf then
      vim.wo[cur_win].winfixbuf = false
    end
    return cur_win
  end

  -- 2. Otherwise search for another open editor window
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if w ~= cur_win and is_editor_win(w) then
      if vim.fn.exists('&winfixbuf') == 1 and vim.wo[w].winfixbuf then
        vim.wo[w].winfixbuf = false
      end
      return w
    end
  end

  -- 3. If no editor window found, search for any window without winfixbuf
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_config(w).relative == '' then
      if vim.fn.exists('&winfixbuf') == 0 or not vim.wo[w].winfixbuf then
        return w
      end
    end
  end

  -- 4. Fallback: create a new editor split beside the current window
  vim.cmd('botright vnew')
  local new_win = vim.api.nvim_get_current_win()
  if vim.fn.exists('&winfixbuf') == 1 then
    vim.wo[new_win].winfixbuf = false
  end
  return new_win
end

--- Safely switch to a buffer, handling windows with winfixbuf enabled
---@param target integer
local function switch_to_buf(target)
  if not target or not vim.api.nvim_buf_is_valid(target) then
    return
  end

  -- If target is already visible in an editor window in current tab, simply focus it
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_is_valid(w) and vim.api.nvim_win_get_buf(w) == target then
      vim.api.nvim_set_current_win(w)
      return
    end
  end

  local win = get_target_window()
  if win and vim.api.nvim_win_is_valid(win) then
    if vim.fn.exists('&winfixbuf') == 1 and vim.wo[win].winfixbuf then
      vim.wo[win].winfixbuf = false
    end
    vim.api.nvim_set_current_win(win)
    pcall(vim.api.nvim_win_set_buf, win, target)
  else
    pcall(vim.api.nvim_set_current_buf, target)
  end
end

--- Jump directly to a fixed slot (1..4)
---@param slot integer
function M.jump(slot)
  M.clean_slots()
  local target = M.slots[slot]
  if target and vim.api.nvim_buf_is_valid(target) then
    switch_to_buf(target)
  else
    vim.notify('Slot ' .. slot .. ' is empty', vim.log.levels.INFO, { title = 'Buffer Ring' })
  end
end

--- Cycle to the next occupied slot in the ring
function M.next_buffer()
  M.clean_slots()
  local cur = vim.api.nvim_get_current_buf()
  local cur_slot = M.find_slot(cur) or 0
  for offset = 1, M.max_slots do
    local idx = ((cur_slot - 1 + offset) % M.max_slots) + 1
    local target = M.slots[idx]
    if target and target ~= cur and vim.api.nvim_buf_is_valid(target) then
      switch_to_buf(target)
      return
    end
  end
end

--- Cycle to the previous occupied slot in the ring
function M.prev_buffer()
  M.clean_slots()
  local cur = vim.api.nvim_get_current_buf()
  local cur_slot = M.find_slot(cur) or 1
  for offset = 1, M.max_slots do
    local idx = ((cur_slot - 1 - offset) % M.max_slots) + 1
    local target = M.slots[idx]
    if target and target ~= cur and vim.api.nvim_buf_is_valid(target) then
      switch_to_buf(target)
      return
    end
  end
end

--- Count how many buffers are currently pinned in the ring
---@return integer
function M.pinned_count()
  local count = 0
  for b, is_p in pairs(M.pinned) do
    if is_p and vim.api.nvim_buf_is_valid(b) and M.find_slot(b) ~= nil then
      count = count + 1
    end
  end
  return count
end

--- Toggle pin status for a buffer (maximum 3 buffers can be pinned)
---@param buf? integer
function M.toggle_pin(buf)
  M.clean_slots()
  buf = buf or vim.api.nvim_get_current_buf()

  -- If focused in a tool/panel (e.g. terminal, drawer, explorer), target the active editor window's buffer
  if not M.is_qualifying(buf) or M.find_slot(buf) == nil then
    local cur_win = vim.api.nvim_get_current_win()
    for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if w ~= cur_win and vim.api.nvim_win_is_valid(w) then
        local b = vim.api.nvim_win_get_buf(w)
        if M.is_qualifying(b) and M.find_slot(b) ~= nil then
          buf = b
          break
        end
      end
    end
  end

  if not M.is_qualifying(buf) then
    vim.notify('Cannot pin non-editor buffer', vim.log.levels.WARN, { title = 'Buffer Ring' })
    return
  end

  local slot = M.find_slot(buf)
  if not slot then
    M.on_buf_enter(buf)
    slot = M.find_slot(buf)
    if not slot then
      vim.notify('Buffer is not in an active slot', vim.log.levels.WARN, { title = 'Buffer Ring' })
      return
    end
  end

  local raw = vim.api.nvim_buf_get_name(buf)
  local name = vim.fs.basename(raw)
  if vim.b[buf].is_preview_buffer or raw:match('%[Preview: ') then
    local tbl = raw:match('%[Preview: (.-)%]')
    name = tbl and ('Preview: ' .. tbl) or 'Preview'
  elseif name == '' then
    name = '[No Name]'
  end

  if M.pinned[buf] then
    M.pinned[buf] = nil
    vim.notify(string.format('Slot %d unpinned (%s)', slot, name), vim.log.levels.INFO, { title = 'Buffer Ring' })
  else
    if M.pinned_count() >= 3 then
      vim.notify('Maximum 3 pinned buffers reached. Unpin one to pin another.', vim.log.levels.WARN, { title = 'Buffer Ring' })
      return
    end
    M.pinned[buf] = true
    vim.notify(string.format('Slot %d pinned (%s) 󰐃', slot, name), vim.log.levels.INFO, { title = 'Buffer Ring' })
  end

  pcall(function() require('lualine').refresh() end)
end

--- Check if buffer is pinned
---@param buf integer
---@return boolean
function M.is_pinned(buf)
  return M.pinned[buf] == true
end

--- Format the 4-slot ring for Lualine
---@return string
function M.lualine_component()
  M.clean_slots()
  local cur_buf = vim.api.nvim_get_current_buf()
  local items = {}
  local ok_devicons, devicons = pcall(require, 'nvim-web-devicons')

  for i = 1, M.max_slots do
    local b = M.slots[i]
    if b and vim.api.nvim_buf_is_valid(b) then
      local is_active = (b == cur_buf)
      local raw = vim.api.nvim_buf_get_name(b)
      local name = vim.fs.basename(raw)
      local ft_icon = '󰈔 '

      if vim.b[b].is_preview_buffer or raw:match('%[Preview: ') then
        local tbl = raw:match('%[Preview: (.-)%]')
        name = tbl and tbl or 'preview'
        ft_icon = '󰆼 '
      elseif name == '' then
        name = '[No Name]'
      else
        if ok_devicons and devicons.get_icon then
          local ext = vim.fn.fnamemodify(raw, ':e')
          local icon = devicons.get_icon(name, ext, { default = true })
          if icon then
            ft_icon = icon .. ' '
          end
        end
      end

      local modified = vim.bo[b].modified and ' ●' or ''
      local pin = M.pinned[b] and '󰐃 ' or ''

      -- Style active vs inactive slots (clean highlight badge without extra separators)
      if is_active then
        table.insert(items, string.format('%%#lualine_a_normal# %d %s%s%s%s %%*', i, pin, ft_icon, name, modified))
      else
        table.insert(items, string.format('%%#lualine_c_normal# %d %s%s%s%s %%*', i, pin, ft_icon, name, modified))
      end
    else
      -- Vacant slot indicator
      table.insert(items, string.format('%%#Comment# %d ··· %%*', i))
    end
  end

  return table.concat(items, '')
end

--- Setup autocommands for automatic slot management
function M.setup()
  local group = vim.api.nvim_create_augroup('UserBufferRing', { clear = true })

  vim.api.nvim_create_autocmd({ 'BufEnter', 'BufWinEnter' }, {
    group = group,
    callback = function(args)
      M.on_buf_enter(args.buf)
    end,
  })

  vim.api.nvim_create_autocmd({ 'BufDelete', 'BufWipeout' }, {
    group = group,
    callback = function(args)
      M.on_buf_delete(args.buf)
    end,
  })

  -- Seed slots with any qualifying buffers already open
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(b) and M.is_qualifying(b) then
      M.on_buf_enter(b)
    end
  end
end

return M
