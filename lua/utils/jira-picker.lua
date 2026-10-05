-- lua/utils/jira-picker.lua
-- Multi-project discovery, state management, and Snacks.picker integration for letieu/jira.nvim

local M = {}

M.STATE_FILE = vim.fn.stdpath('state') .. '/jira_active_projects.json'
M.CACHE_FILE = vim.fn.stdpath('state') .. '/jira_projects_cache.json'

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

--- Find issues across active projects with Snacks.picker
---@param custom_jql? string Optional additional JQL filter
---@param title? string Optional picker title
function M.find_issues(custom_jql, title)
  local ok_snacks, Snacks = pcall(require, 'snacks')
  if not ok_snacks or not Snacks.picker then
    vim.notify('Snacks.picker is required for Jira search', vim.log.levels.ERROR)
    return
  end

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

      local items = {}
      for _, issue in ipairs(raw_issues) do
        local f = issue.fields or {}
        local status_name = (f.status and f.status.name) or 'Unknown'
        local summary = f.summary or ''
        local assignee = (f.assignee and (f.assignee.displayName or f.assignee.name)) or 'Unassigned'
        local priority = (f.priority and f.priority.name) or ''
        local proj_key = issue.key:match('^([%w_]+)%-%d+') or ''

        table.insert(items, {
          key = issue.key,
          summary = summary,
          status = status_name,
          assignee = assignee,
          priority = priority,
          project_key = proj_key,
          description = f.description or '',
          text = issue.key .. ' ' .. status_name .. ' ' .. summary .. ' ' .. assignee,
        })
      end

      Snacks.picker({
        title = title or ('Jira Issues (' .. #items .. ' found)'),
        items = items,
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
              ['<C-e>'] = { function(picker, item) picker:close(); require('jira.edit').open(item.key) end, mode = { 'n', 'i' }, desc = 'Edit Issue' },
              ['<C-b>'] = { function(picker, item) picker:close(); require('jira.board').open(item.project_key) end, mode = { 'n', 'i' }, desc = 'Open Board' },
              ['<C-o>'] = { function(picker, item)
                local auth = require('jira.common.auth').get_auth()
                local base_url = (auth.base or ''):gsub('/+$', '')
                if base_url ~= '' then
                  vim.ui.open(base_url .. '/browse/' .. item.key)
                end
              end, mode = { 'n', 'i' }, desc = 'Open in Browser' },
              ['<C-y>'] = { function(picker, item)
                vim.fn.setreg('+', item.key)
                vim.fn.setreg('*', item.key)
                vim.notify('Copied ' .. item.key .. ' to clipboard', vim.log.levels.INFO)
              end, mode = { 'n', 'i' }, desc = 'Yank Key' },
            },
          },
        },
        format = function(item)
          local status_hl = 'DiagnosticWarn'
          local st = item.status:upper()
          if st:find('DONE') or st:find('RESOLVED') or st:find('CLOSED') then
            status_hl = 'DiagnosticOk'
          elseif st:find('TODO') or st:find('OPEN') or st:find('BACKLOG') then
            status_hl = 'DiagnosticInfo'
          end

          return {
            { string.format('%-10s', item.key), 'Special' },
            { string.format(' [%s] ', item.status), status_hl },
            { item.summary, 'Normal' },
            { ' (' .. item.assignee .. ')', 'Comment' },
          }
        end,
        confirm = function(picker, item)
          picker:close()
          if item and item.key then
            require('jira.issue').open(item.key)
          end
        end,
      })
    end)
  end)
end

--- Search issues assigned to currentUser() across active projects
function M.my_tasks()
  M.find_issues('assignee = currentUser() AND statusCategory != Done', 'My Active Jira Tasks')
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
