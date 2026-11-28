-- lua/utils/jira-local.lua
-- Global personal local tickets (LOCAL-1, LOCAL-2, ...) merged into Jira "My Tasks"
-- with full parity: status transitions, creation age, Markdown description, and comments.

local M = {}

M.DATA_FILE = vim.fn.stdpath('data') .. '/jira-local.json'
M.STATUSES = { 'To Do', 'In Progress', 'Blocked', 'Done' }
M.PRIORITIES = { 'Medium', 'High', 'Highest', 'Low' }
M.TYPES = { 'Task', 'Bug', 'Story' }

local function load_store()
  if vim.fn.filereadable(M.DATA_FILE) == 0 then
    return { next_id = 1, tickets = {} }
  end
  local ok, lines = pcall(vim.fn.readfile, M.DATA_FILE)
  if not ok or not lines or #lines == 0 then
    return { next_id = 1, tickets = {} }
  end
  local ok_json, data = pcall(vim.json.decode, table.concat(lines, '\n'))
  if not ok_json or type(data) ~= 'table' then
    return { next_id = 1, tickets = {} }
  end
  data.next_id = tonumber(data.next_id) or 1
  data.tickets = type(data.tickets) == 'table' and data.tickets or {}
  return data
end

local function save_store(data)
  local dir = vim.fn.fnamemodify(M.DATA_FILE, ':h')
  if vim.fn.isdirectory(dir) == 0 then
    vim.fn.mkdir(dir, 'p')
  end
  vim.fn.writefile({ vim.json.encode(data) }, M.DATA_FILE)
end

function M.is_local_key(key)
  return type(key) == 'string' and key:match('^LOCAL%-%d+$') ~= nil
end

function M.list_active()
  local data = load_store()
  local active = {}
  for _, t in ipairs(data.tickets) do
    if t.status ~= 'Done' then
      table.insert(active, {
        key = t.key,
        summary = t.summary or '',
        status = t.status or 'To Do',
        priority = t.priority or 'Medium',
        assignee = 'Me',
        type = t.type or 'Task',
        created = t.created,
        is_local = true,
        children = {},
        expanded = true,
      })
    end
  end
  return active
end

function M.get(key)
  local data = load_store()
  for _, t in ipairs(data.tickets) do
    if t.key == key then
      return t
    end
  end
  return nil
end

function M.create(summary, opts)
  opts = opts or {}
  local data = load_store()
  local key = 'LOCAL-' .. tostring(data.next_id)
  data.next_id = data.next_id + 1
  local ticket = {
    key = key,
    summary = vim.trim(summary or ''),
    description = opts.description or '',
    status = opts.status or 'To Do',
    priority = opts.priority or 'Medium',
    type = opts.type or 'Task',
    assignee = 'Me',
    created = os.date('!%Y-%m-%dT%H:%M:%SZ'),
    comments = {},
  }
  table.insert(data.tickets, 1, ticket)
  save_store(data)
  return ticket
end

function M.update(key, patch)
  local data = load_store()
  for _, t in ipairs(data.tickets) do
    if t.key == key then
      for k, v in pairs(patch) do
        t[k] = v
      end
      save_store(data)
      return t
    end
  end
  return nil
end

function M.set_status(key, status)
  return M.update(key, { status = status })
end

function M.add_comment(key, body)
  local data = load_store()
  for _, t in ipairs(data.tickets) do
    if t.key == key then
      t.comments = type(t.comments) == 'table' and t.comments or {}
      table.insert(t.comments, {
        id = tostring(os.time()) .. '-' .. tostring(#t.comments + 1),
        author = 'Me',
        created = os.date('!%Y-%m-%dT%H:%M:%SZ'),
        body = body,
      })
      save_store(data)
      return t
    end
  end
  return nil
end

function M.edit_comment(key, comment_id, body)
  local data = load_store()
  for _, t in ipairs(data.tickets) do
    if t.key == key then
      for _, c in ipairs(t.comments or {}) do
        if c.id == comment_id then
          c.body = body
          c.updated = os.date('!%Y-%m-%dT%H:%M:%SZ')
          save_store(data)
          return t
        end
      end
    end
  end
  return nil
end

function M.delete(key)
  local data = load_store()
  for i, t in ipairs(data.tickets) do
    if t.key == key then
      table.remove(data.tickets, i)
      save_store(data)
      return true
    end
  end
  return false
end

function M.prompt_create(on_created)
  vim.ui.input({ prompt = 'New Local Ticket Summary: ' }, function(summary)
    if not summary or vim.trim(summary) == '' then
      return
    end
    vim.ui.select(M.PRIORITIES, { prompt = 'Priority:' }, function(priority)
      if not priority then
        return
      end
      vim.ui.select(M.TYPES, { prompt = 'Type:' }, function(ttype)
        if not ttype then
          return
        end
        local ticket = M.create(summary, { priority = priority, type = ttype })
        vim.notify('Created local ticket ' .. ticket.key, vim.log.levels.INFO, { title = 'Jira Local' })
        if on_created then
          on_created(ticket)
        end
      end)
    end)
  end)
end

function M.prompt_status(key, on_updated)
  vim.ui.select(M.STATUSES, { prompt = 'Select Status for ' .. key .. ':' }, function(choice)
    if not choice then
      return
    end
    M.set_status(key, choice)
    vim.notify('Updated ' .. key .. ' to ' .. choice, vim.log.levels.INFO, { title = 'Jira Local' })
    if on_updated then
      on_updated(choice)
    end
  end)
end

function M.prompt_delete(key, on_deleted)
  vim.ui.select({ 'No', 'Yes' }, { prompt = 'Delete local ticket ' .. key .. '?' }, function(choice)
    if choice ~= 'Yes' then
      return
    end
    if M.delete(key) then
      vim.notify('Deleted local ticket ' .. key, vim.log.levels.INFO, { title = 'Jira Local' })
      if on_deleted then
        on_deleted()
      end
    end
  end)
end

local function open_comment_popup(title, initial_text, on_submit)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].filetype = 'markdown'
  vim.bo[buf].bufhidden = 'wipe'
  if initial_text and initial_text ~= '' then
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(initial_text, '\n', { plain = true }))
  end

  local width = math.min(80, math.floor(vim.o.columns * 0.6))
  local height = 10
  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = 'minimal',
    border = 'rounded',
    title = ' ' .. title .. ' (<C-s> to save, <Esc> to cancel) ',
    title_pos = 'center',
  })
  vim.wo[win].wrap = true
  vim.cmd('startinsert')

  local function close()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end

  vim.keymap.set({ 'n', 'i' }, '<C-s>', function()
    vim.cmd('stopinsert')
    local text = vim.trim(table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n'))
    close()
    if text ~= '' then
      on_submit(text)
    end
  end, { buffer = buf, silent = true, desc = 'Save comment' })

  vim.keymap.set('n', '<Esc>', close, { buffer = buf, silent = true, desc = 'Cancel comment' })
  vim.keymap.set('n', 'q', close, { buffer = buf, silent = true, desc = 'Cancel comment' })
end

--- Open a local ticket Markdown editor in-place inside `target_win`
function M.open_editor(key, target_win, opts)
  opts = opts or {}
  local ticket = M.get(key)
  if not ticket then
    vim.notify('Local ticket not found: ' .. tostring(key), vim.log.levels.ERROR)
    return
  end

  local buf_name = 'Jira Edit: ' .. ticket.key
  local existing = vim.fn.bufnr('^' .. vim.pesc(buf_name) .. '$')
  if existing ~= -1 and vim.api.nvim_buf_is_valid(existing) then
    pcall(vim.api.nvim_buf_delete, existing, { force = true })
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].filetype = 'markdown'
  vim.bo[buf].buftype = 'acwrite'
  vim.bo[buf].bufhidden = 'hide'
  vim.b[buf].panel_zone = 'right'
  vim.b[buf].panel_type = 'jira'
  vim.api.nvim_buf_set_name(buf, buf_name)

  local lines = {
    'Summary: ' .. (ticket.summary or ''),
    'Status: ' .. (ticket.status or 'To Do'),
    'Priority: ' .. (ticket.priority or 'Medium'),
    'Type: ' .. (ticket.type or 'Task'),
    '',
    '## Description',
    '',
  }
  if ticket.description and ticket.description ~= '' then
    for _, l in ipairs(vim.split(ticket.description, '\n', { plain = true })) do
      table.insert(lines, l)
    end
  end

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modified = false

  if target_win and vim.api.nvim_win_is_valid(target_win) then
    vim.wo[target_win].winfixbuf = false
    vim.api.nvim_win_set_buf(target_win, buf)
    vim.api.nvim_set_current_win(target_win)
    if opts.style_win then
      opts.style_win(target_win, false)
    end
  end

  local write_group = vim.api.nvim_create_augroup('UserJiraLocalWrite', { clear = false })
  pcall(vim.api.nvim_clear_autocmds, { group = write_group, buffer = buf })
  vim.api.nvim_create_autocmd('BufWriteCmd', {
    group = write_group,
    buffer = buf,
    callback = function()
      local cur_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      local patch = {}
      local desc_lines = {}
      local in_desc = false
      for _, line in ipairs(cur_lines) do
        if in_desc then
          table.insert(desc_lines, line)
        elseif line:match('^##%s*Description') then
          in_desc = true
        elseif line:match('^Summary:%s*') then
          patch.summary = vim.trim(line:gsub('^Summary:%s*', ''))
        elseif line:match('^Status:%s*') then
          patch.status = vim.trim(line:gsub('^Status:%s*', ''))
        elseif line:match('^Priority:%s*') then
          patch.priority = vim.trim(line:gsub('^Priority:%s*', ''))
        elseif line:match('^Type:%s*') then
          patch.type = vim.trim(line:gsub('^Type:%s*', ''))
        end
      end
      patch.description = vim.trim(table.concat(desc_lines, '\n'))
      M.update(ticket.key, patch)
      vim.bo[buf].modified = false
      vim.notify('Saved local ticket ' .. ticket.key .. ' ✓', vim.log.levels.INFO, { title = 'Jira Local' })
      if opts.on_change then
        opts.on_change()
      end
    end,
  })

  vim.keymap.set('n', 'q', function()
    if opts.on_close then
      opts.on_close(buf)
    end
  end, { buffer = buf, silent = true, nowait = true, desc = 'Jira Local: Close editor' })

  return buf
end

--- Open a local ticket viewer (Description / Comments / Help / S to change status) in-place inside `target_win`
function M.open_viewer(key, target_win, opts)
  opts = opts or {}
  local ticket = M.get(key)
  if not ticket then
    vim.notify('Local ticket not found: ' .. tostring(key), vim.log.levels.ERROR)
    return
  end

  local buf_name = 'Jira: ' .. ticket.key
  local existing = vim.fn.bufnr('^' .. vim.pesc(buf_name) .. '$')
  if existing ~= -1 and vim.api.nvim_buf_is_valid(existing) then
    pcall(vim.api.nvim_buf_delete, existing, { force = true })
  end

  local buf = vim.api.nvim_create_buf(false, true)
  local ns = vim.api.nvim_create_namespace('JiraLocalViewer')
  vim.bo[buf].filetype = 'markdown'
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'hide'
  vim.b[buf].panel_zone = 'right'
  vim.b[buf].panel_type = 'jira'
  vim.api.nvim_buf_set_name(buf, buf_name)

  local active_tab = 'description'
  local comment_ranges = {}

  local function render()
    if not vim.api.nvim_buf_is_valid(buf) then
      return
    end
    ticket = M.get(key) or ticket
    comment_ranges = {}

    local tabs = {
      { name = 'Description (D)', id = 'description' },
      { name = 'Comments (C)', id = 'comments' },
      { name = 'Help (H)', id = 'help' },
    }
    local header = '  '
    local hls = {}
    for _, tb in ipairs(tabs) do
      local s = ' ' .. tb.name .. ' '
      local sc = #header
      header = header .. s .. '  '
      table.insert(hls, {
        row = 0,
        start_col = sc,
        end_col = sc + #s,
        hl = (active_tab == tb.id) and 'JiraTabActive' or 'JiraTabInactive',
      })
    end

    local lines = { header, '' }
    if active_tab == 'description' then
      table.insert(lines, '# ' .. ticket.key .. ': ' .. (ticket.summary or ''))
      table.insert(lines, '')
      table.insert(lines, '**Type**: ' .. (ticket.type or 'Task') .. ' (Local)')
      table.insert(lines, '**Status**: ' .. (ticket.status or 'To Do'))
      table.insert(lines, '**Priority**: ' .. (ticket.priority or 'Medium'))
      table.insert(lines, '**Created**: ' .. (ticket.created or 'Unknown'))
      table.insert(lines, '')
      table.insert(lines, '## Description')
      table.insert(lines, '')
      if ticket.description and ticket.description ~= '' then
        for _, l in ipairs(vim.split(ticket.description, '\n', { plain = true })) do
          table.insert(lines, l)
        end
      else
        table.insert(lines, '_No description — press `i` to edit._')
      end
    elseif active_tab == 'comments' then
      local comments = ticket.comments or {}
      if #comments == 0 then
        table.insert(lines, '_No comments yet._')
        table.insert(lines, '')
        table.insert(lines, "Press 'i' to add a comment.")
      else
        for idx, c in ipairs(comments) do
          if idx > 1 then
            table.insert(lines, '')
            table.insert(lines, '---')
            table.insert(lines, '')
          end
          local start_line = #lines
          table.insert(lines, string.format('**%s** · _%s_', c.author or 'Me', c.created or ''))
          table.insert(lines, '')
          for _, l in ipairs(vim.split(c.body or '', '\n', { plain = true })) do
            table.insert(lines, l)
          end
          table.insert(comment_ranges, {
            id = c.id,
            start_line = start_line,
            end_line = #lines - 1,
            comment = c,
          })
        end
      end
    else
      table.insert(lines, '## Local Ticket Keymaps')
      table.insert(lines, '')
      table.insert(lines, '- `<Tab>` : Switch tabs (Description / Comments / Help)')
      table.insert(lines, '- `D` / `C` / `H` : Jump to Description / Comments / Help')
      table.insert(lines, '- `S` : Change status (To Do / In Progress / Blocked / Done)')
      table.insert(lines, '- `i` : Edit ticket (on Description) or Add comment (on Comments)')
      table.insert(lines, '- `r` : Edit comment under cursor (on Comments)')
      table.insert(lines, '- `X` : Delete local ticket')
      table.insert(lines, '- `q` / `h` : Back to My Tasks')
    end

    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false

    for _, h in ipairs(hls) do
      pcall(vim.api.nvim_buf_set_extmark, buf, ns, h.row, h.start_col, {
        end_col = h.end_col,
        hl_group = h.hl,
      })
    end
  end

  if target_win and vim.api.nvim_win_is_valid(target_win) then
    vim.wo[target_win].winfixbuf = false
    vim.api.nvim_win_set_buf(target_win, buf)
    vim.api.nvim_set_current_win(target_win)
    if opts.style_win then
      opts.style_win(target_win, false)
    end
  end

  render()

  local map = function(lhs, fn, desc)
    vim.keymap.set('n', lhs, fn, { buffer = buf, silent = true, nowait = true, desc = 'Jira Local: ' .. desc })
  end

  map('<Tab>', function()
    local next_tab = { description = 'comments', comments = 'help', help = 'description' }
    active_tab = next_tab[active_tab] or 'description'
    render()
  end, 'Switch tabs')
  map('D', function()
    active_tab = 'description'
    render()
  end, 'Description tab')
  map('C', function()
    active_tab = 'comments'
    render()
  end, 'Comments tab')
  map('H', function()
    active_tab = 'help'
    render()
  end, 'Help tab')
  map('S', function()
    M.prompt_status(key, function()
      render()
      if opts.on_change then
        opts.on_change()
      end
    end)
  end, 'Change status')
  map('i', function()
    if active_tab == 'description' then
      M.open_editor(key, target_win, {
        style_win = opts.style_win,
        on_change = function()
          if opts.on_change then
            opts.on_change()
          end
        end,
        on_close = function(ebuf)
          if target_win and vim.api.nvim_win_is_valid(target_win) and vim.api.nvim_buf_is_valid(buf) then
            vim.wo[target_win].winfixbuf = false
            vim.api.nvim_win_set_buf(target_win, buf)
            vim.api.nvim_set_current_win(target_win)
            if opts.style_win then
              opts.style_win(target_win, false)
            end
            render()
          end
          if ebuf and vim.api.nvim_buf_is_valid(ebuf) then
            pcall(vim.api.nvim_buf_delete, ebuf, { force = true })
          end
        end,
      })
    elseif active_tab == 'comments' then
      open_comment_popup('Add Comment to ' .. key, '', function(text)
        M.add_comment(key, text)
        render()
      end)
    end
  end, 'Edit / Add comment')
  map('r', function()
    if active_tab ~= 'comments' or not (target_win and vim.api.nvim_win_is_valid(target_win)) then
      return
    end
    local row = vim.api.nvim_win_get_cursor(target_win)[1] - 1
    local target_c = nil
    for _, r in ipairs(comment_ranges) do
      if row >= r.start_line and row <= r.end_line then
        target_c = r.comment
        break
      end
    end
    if not target_c then
      vim.notify('Place cursor on a comment to edit it', vim.log.levels.WARN)
      return
    end
    open_comment_popup('Edit Comment on ' .. key, target_c.body or '', function(text)
      M.edit_comment(key, target_c.id, text)
      render()
    end)
  end, 'Edit comment')
  map('X', function()
    M.prompt_delete(key, function()
      if opts.on_change then
        opts.on_change()
      end
      if opts.on_close then
        opts.on_close(buf)
      end
    end)
  end, 'Delete local ticket')
  map('q', function()
    if opts.on_close then
      opts.on_close(buf)
    end
  end, 'Back to board')
  map('h', function()
    if opts.on_close then
      opts.on_close(buf)
    end
  end, 'Back to board')

  return buf
end

return M
