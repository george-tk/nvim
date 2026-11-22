-- lua/utils/jira-picker.lua
-- Multi-project discovery, state management, and Snacks.picker integration for letieu/jira.nvim

local M = {}

M.STATE_FILE = vim.fn.stdpath('state') .. '/jira_active_projects.json'
M.CACHE_FILE = vim.fn.stdpath('state') .. '/jira_projects_cache.json'
M.BOARD_ID = 112
M.AGILE_BOARD_JQL = 'AGILE:BOARD:' .. M.BOARD_ID
M.AGILE_BACKLOG_JQL = 'AGILE:BACKLOG:' .. M.BOARD_ID
M.COMPLETED_WINDOW_DAYS = 14
M.BOARD_STATUS_ORDER = {
  ['Kanban: 28Oct-9Dec'] = 1,
  ['To Do'] = 2,
  ['In Progress'] = 3,
  ['Review'] = 4,
  ['Confirm working in PRD'] = 5,
  ['Done'] = 6,
  ['Closed'] = 7,
}

local cached_active_projects = nil

--- Load active project keys from state file
---@return string[]
function M.get_active_projects()
  if cached_active_projects then
    return cached_active_projects
  end

  if vim.fn.filereadable(M.STATE_FILE) == 1 then
    local f = io.open(M.STATE_FILE, 'r')
    if f then
      local content = f:read('*a')
      f:close()
      local ok, data = pcall(vim.json.decode, content)
      if ok and type(data) == 'table' then
        cached_active_projects = data
        return data
      end
    end
  end

  cached_active_projects = {}
  return cached_active_projects
end

--- Save active project keys to state file
---@param keys string[]
function M.set_active_projects(keys)
  cached_active_projects = keys
  local dir = vim.fn.fnamemodify(M.STATE_FILE, ':h')
  if vim.fn.isdirectory(dir) == 0 then
    vim.fn.mkdir(dir, 'p')
  end

  local f = io.open(M.STATE_FILE, 'w')
  if f then
    f:write(vim.json.encode(keys))
    f:close()
  end
end

--- Resolve HTTP headers for Jira REST API using jira.nvim auth
---@return table|nil headers, string|nil base_url, string|nil err
local function get_request_headers()
  local ok_auth, auth_mod = pcall(require, 'jira.common.auth')
  if not ok_auth then
    return nil, nil, 'jira.nvim is not loaded'
  end

  local auth = auth_mod.get_auth()
  local base = (auth.base or ''):gsub('/+$', '')
  if base == '' then
    return nil, nil, 'Missing Jira base URL. Please run :Jira auth login'
  end

  local headers = {
    '-H', 'Accept: application/json',
    '-H', 'Content-Type: application/json',
  }

  local is_bearer = auth_mod.is_bearer(auth.type)
  if is_bearer then
    if not auth.token or auth.token == '' then
      return nil, nil, 'Missing Jira token. Please run :Jira auth login'
    end
    table.insert(headers, '-H')
    table.insert(headers, 'Authorization: Bearer ' .. auth.token)
  else
    if not auth.email or auth.email == '' or not auth.token or auth.token == '' then
      return nil, nil, 'Missing Jira email or API token. Please run :Jira auth login'
    end
    local encoded = vim.base64.encode(auth.email .. ':' .. auth.token)
    table.insert(headers, '-H')
    table.insert(headers, 'Authorization: Basic ' .. encoded)
  end

  return headers, base, nil
end

local function non_nil(value)
  if value == vim.NIL or type(value) == 'userdata' then
    return nil
  end
  return value
end

local function parse_jira_time(value)
  value = non_nil(value)
  if not value or value == '' then
    return nil
  end

  local year, month, day, hour, minute, second = value:match('^(%d+)%-(%d+)%-(%d+)T(%d+):(%d+):(%d+)')
  local sign, offset_hour, offset_minute = value:match('([+-])(%d%d):?(%d%d)$')
  if not year or not sign then
    return nil
  end

  local epoch = os.time({
    year = tonumber(year),
    month = tonumber(month),
    day = tonumber(day),
    hour = tonumber(hour),
    min = tonumber(minute),
    sec = tonumber(second),
  })
  local offset = tonumber(offset_hour) * 3600 + tonumber(offset_minute) * 60
  if sign == '-' then
    return epoch + offset
  end
  return epoch - offset
end

local function status_name(issue)
  local f = non_nil(issue.fields) or {}
  local status = non_nil(f.status)
  return (status and non_nil(status.name)) or 'Unknown'
end

local function status_category(issue)
  local f = non_nil(issue.fields) or {}
  local status = non_nil(f.status)
  local category = status and non_nil(status.statusCategory)
  return (category and non_nil(category.name)) or ''
end

local function issue_type_name(issue)
  local f = non_nil(issue.fields) or {}
  local issue_type = non_nil(f.issuetype)
  return (issue_type and non_nil(issue_type.name)) or ''
end

local function is_recent_completed(issue)
  if status_category(issue) ~= 'Done' then
    return true
  end

  local f = non_nil(issue.fields) or {}
  local latest = 0
  for _, key in ipairs({ 'statuscategorychangedate', 'resolutiondate', 'updated' }) do
    local timestamp = parse_jira_time(f[key])
    if timestamp and timestamp > latest then
      latest = timestamp
    end
  end

  return latest >= os.time() - (M.COMPLETED_WINDOW_DAYS * 24 * 60 * 60)
end

local function filter_work_issues(issues)
  local filtered = {}
  for _, issue in ipairs(issues) do
    local issue_type = issue_type_name(issue)
    if issue_type ~= 'Epic' and issue_type ~= 'Subtask' and is_recent_completed(issue) then
      table.insert(filtered, issue)
    end
  end
  return filtered
end

local function priority_rank(priority)
  local p = (priority or ''):lower()
  if p == 'highest' then return 1 end
  if p == 'high' then return 2 end
  if p == 'medium' then return 3 end
  if p == 'low' then return 4 end
  if p == 'lowest' then return 5 end
  return 6
end

local function status_rank(status)
  return M.BOARD_STATUS_ORDER[status or ''] or 99
end

local function request_agile_page(base, headers, endpoint, start_at, callback)
  local fields = 'summary,status,assignee,priority,parent,issuetype,labels,created,updated,statuscategorychangedate,resolutiondate,timespent,timeoriginalestimate'
  local url = base .. endpoint .. '?startAt=' .. start_at .. '&maxResults=100&fields=' .. fields
  local cmd = { 'curl', '-s', '-L', '--max-time', '10' }
  for _, h in ipairs(headers) do
    table.insert(cmd, h)
  end
  table.insert(cmd, url)

  vim.system(cmd, { text = true }, function(obj)
    vim.schedule(function()
      if obj.code ~= 0 or not obj.stdout or obj.stdout == '' then
        callback(nil, 'Failed to fetch Jira Agile issues (curl exit ' .. tostring(obj.code) .. ')')
        return
      end

      local ok, data = pcall(vim.json.decode, obj.stdout)
      if not ok or type(data) ~= 'table' then
        callback(nil, 'Invalid JSON response from Jira Agile endpoint')
        return
      end

      if data.errorMessages and #data.errorMessages > 0 then
        callback(nil, table.concat(data.errorMessages, '\n'))
        return
      end

      callback(data, nil)
    end)
  end)
end

local function agile_endpoint(kind)
  if kind == 'backlog' then
    return '/rest/agile/1.0/board/' .. M.BOARD_ID .. '/backlog'
  end
  return '/rest/agile/1.0/board/' .. M.BOARD_ID .. '/issue'
end

local function fetch_endpoint(base, headers, endpoint, callback)
  local all = {}
  local function fetch_page(start_at)
    request_agile_page(base, headers, endpoint, start_at, function(data, page_err)
      if page_err then
        callback({}, page_err)
        return
      end

      local issues = non_nil(data.issues) or {}
      for _, issue in ipairs(issues) do
        table.insert(all, issue)
      end

      local total = tonumber(data.total) or #all
      if data.isLast == true or #issues == 0 or #all >= total then
        callback(all, nil)
        return
      end

      fetch_page(#all)
    end)
  end

  fetch_page(0)
end

local function fetch_agile_issues(kind, callback)
  local headers, base, err = get_request_headers()
  if err then
    callback({}, err)
    return
  end

  if kind == 'backlog' then
    fetch_endpoint(base, headers, agile_endpoint('backlog'), function(issues, fetch_err)
      if fetch_err then
        callback({}, fetch_err)
        return
      end
      callback(filter_work_issues(issues), nil)
    end)
    return
  end

  fetch_endpoint(base, headers, agile_endpoint('issue'), function(board_issues, board_err)
    if board_err then
      callback({}, board_err)
      return
    end

    fetch_endpoint(base, headers, agile_endpoint('backlog'), function(backlog_issues, backlog_err)
      if backlog_err then
        callback({}, backlog_err)
        return
      end

      local backlog_keys = {}
      for _, issue in ipairs(backlog_issues) do
        backlog_keys[issue.key] = true
      end

      local on_board = {}
      for _, issue in ipairs(board_issues) do
        if not backlog_keys[issue.key] then
          table.insert(on_board, issue)
        end
      end

      callback(filter_work_issues(on_board), nil)
    end)
  end)
end

local function to_board_issue(issue)
  local f = non_nil(issue.fields) or {}
  local status = non_nil(f.status)
  local parent = non_nil(f.parent)
  local priority = non_nil(f.priority)
  local assignee = non_nil(f.assignee)
  local issuetype = non_nil(f.issuetype)
  local labels = non_nil(f.labels)
  return {
    key = issue.key,
    summary = non_nil(f.summary) or '',
    status = (status and non_nil(status.name)) or 'Unknown',
    parent = (parent and non_nil(parent.key)) or nil,
    priority = (priority and non_nil(priority.name)) or 'None',
    assignee = (assignee and (non_nil(assignee.displayName) or non_nil(assignee.name))) or 'Unassigned',
    time_spent = non_nil(f.timespent),
    time_estimate = non_nil(f.timeoriginalestimate),
    type = (issuetype and non_nil(issuetype.name)) or 'Task',
    created = non_nil(f.created),
    labels = (type(labels) == 'table') and labels or {},
  }
end

--- Fetch all accessible Jira projects via REST API (with local disk cache)
---@param callback fun(projects: table[], err: string|nil)
---@param force_refresh? boolean
function M.fetch_all_projects(callback, force_refresh)
  if not force_refresh and vim.fn.filereadable(M.CACHE_FILE) == 1 then
    local f = io.open(M.CACHE_FILE, 'r')
    if f then
      local content = f:read('*a')
      f:close()
      local ok, cached = pcall(vim.json.decode, content)
      if ok and type(cached) == 'table' and #cached > 0 then
        callback(cached, nil)
        return
      end
    end
  end

  local headers, base, err = get_request_headers()
  if err then
    callback({}, err)
    return
  end

  local api_version = '3'
  local ok_cfg, cfg = pcall(require, 'jira.common.config')
  if ok_cfg and cfg.options and cfg.options.jira and cfg.options.jira.api_version then
    api_version = tostring(cfg.options.jira.api_version)
  end

  local url = base .. '/rest/api/' .. api_version .. '/project'
  local cmd = { 'curl', '-s', '-L', '--max-time', '10' }
  for _, h in ipairs(headers) do
    table.insert(cmd, h)
  end
  table.insert(cmd, url)

  vim.system(cmd, { text = true }, function(obj)
    vim.schedule(function()
      if obj.code ~= 0 or not obj.stdout or obj.stdout == '' then
        callback({}, 'Failed to fetch projects from Jira (curl exit ' .. tostring(obj.code) .. ')')
        return
      end

      local ok_json, data = pcall(vim.json.decode, obj.stdout)
      if not ok_json or type(data) ~= 'table' then
        callback({}, 'Invalid JSON response from Jira project endpoint')
        return
      end

      -- If Jira returns errorMessages table
      if data.errorMessages and #data.errorMessages > 0 then
        callback({}, table.concat(data.errorMessages, '\n'))
        return
      end

      local projects = {}
      for _, p in ipairs(data) do
        if p and p.key then
          table.insert(projects, {
            key = p.key,
            name = p.name or p.key,
            id = p.id,
            category = p.projectCategory and p.projectCategory.name or nil,
          })
        end
      end

      table.sort(projects, function(a, b) return a.key < b.key end)

      -- Write to disk cache
      if #projects > 0 then
        local cf = io.open(M.CACHE_FILE, 'w')
        if cf then
          cf:write(vim.json.encode(projects))
          cf:close()
        end
      end

      callback(projects, nil)
    end)
  end)
end

--- Open multi-select project picker using Snacks.picker
---@param on_selected? fun(keys: string[])
function M.select_projects(on_selected)
  local ok_snacks, Snacks = pcall(require, 'snacks')
  if not ok_snacks or not Snacks.picker then
    vim.notify('Snacks.picker is required for Jira project selection', vim.log.levels.ERROR)
    return
  end

  M.fetch_all_projects(function(all_projects, err)
    if err and (#all_projects == 0) then
      vim.notify('Jira: ' .. err, vim.log.levels.WARN, { title = 'Jira Projects' })
      -- Fallback: prompt for manual project keys
      vim.ui.input({ prompt = 'Enter Jira Project Keys (comma separated): ' }, function(input)
        if input and input ~= '' then
          local keys = {}
          for k in input:gmatch('[%w_-]+') do
            table.insert(keys, k:upper())
          end
          if #keys > 0 then
            M.set_active_projects(keys)
            vim.notify('Active Jira projects set: ' .. table.concat(keys, ', '), vim.log.levels.INFO)
            if on_selected then on_selected(keys) end
          end
        end
      end)
      return
    end

    local current_active = M.get_active_projects()
    local selected_map = {}
    for _, k in ipairs(current_active) do
      selected_map[k] = true
    end

    local items = {}
    for _, p in ipairs(all_projects) do
      table.insert(items, {
        key = p.key,
        name = p.name,
        category = p.category,
        text = p.key .. ' ' .. p.name .. (p.category and (' ' .. p.category) or ''),
      })
    end

    local function toggle_item(picker)
      local current = picker:current()
      if not current or not current.key then return end
      selected_map[current.key] = not selected_map[current.key]
      picker:render()
    end

    Snacks.picker({
      title = 'Select Active Jira Projects (<Space> to Toggle, <CR> to Save)',
      items = items,
      layout = {
        preset = 'default',
      },
      win = {
        input = {
          keys = {
            ['<Tab>'] = { 'list_down', mode = { 'i', 'n' } },
            ['<S-Tab>'] = { 'list_up', mode = { 'i', 'n' } },
            ['<C-Space>'] = { function(picker) toggle_item(picker) end, mode = { 'i', 'n' }, desc = 'Toggle Project' },
            ['<C-j>'] = { function() vim.cmd('stopinsert'); _G.BottomPanel.toggle_active() end, mode = { 'i', 'n' } },
          },
        },
        list = {
          keys = {
            ['<Tab>'] = { 'list_down', mode = { 'n', 'x' } },
            ['<S-Tab>'] = { 'list_up', mode = { 'n', 'x' } },
            ['<Space>'] = { function(picker) toggle_item(picker) end, mode = { 'n' }, desc = 'Toggle Project' },
            ['x'] = { function(picker) toggle_item(picker) end, mode = { 'n' }, desc = 'Toggle Project' },
            ['<C-j>'] = { function() _G.BottomPanel.toggle_active() end, mode = { 'n' } },
          },
        },
      },
      format = function(item)
        local is_checked = selected_map[item.key] == true
        local check_str = is_checked and ' [x] ' or ' [ ] '
        local check_hl = is_checked and 'DiagnosticOk' or 'Comment'
        return {
          { check_str, check_hl },
          { string.format('%-8s', item.key), 'Special' },
          { ' ' .. item.name, 'Normal' },
          item.category and { ' (' .. item.category .. ')', 'Comment' } or { '' },
        }
      end,
      confirm = function(picker, item)
        picker:close()

        local final_keys = {}
        for _, it in ipairs(items) do
          if selected_map[it.key] then
            table.insert(final_keys, it.key)
          end
        end

        -- If nothing explicitly checked, take item currently under cursor
        if #final_keys == 0 and item and item.key then
          table.insert(final_keys, item.key)
        end

        M.set_active_projects(final_keys)
        vim.notify('Active Jira projects set: ' .. (#final_keys > 0 and table.concat(final_keys, ', ') or 'None'), vim.log.levels.INFO)
        if on_selected then
          on_selected(final_keys)
        end
      end,
    })
  end)
end

--- Execute action with a single target project (1-vs-many routing gate)
---@param action_fn fun(project_key: string)
function M.with_target_project(action_fn)
  local active = M.get_active_projects()

  if #active == 1 then
    action_fn(active[1])
    return
  end

  if #active > 1 then
    local items = {}
    for _, k in ipairs(active) do
      table.insert(items, { key = k, text = k })
    end

    local ok_snacks, Snacks = pcall(require, 'snacks')
    if ok_snacks and Snacks.picker then
      Snacks.picker({
        title = 'Select Jira Project',
        items = items,
        layout = { preset = 'select' },
        format = function(item)
          return {
            { '  ', 'Special' },
            { item.key, 'Title' },
          }
        end,
        confirm = function(picker, item)
          picker:close()
          if item and item.key then
            action_fn(item.key)
          end
        end,
      })
      return
    end

    vim.ui.select(active, { prompt = 'Select Jira Project: ' }, function(choice)
      if choice then action_fn(choice) end
    end)
    return
  end

  -- If 0 projects selected, prompt project selection first
  vim.notify('No active Jira projects selected. Please select your projects.', vim.log.levels.WARN, { title = 'Jira' })
  M.select_projects(function(keys)
    if #keys > 0 then
      action_fn(keys[1])
    end
  end)
end

local function build_issue_item(issue)
  local f = non_nil(issue.fields) or {}
  local status = non_nil(f.status)
  local assignee = non_nil(f.assignee)
  local priority = non_nil(f.priority)
  local status_name = (status and non_nil(status.name)) or 'Unknown'
  local summary = non_nil(f.summary) or ''
  local assignee_name = (assignee and (non_nil(assignee.displayName) or non_nil(assignee.name))) or 'Unassigned'
  local priority_name = (priority and non_nil(priority.name)) or ''
  local proj_key = issue.key:match('^([%w_]+)%-%d+') or ''
  local labels = {}
  for _, label in ipairs(non_nil(f.labels) or {}) do
    local value = non_nil(label)
    if value and value ~= '' then
      table.insert(labels, value)
    end
  end

  return {
    key = issue.key,
    summary = summary,
    status = status_name,
    assignee = assignee_name,
    priority = priority_name,
    project_key = proj_key,
    description = non_nil(f.description) or '',
    labels = labels,
    text = issue.key .. ' ' .. status_name .. ' ' .. priority_name .. ' ' .. summary .. ' ' .. assignee_name
      .. (#labels > 0 and (' ' .. table.concat(labels, ' ')) or ''),
  }
end

local function build_issue_items(raw_issues)
  local items = {}
  for _, issue in ipairs(raw_issues) do
    table.insert(items, build_issue_item(issue))
  end
  return items
end

local function is_emoji_label(label)
  local first = label:byte(1, 1)
  return first ~= nil and first >= 128
end

local function group_for_issue(issue)
  local item = build_issue_item(issue)
  local first_plain = nil
  for _, label in ipairs(item.labels) do
    local lower = label:lower()
    if lower:find('security', 1, true) or lower:find('bau', 1, true) then
      return label
    end
    if not is_emoji_label(label) then
      first_plain = first_plain or label
    end
  end
  return first_plain or 'Untagged'
end

local function group_rank(group)
  local lower = (group or ''):lower()
  if lower:find('security', 1, true) then
    return 1
  end
  if lower:find('bau', 1, true) then
    return 2
  end
  if group == 'Untagged' then
    return 99
  end
  return 50
end

local function group_compare(a, b)
  local rank_a = group_rank(a)
  local rank_b = group_rank(b)
  if rank_a ~= rank_b then
    return rank_a < rank_b
  end
  return a < b
end

local function issue_item_compare(a, b)
  local priority_a = priority_rank(a.priority)
  local priority_b = priority_rank(b.priority)
  if priority_a ~= priority_b then
    return priority_a < priority_b
  end
  return a.key < b.key
end

local function board_item_compare(a, b)
  local status_a = status_rank(a.status)
  local status_b = status_rank(b.status)
  if status_a ~= status_b then
    return status_a < status_b
  end
  return issue_item_compare(a, b)
end

local function build_grouped_issue_items(raw_issues)
  local groups = {}
  for _, issue in ipairs(raw_issues) do
    local group = group_for_issue(issue)
    groups[group] = groups[group] or {}
    table.insert(groups[group], issue)
  end

  local names = {}
  for name in pairs(groups) do
    table.insert(names, name)
  end
  table.sort(names, group_compare)

  local rows = {}
  for _, name in ipairs(names) do
    local items = build_issue_items(groups[name])
    table.sort(items, issue_item_compare)

    local keys = {}
    for _, item in ipairs(items) do
      table.insert(keys, item.key)
    end

    table.insert(rows, {
      is_header = true,
      group = name,
      group_count = #items,
      text = name .. ' ' .. table.concat(keys, ' '),
    })

    for _, item in ipairs(items) do
      item.group = name
      table.insert(rows, item)
    end
  end
  return rows
end

local function show_issue_picker(items, title)
  local ok_snacks, Snacks = pcall(require, 'snacks')
  if not ok_snacks or not Snacks.picker then
    vim.notify('Snacks.picker is required for Jira search', vim.log.levels.ERROR)
    return
  end

  local function is_real(item)
    return item and not item.is_header and item.key
  end

  Snacks.picker({
    title = title or ('Jira Issues (' .. #items .. ' found)'),
    items = items,
    matcher = { sort = false },
    layout = {
      preset = 'ivy',
    },
    win = {
      input = {
        keys = {
          ['<Tab>'] = { 'list_down', mode = { 'i', 'n' } },
          ['<S-Tab>'] = { 'list_up', mode = { 'i', 'n' } },
          ['<C-j>'] = { function() vim.cmd('stopinsert'); _G.BottomPanel.toggle_active() end, mode = { 'i', 'n' } },
        },
      },
      list = {
        keys = {
          ['<Tab>'] = { 'list_down', mode = { 'n', 'x' } },
          ['<S-Tab>'] = { 'list_up', mode = { 'n', 'x' } },
          ['<C-j>'] = { function() _G.BottomPanel.toggle_active() end, mode = { 'n' } },
          ['<C-e>'] = { function(picker, item)
            if not is_real(item) then return end
            picker:close()
            require('jira.edit').open(item.key)
          end, mode = { 'n', 'i' }, desc = 'Edit Issue' },
          ['<C-b>'] = { function(picker, item)
            if not is_real(item) then return end
            picker:close()
            require('jira.board').open(item.project_key)
          end, mode = { 'n', 'i' }, desc = 'Open Board' },
          ['<C-o>'] = { function(_, item)
            if not is_real(item) then return end
            local auth = require('jira.common.auth').get_auth()
            local base_url = (auth.base or ''):gsub('/+$', '')
            if base_url ~= '' then
              vim.ui.open(base_url .. '/browse/' .. item.key)
            end
          end, mode = { 'n', 'i' }, desc = 'Open in Browser' },
          ['<C-y>'] = { function(_, item)
            if not is_real(item) then return end
            vim.fn.setreg('+', item.key)
            vim.fn.setreg('*', item.key)
            vim.notify('Copied ' .. item.key .. ' to clipboard', vim.log.levels.INFO)
          end, mode = { 'n', 'i' }, desc = 'Yank Key' },
        },
      },
    },
    format = function(item)
      if item.is_header then
        return {
          { ('── %s (%d) ──'):format(item.group, item.group_count or 0), 'SnacksPickerLabel' },
        }
      end

      local status_hl = 'DiagnosticWarn'
      local st = (item.status or ''):upper()
      if st:find('DONE') or st:find('RESOLVED') or st:find('CLOSED') then
        status_hl = 'DiagnosticOk'
      elseif st:find('TODO') or st:find('OPEN') or st:find('BACKLOG') then
        status_hl = 'DiagnosticInfo'
      end

      local priority_hl = 'Comment'
      local pt = (item.priority or ''):lower()
      if pt == 'highest' then
        priority_hl = 'DiagnosticError'
      elseif pt == 'high' then
        priority_hl = 'DiagnosticWarn'
      elseif pt == 'medium' then
        priority_hl = 'DiagnosticInfo'
      end

      return {
        { string.format('%-10s', item.key), 'Special' },
        { string.format(' [%-9s] ', item.priority or 'None'), priority_hl, field = 'priority' },
        { string.format(' [%s] ', item.status), status_hl },
        { item.summary, 'Normal' },
        { ' (' .. item.assignee .. ')', 'Comment' },
      }
    end,
    confirm = function(picker, item)
      if not is_real(item) then return end
      picker:close()
      require('jira.issue').open(item.key)
    end,
  })
end

--- Find issues across active projects with Snacks.picker
---@param custom_jql? string Optional additional JQL filter
---@param title? string Optional picker title
function M.find_issues(custom_jql, title)
  local ok_jira, jira_api = pcall(require, 'jira.jira-api.api')
  if not ok_jira then
    vim.notify('jira.nvim is not loaded', vim.log.levels.ERROR)
    return
  end

  local active = M.get_active_projects()
  local jql = ''

  if #active > 0 then
    local quoted = {}
    for _, k in ipairs(active) do
      table.insert(quoted, string.format('"%s"', k))
    end
    local proj_clause = string.format('project in (%s)', table.concat(quoted, ', '))
    if custom_jql and custom_jql ~= '' then
      jql = proj_clause .. ' AND (' .. custom_jql .. ') ORDER BY updated DESC'
    else
      jql = proj_clause .. ' AND statusCategory != Done ORDER BY updated DESC'
    end
  else
    if custom_jql and custom_jql ~= '' then
      jql = custom_jql .. ' ORDER BY updated DESC'
    else
      jql = 'assignee = currentUser() AND statusCategory != Done ORDER BY updated DESC'
    end
  end

  local common_ui = require('jira.common.ui')
  common_ui.start_loading('Searching Jira issues...')

  jira_api.search_issues(jql, nil, 100, nil, function(result, err)
    vim.schedule(function()
      common_ui.stop_loading()

      if err then
        vim.notify('Jira Search Error: ' .. tostring(err), vim.log.levels.ERROR)
        return
      end

      local raw_issues = (result and result.issues) or {}
      if #raw_issues == 0 then
        vim.notify('No Jira issues found matching query.', vim.log.levels.INFO)
        return
      end

      show_issue_picker(build_issue_items(raw_issues), title)
    end)
  end)
end

--- Search issues assigned to currentUser() across active projects
function M.my_tasks()
  M.find_issues('assignee = currentUser() AND statusCategory != Done', 'My Active Jira Tasks')
end

local function agile_title(kind, count)
  if kind == 'backlog' then
    return 'DDT Kanban Backlog (' .. count .. ' found)'
  end
  return 'DDT Kanban Board (' .. count .. ' found)'
end

function M.show_kanban(kind)
  local ok_ui, common_ui = pcall(require, 'jira.common.ui')
  if not ok_ui then
    vim.notify('jira.nvim is not loaded', vim.log.levels.ERROR)
    return
  end

  common_ui.start_loading('Loading Jira Kanban ' .. kind .. '...')
  fetch_agile_issues(kind, function(raw_issues, err)
    vim.schedule(function()
      common_ui.stop_loading()

      if err then
        vim.notify('Jira Kanban Error: ' .. tostring(err), vim.log.levels.ERROR)
        return
      end

      if #raw_issues == 0 then
        vim.notify('No Jira issues found in ' .. kind .. '.', vim.log.levels.INFO)
        return
      end

      local items
      if kind == 'backlog' then
        items = build_grouped_issue_items(raw_issues)
      else
        items = build_issue_items(raw_issues)
        table.sort(items, board_item_compare)
      end
      show_issue_picker(items, agile_title(kind, #raw_issues))
    end)
  end)
end

function M.get_kanban_issues(kind, callback)
  fetch_agile_issues(kind, function(raw_issues, err)
    if err then
      callback(nil, err)
      return
    end

    local issues = {}
    for _, issue in ipairs(raw_issues) do
      table.insert(issues, to_board_issue(issue))
    end
    table.sort(issues, board_item_compare)
    callback(issues, nil)
  end)
end

--- Prompt for an issue key (or inspect word under cursor) and open issue details
function M.show_issue_details()
  local cword = vim.fn.expand('<cword>')
  local default_key = ''
  if cword and cword:match('^%a[%a%d]+%-%d+$') then
    default_key = cword:upper()
  end

  vim.ui.input({ prompt = 'Open Jira Issue: ', default = default_key }, function(input)
    if input and input ~= '' then
      local key = input:upper():match('[%a%d]+%-%d+') or input:upper()
      require('jira.issue').open(key)
    end
  end)
end

return M
