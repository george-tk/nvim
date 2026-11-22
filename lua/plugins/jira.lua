local TABS = {
  { id = 'My Tasks', kind = 'query', query = 'My Tasks' },
  { id = 'Board', kind = 'query', query = 'Board' },
  { id = 'Backlog', kind = 'query', query = 'Backlog' },
  { id = 'Help', kind = 'help' },
}

local function active_tab_id(bstate)
  if bstate.current_view == 'Help' then
    return 'Help'
  end
  if bstate.current_view == 'JQL' then
    for _, tab in ipairs(TABS) do
      if tab.query and bstate.current_query == tab.query then
        return tab.id
      end
    end
    return 'JQL'
  end
  return 'My Tasks'
end

local function open_tab(project_key, tab)
  local board = require('jira.board')
  local bstate = require('jira.board.state')
  bstate.project_key = project_key
  if tab.kind == 'help' then
    board.load_view(project_key, 'Help')
  else
    board.switch_query(tab.query)
  end
end

return {
  'letieu/jira.nvim',
  dependencies = {
    'nvim-lua/plenary.nvim',
    'MunifTanjim/nui.nvim',
  },
  cmd = { 'Jira' },
  keys = {
    {
      '<leader>jj',
      function()
        if _G.RightPanel and _G.RightPanel.open_jira then
          _G.RightPanel.open_jira()
        else
          require('utils.jira-picker').with_target_project(function(p)
            open_tab(p, TABS[1])
          end)
        end
      end,
      desc = 'Jira (My Tasks)',
    },
    {
      '<leader>jp',
      function()
        require('utils.jira-picker').select_projects()
      end,
      desc = 'Select Projects',
    },
    {
      '<leader>jn',
      function()
        require('utils.jira-local').prompt_create(function()
          local ok_b, board = pcall(require, 'jira.board')
          local ok_s, bstate = pcall(require, 'jira.board.state')
          if ok_b and ok_s and bstate.win and vim.api.nvim_win_is_valid(bstate.win) then
            board.refresh_view()
          end
        end)
      end,
      desc = 'New Local Ticket',
    },
    {
      '<leader>jc',
      function()
        require('utils.jira-picker').with_target_project(function(p)
          require('jira.create').open(p)
        end)
      end,
      desc = 'Create Issue',
    },
    {
      '<leader>ji',
      function()
        require('utils.jira-picker').show_issue_details()
      end,
      desc = 'Issue Details',
    },
    {
      '<leader>ja',
      function()
        vim.cmd('Jira auth login')
      end,
      desc = 'Jira Auth / Login',
    },
  },
  opts = {
    jira = {
      api_version = '3',
      limit = 200,
      logging = false,
    },
    queries = {
      ['My Tasks'] = 'project = "%s" AND assignee = currentUser() AND statusCategory != Done ORDER BY updated DESC',
      ['Board'] = require('utils.jira-picker').AGILE_BOARD_JQL,
      ['Backlog'] = require('utils.jira-picker').AGILE_BACKLOG_JQL,
    },
  },
  config = function(_, opts)
    require('jira').setup(opts)

    local picker = require('utils.jira-picker')
    local local_tickets = require('utils.jira-local')
    local sprint = require('jira.jira-api.sprint')
    local jira_api = require('jira.jira-api.api')
    local jira_cfg = require('jira.common.config')
    local board = require('jira.board')
    local bstate = require('jira.board.state')
    local bhelper = require('jira.board.helper')
    local board_render = require('jira.board.render')
    local board_ui = require('jira.board.ui')

    -- Expose helper for RightPanel.open_jira()
    board.open_default_tab = function(project_key)
      open_tab(project_key, TABS[1])
    end

    -- 1. Dock Jira Board into the Right Panel (large, non-wrapping split; no dimmed floating overlay)
    local function jira_panel_width()
      local custom = _G.RightPanel and _G.RightPanel.custom_widths or {}
      return custom['jira'] or math.max(96, math.floor(vim.o.columns * 0.55))
    end

    local function ensure_jira_panel_win()
      if bstate.win and vim.api.nvim_win_is_valid(bstate.win) then
        local cfg = vim.api.nvim_win_get_config(bstate.win)
        if not cfg.relative or cfg.relative == '' then
          vim.wo[bstate.win].winfixbuf = false
          return bstate.win
        end
      end
      if _G.RightPanel and _G.RightPanel.close_all then
        _G.RightPanel.close_all()
        _G.RightPanel.active_mode = 'jira'
      end
      vim.cmd(('botright vertical %dsplit'):format(jira_panel_width()))
      local win = vim.api.nvim_get_current_win()
      vim.wo[win].winfixwidth = true
      vim.wo[win].winfixbuf = false
      return win
    end

    local function style_jira_win(win, is_board)
      if not (win and vim.api.nvim_win_is_valid(win)) then
        return
      end
      local wo = vim.wo[win]
      wo.wrap = not is_board
      if not is_board then
        wo.linebreak = true
        wo.breakindent = true
      end
      wo.cursorline = is_board
      wo.number = false
      wo.relativenumber = false
      wo.signcolumn = 'no'
      wo.foldcolumn = '0'
      wo.spell = false
      wo.winfixwidth = true
      wo.winfixbuf = false
    end

    board_ui.create_window = function()
      bstate.dim_win = nil
      bstate.win = ensure_jira_panel_win()
      bstate.buf = vim.api.nvim_create_buf(false, true)
      vim.bo[bstate.buf].bufhidden = 'hide'
      vim.bo[bstate.buf].buftype = 'nofile'
      vim.bo[bstate.buf].filetype = 'jira-board'
      vim.bo[bstate.buf].modifiable = false
      vim.bo[bstate.buf].swapfile = false
      vim.b[bstate.buf].panel_zone = 'right'
      vim.b[bstate.buf].panel_type = 'jira'

      vim.api.nvim_win_set_buf(bstate.win, bstate.buf)
      vim.api.nvim_win_set_hl_ns(bstate.win, bstate.ns)
      style_jira_win(bstate.win, true)

      local resize_group = vim.api.nvim_create_augroup('JiraBoardRightPanelResize', { clear = true })
      local last_w = vim.api.nvim_win_get_width(bstate.win)
      vim.api.nvim_create_autocmd('WinResized', {
        group = resize_group,
        callback = function()
          if not (bstate.win and vim.api.nvim_win_is_valid(bstate.win) and bstate.buf and vim.api.nvim_buf_is_valid(bstate.buf)) then
            return
          end
          local nw = vim.api.nvim_win_get_width(bstate.win)
          if nw ~= last_w and bstate.current_view ~= 'Help' and bstate.tree and #bstate.tree > 0 then
            last_w = nw
            local cur = vim.api.nvim_win_get_cursor(bstate.win)
            board_render.clear(bstate.buf)
            board_render.render_issue_tree(bstate.tree, bstate.current_view)
            local max_l = vim.api.nvim_buf_line_count(bstate.buf)
            pcall(vim.api.nvim_win_set_cursor, bstate.win, { math.min(cur[1], max_l), 0 })
          end
        end,
      })

      if _G.RightPanel and _G.RightPanel.ensure_precedence then
        vim.schedule(function()
          _G.RightPanel.ensure_precedence()
          pcall(function()
            require('lualine').refresh()
          end)
        end)
      end
    end

    -- 2. Capture `created` from Jira search responses (sprint.lua strips it)
    local issue_meta_cache = {}
    local orig_search_issues = jira_api.search_issues
    jira_api.search_issues = function(jql, page_token, max_results, fields, callback, project_key)
      if not fields then
        local sp_field = jira_cfg.get_project_config(project_key).story_point_field
        fields = {
          'summary',
          'status',
          'parent',
          'priority',
          'assignee',
          'timespent',
          'timeoriginalestimate',
          'issuetype',
          'created',
          sp_field,
        }
      end
      local wrapped_cb = function(result, err)
        if result and type(result.issues) == 'table' then
          for _, iss in ipairs(result.issues) do
            if iss and iss.key and type(iss.fields) == 'table' then
              local created = iss.fields.created
              issue_meta_cache[iss.key] = {
                created = (created ~= nil and created ~= vim.NIL) and created or nil,
              }
            end
          end
        end
        if callback and vim.is_callable(callback) then
          callback(result, err)
        end
      end
      return orig_search_issues(jql, page_token, max_results, fields, wrapped_cb, project_key)
    end

    local original_get_issues_by_jql = sprint.get_issues_by_jql
    sprint.get_issues_by_jql = function(project, jql, callback)
      if jql == picker.AGILE_BOARD_JQL then
        return picker.get_kanban_issues('board', callback)
      elseif jql == picker.AGILE_BACKLOG_JQL then
        return picker.get_kanban_issues('backlog', callback)
      end
      local is_my_tasks = (bstate.current_query == 'My Tasks')
      return original_get_issues_by_jql(project, jql, function(issues, err)
        if not is_my_tasks then
          return callback(issues, err)
        end
        local merged = {}
        for _, iss in ipairs(issues or {}) do
          table.insert(merged, iss)
        end
        local locals = local_tickets.list_active()
        for _, lt in ipairs(locals) do
          table.insert(merged, lt)
        end
        if err and #locals > 0 then
          -- Still show local tickets even if Jira search failed
          vim.notify('Jira fetch failed (' .. tostring(err) .. '); showing local tickets', vim.log.levels.WARN)
          return callback(merged, nil)
        end
        return callback(merged, err)
      end)
    end

    -- 3. Custom 4-tab header & compact ticket row renderer (Priority, Age, Assignee, Status)
    local COL_MAX = {
      PRIORITY = 7,
      AGE = 5,
      ASSIGNEE = 10,
      STATUS = 13,
    }
    -- Fixed display width of the right block: prio(7) + 2 + age(5) + 2 + ass(10) + 2 + " status "(15) = 43
    local RIGHT_BLOCK_WIDTH = COL_MAX.PRIORITY + 2 + COL_MAX.AGE + 2 + COL_MAX.ASSIGNEE + 2 + (COL_MAX.STATUS + 2)

    local function trunc(str, max)
      if max <= 1 then
        return ''
      end
      if vim.fn.strdisplaywidth(str) <= max then
        return str
      end
      local n = vim.fn.strchars(str)
      local cut = math.min(n, max - 1)
      local out = vim.fn.strcharpart(str, 0, cut)
      while cut > 0 and vim.fn.strdisplaywidth(out) > max - 1 do
        cut = cut - 1
        out = vim.fn.strcharpart(str, 0, cut)
      end
      return out .. '…'
    end

    local function pad_right(str, width)
      local w = vim.fn.strdisplaywidth(str)
      return str .. (' '):rep(math.max(0, width - w))
    end

    local function days_since_created(created)
      if type(created) ~= 'string' or created == '' then
        return nil
      end
      local y, m, d, H, M, S = created:match('^(%d%d%d%d)%-(%d%d)%-(%d%d)T(%d%d):(%d%d):(%d%d)')
      if not y then
        return nil
      end
      local ts = os.time({
        year = tonumber(y),
        month = tonumber(m),
        day = tonumber(d),
        hour = tonumber(H),
        min = tonumber(M),
        sec = tonumber(S),
      })
      if not ts then
        return nil
      end
      return math.max(0, math.floor((os.time() - ts) / 86400))
    end

    local function issue_type_icon(t)
      t = t or ''
      if t == 'Bug' then
        return '', 'JiraIconBug'
      elseif t == 'Story' then
        return '', 'JiraIconStory'
      elseif t == 'Task' then
        return '', 'JiraIconTask'
      elseif t == 'Sub-task' or t == 'Subtask' then
        return '󰙅', 'JiraIconSubTask'
      elseif t == 'Sub-Test' or t == 'Sub Test Execution' then
        return '󰙨', 'JiraIconTest'
      elseif t == 'Sub Design' then
        return '󰟶', 'JiraIconDesign'
      elseif t == 'Sub Overhead' then
        return '󱖫', 'JiraIconOverhead'
      elseif t == 'Sub-Imp' then
        return '', 'JiraIconImp'
      end
      return '●', 'JiraIconStory'
    end

    local function priority_hl(prio)
      local p = (prio or ''):lower()
      if p == 'highest' or p == 'critical' or p == 'blocker' then
        return 'DiagnosticError'
      elseif p == 'high' then
        return 'DiagnosticWarn'
      elseif p == 'medium' then
        return 'DiagnosticInfo'
      end
      return 'Comment'
    end

    local function render_tab_header()
      local buf = bstate.buf
      if not (buf and vim.api.nvim_buf_is_valid(buf)) then
        return
      end
      local current = active_tab_id(bstate)
      local header = '  '
      local hls = {}

      local tabs_to_draw = vim.deepcopy(TABS)
      if current == 'JQL' then
        table.insert(tabs_to_draw, { id = 'JQL' })
      end

      for _, tab in ipairs(tabs_to_draw) do
        local is_active = (current == tab.id)
        local tab_str = (' %s '):format(tab.id)
        local start_col = #header
        header = header .. tab_str .. '  '
        table.insert(hls, {
          row = 0,
          start_col = start_col,
          end_col = start_col + #tab_str,
          hl = is_active and 'JiraTabActive' or 'JiraTabInactive',
        })
      end

      vim.api.nvim_set_option_value('modifiable', true, { buf = buf })
      vim.api.nvim_buf_set_lines(buf, 0, 2, false, { header, '' })
      vim.api.nvim_set_option_value('modifiable', false, { buf = buf })

      for _, h in ipairs(hls) do
        pcall(vim.api.nvim_buf_set_extmark, buf, bstate.ns, h.row, h.start_col, {
          end_col = h.end_col,
          hl_group = h.hl,
        })
      end
    end

    local function render_custom_issue_line(node, depth, row, align_col)
      local buf = bstate.buf
      if not (buf and vim.api.nvim_buf_is_valid(buf)) then
        return
      end
      local indent = ('    '):rep(depth - 1)
      local icon, icon_hl = issue_type_icon(node.type)
      local expand_icon = ' '
      if node.children and #node.children > 0 then
        expand_icon = node.expanded and '' or ''
      end

      local key = node.key or ''
      local prefix = ('%s%s %s %s '):format(indent, expand_icon, icon, key)
      local max_title_w = math.max(12, align_col - vim.fn.strdisplaywidth(prefix) - 2)
      local title = trunc(node.summary or '', max_title_w)

      local meta = issue_meta_cache[key] or {}
      local created = node.created or meta.created

      local prio_raw = (node.priority and node.priority ~= '' and node.priority ~= 'None') and node.priority or '-'
      local prio_str = trunc(prio_raw, COL_MAX.PRIORITY)
      local prio_h = (prio_raw == '-') and 'Comment' or priority_hl(prio_raw)

      local age_days = days_since_created(created)
      local age_str = trunc(age_days and (tostring(age_days) .. 'd') or '-', COL_MAX.AGE)
      local age_hl = (age_days and age_days >= 30) and 'DiagnosticWarn' or 'Comment'

      local ass_str = ' ' .. trunc(node.assignee or 'Unassigned', COL_MAX.ASSIGNEE - 2)
      local ass_hl = (not node.assignee or node.assignee == 'Unassigned') and 'JiraAssigneeUnassigned' or 'JiraAssignee'

      local status_text = trunc(node.status or 'Unknown', COL_MAX.STATUS)
      local status_str = ' ' .. pad_right(status_text, COL_MAX.STATUS) .. ' '
      local status_hl = board_ui.get_status_hl(node.status)

      local left = prefix .. title
      local right_part = ('%s  %s  %s  %s'):format(
        pad_right(prio_str, COL_MAX.PRIORITY),
        pad_right(age_str, COL_MAX.AGE),
        pad_right(ass_str, COL_MAX.ASSIGNEE),
        status_str
      )

      local pad_len = math.max(2, align_col - vim.fn.strdisplaywidth(left))
      local padding = (' '):rep(pad_len)
      local full_line = left .. padding .. right_part

      local hls = {}
      local function add_hl(sc, text, hl)
        if #text > 0 then
          table.insert(hls, { start_col = sc, end_col = sc + #text, hl = hl })
        end
      end

      local col = #indent
      add_hl(col, expand_icon, 'Comment')
      col = col + #expand_icon + 1
      add_hl(col, icon, icon_hl)
      col = col + #icon + 1
      add_hl(col, key, depth == 1 and 'Title' or 'LineNr')
      col = col + #key + 1
      add_hl(col, title, depth == 1 and 'JiraTopLevel' or 'Comment')

      local rc = #left + #padding
      add_hl(rc, prio_str, prio_h)
      rc = rc + #pad_right(prio_str, COL_MAX.PRIORITY) + 2
      add_hl(rc, age_str, age_hl)
      rc = rc + #pad_right(age_str, COL_MAX.AGE) + 2
      add_hl(rc, ass_str, ass_hl)
      rc = rc + #pad_right(ass_str, COL_MAX.ASSIGNEE) + 2
      add_hl(rc, status_str, status_hl)

      vim.api.nvim_buf_clear_namespace(buf, bstate.ns, row, row + 1)
      vim.api.nvim_set_option_value('modifiable', true, { buf = buf })
      vim.api.nvim_buf_set_lines(buf, row, row + 1, false, { full_line })
      vim.api.nvim_set_option_value('modifiable', false, { buf = buf })

      for _, h in ipairs(hls) do
        pcall(vim.api.nvim_buf_set_extmark, buf, bstate.ns, row, h.start_col, {
          end_col = h.end_col,
          hl_group = h.hl,
        })
      end
    end

    local function compute_align_col(issues)
      local total_w = vim.api.nvim_win_get_width(bstate.win or 0)
      local max_avail_left = math.max(24, total_w - RIGHT_BLOCK_WIDTH - 2)
      local longest = 0
      local function walk(nodes, d)
        for _, n in ipairs(nodes or {}) do
          local prefix_w = (d - 1) * 4 + 4 + #(n.key or '') + 1
          local w = prefix_w + vim.fn.strdisplaywidth(n.summary or '')
          if w > longest then
            longest = w
          end
          if n.children and #n.children > 0 and n.expanded then
            walk(n.children, d + 1)
          end
        end
      end
      walk(issues, 1)
      return math.min(max_avail_left, math.max(28, longest + 3))
    end

    board_render.render_issue_tree = function(issues, view, depth, row, align_col)
      depth = depth or 1
      if not row then
        row = 2
      end

      if depth == 1 then
        bstate.line_map = {}
        bstate.jql_line = nil
        bstate.query_map = {}
        render_tab_header()
        align_col = compute_align_col(issues)
      end

      local local_divider_drawn = false
      for i, node in ipairs(issues or {}) do
        if depth == 1 and node.is_local and not local_divider_drawn then
          local_divider_drawn = true
          local sep_lines = {}
          if i > 1 then
            table.insert(sep_lines, '')
          end
          local total_w = vim.api.nvim_win_get_width(bstate.win or 0)
          local label = '  ── Local Tasks '
          local rule_len = math.max(4, total_w - vim.fn.strdisplaywidth(label) - 2)
          local sep_line = label .. ('─'):rep(rule_len)
          table.insert(sep_lines, sep_line)
          table.insert(sep_lines, '')
          vim.api.nvim_set_option_value('modifiable', true, { buf = bstate.buf })
          vim.api.nvim_buf_set_lines(bstate.buf, row, row + #sep_lines, false, sep_lines)
          vim.api.nvim_set_option_value('modifiable', false, { buf = bstate.buf })
          local label_row = row + (i > 1 and 1 or 0)
          pcall(vim.api.nvim_buf_set_extmark, bstate.buf, bstate.ns, label_row, 0, {
            end_col = #sep_line,
            hl_group = 'Comment',
          })
          row = row + #sep_lines
        elseif depth == 1 and i > 1 then
          vim.api.nvim_set_option_value('modifiable', true, { buf = bstate.buf })
          vim.api.nvim_buf_set_lines(bstate.buf, row, row + 1, false, { '' })
          vim.api.nvim_set_option_value('modifiable', false, { buf = bstate.buf })
          row = row + 1
        end

        bstate.line_map[row] = node
        render_custom_issue_line(node, depth, row, align_col)
        row = row + 1

        if node.children and #node.children > 0 and node.expanded then
          row = board_render.render_issue_tree(node.children, view, depth + 1, row, align_col)
        end
      end

      if depth == 1 and bstate.win and vim.api.nvim_win_is_valid(bstate.win) and #(issues or {}) > 0 then
        local first_row = nil
        for r in pairs(bstate.line_map) do
          if not first_row or r < first_row then
            first_row = r
          end
        end
        if first_row then
          local cur_row = vim.api.nvim_win_get_cursor(bstate.win)[1]
          if cur_row < first_row + 1 then
            pcall(vim.api.nvim_win_set_cursor, bstate.win, { first_row + 1, 0 })
          end
        end
      end

      return row
    end

    board_render.render_help = function()
      local buf = bstate.buf
      if not (buf and vim.api.nvim_buf_is_valid(buf)) then
        return
      end
      render_tab_header()

      local help_content = {
        { section = 'Tabs & Navigation' },
        { k = '<Tab> / <S-Tab>', d = 'Cycle tabs (My Tasks → Board → Backlog → Help)' },
        { k = 'j / k', d = 'Jump to next / previous ticket' },
        { k = 'l / gd', d = 'Open ticket viewer (D/C/H tabs, S to change status)' },
        { k = '<CR>', d = 'Expand / collapse subtasks' },
        { k = 'zR / zM', d = 'Expand / collapse all subtasks' },
        { k = '/', d = 'Run custom JQL query' },
        { k = 'r', d = 'Refresh current tab' },
        { k = 'q', d = 'Close Jira panel' },
        { section = 'Ticket Actions' },
        { k = 'gs', d = 'Change ticket status (also S inside ticket viewer)' },
        { k = 'ga', d = 'Change assignee' },
        { k = 'ge', d = 'Edit ticket directly' },
        { k = 'K', d = 'Quick details popup' },
        { k = 'i', d = 'Create Jira issue / sub-task' },
        { k = 'n', d = 'Create local personal ticket (never sent to Jira)' },
        { k = 'X', d = 'Delete local ticket under cursor' },
        { k = 'gx', d = 'Open in browser' },
        { k = 'gb', d = 'Checkout / create git branch' },
        { k = 'gw', d = 'Log work time' },
        { k = 'go / gp', d = 'Show child / parent issues' },
      }

      local start_row = 2
      local lines = {}
      local hls = {}
      for _, item in ipairs(help_content) do
        if item.section then
          table.insert(lines, '')
          table.insert(lines, '  ' .. item.section .. ':')
          table.insert(hls, { row = start_row + #lines - 1, start_col = 2, end_col = -1, hl = 'Title' })
        else
          local line = ('    %-18s %s'):format(item.k, item.d)
          table.insert(lines, line)
          table.insert(hls, { row = start_row + #lines - 1, start_col = 4, end_col = 4 + #item.k, hl = 'Special' })
        end
      end

      vim.api.nvim_set_option_value('modifiable', true, { buf = buf })
      vim.api.nvim_buf_set_lines(buf, start_row, -1, false, lines)
      vim.api.nvim_set_option_value('modifiable', false, { buf = buf })

      for _, h in ipairs(hls) do
        local ext_opts = { hl_group = h.hl }
        if h.end_col and h.end_col ~= -1 then
          ext_opts.end_col = h.end_col
        end
        pcall(vim.api.nvim_buf_set_extmark, buf, bstate.ns, h.row, h.start_col, ext_opts)
      end
    end

    -- 4. Board keymaps: <Tab>/<S-Tab> cycle tabs, j/k jump tickets, l opens viewer, <CR> folds, / runs JQL
    local orig_setup_keymaps = board.setup_keymaps

    local function cycle_tab(dir)
      local current = active_tab_id(bstate)
      local idx = 1
      for i, tab in ipairs(TABS) do
        if tab.id == current then
          idx = i
          break
        end
      end
      local next_idx = ((idx - 1 + dir) % #TABS) + 1
      open_tab(bstate.project_key, TABS[next_idx])
    end

    local function jump_ticket(dir)
      if not (bstate.win and vim.api.nvim_win_is_valid(bstate.win)) then
        return
      end
      local rows = {}
      for row in pairs(bstate.line_map or {}) do
        table.insert(rows, row)
      end
      if #rows == 0 then
        vim.cmd('normal! ' .. (dir > 0 and 'j' or 'k'))
        return
      end

      table.sort(rows)
      local cur_row = vim.api.nvim_win_get_cursor(bstate.win)[1] - 1
      local target = nil
      if dir > 0 then
        for _, r in ipairs(rows) do
          if r > cur_row then
            target = r
            break
          end
        end
      else
        for i = #rows, 1, -1 do
          if rows[i] < cur_row then
            target = rows[i]
            break
          end
        end
      end

      if target ~= nil then
        vim.api.nvim_win_set_cursor(bstate.win, { target + 1, 0 })
      end
    end

    board.setup_keymaps = function(...)
      orig_setup_keymaps(...)
      local buf = bstate.buf
      if not (buf and vim.api.nvim_buf_is_valid(buf)) then
        return
      end
      for _, old_k in ipairs({ 'S', 'J', 'H' }) do
        pcall(vim.api.nvim_buf_del_keymap, buf, 'n', old_k)
      end

      local map_opts = function(desc)
        return { noremap = true, silent = true, nowait = true, buffer = buf, desc = 'Jira: ' .. desc }
      end
      vim.keymap.set('n', 'q', function()
        if _G.RightPanel then
          _G.RightPanel.close_all()
          local ed = _G.RightPanel.get_editor_win and _G.RightPanel.get_editor_win()
          if ed and vim.api.nvim_win_is_valid(ed) then
            vim.api.nvim_set_current_win(ed)
          end
        elseif bstate.win and vim.api.nvim_win_is_valid(bstate.win) then
          vim.api.nvim_win_close(bstate.win, true)
        end
      end, map_opts('Close panel'))
      vim.keymap.set('n', '<Tab>', function()
        cycle_tab(1)
      end, map_opts('Next tab'))
      vim.keymap.set('n', '<S-Tab>', function()
        cycle_tab(-1)
      end, map_opts('Previous tab'))
      vim.keymap.set('n', '<CR>', function()
        board.toggle_node()
      end, map_opts('Toggle subtasks'))
      vim.keymap.set('n', 'j', function()
        jump_ticket(1)
      end, map_opts('Next ticket'))
      vim.keymap.set('n', 'k', function()
        jump_ticket(-1)
      end, map_opts('Previous ticket'))
      local function return_to_board(close_buf)
        local win = bstate.win
        if win and vim.api.nvim_win_is_valid(win) and bstate.buf and vim.api.nvim_buf_is_valid(bstate.buf) then
          vim.wo[win].winfixbuf = false
          vim.api.nvim_win_set_buf(win, bstate.buf)
          style_jira_win(win, true)
          vim.api.nvim_set_current_win(win)
        end
        if close_buf and vim.api.nvim_buf_is_valid(close_buf) then
          pcall(vim.api.nvim_buf_delete, close_buf, { force = true })
        end
      end

      vim.keymap.set('n', 'l', function()
        local node = bhelper.get_node_at_cursor()
        if not (node and node.key) then
          return
        end
        if local_tickets.is_local_key(node.key) then
          local_tickets.open_viewer(node.key, bstate.win, {
            style_win = style_jira_win,
            on_change = function()
              board.refresh_view()
            end,
            on_close = return_to_board,
          })
        else
          board.read_task()
        end
      end, map_opts('View ticket'))
      vim.keymap.set('n', 'gd', function()
        local node = bhelper.get_node_at_cursor()
        if node and local_tickets.is_local_key(node.key) then
          local_tickets.open_viewer(node.key, bstate.win, {
            style_win = style_jira_win,
            on_change = function()
              board.refresh_view()
            end,
            on_close = return_to_board,
          })
        else
          board.read_task()
        end
      end, map_opts('View ticket'))
      vim.keymap.set('n', 'ge', function()
        local node = bhelper.get_node_at_cursor()
        if node and local_tickets.is_local_key(node.key) then
          local_tickets.open_editor(node.key, bstate.win, {
            style_win = style_jira_win,
            on_change = function()
              board.refresh_view()
            end,
            on_close = return_to_board,
          })
        else
          board.edit_issue()
        end
      end, map_opts('Edit ticket'))
      vim.keymap.set('n', 'gs', function()
        local node = bhelper.get_node_at_cursor()
        if node and local_tickets.is_local_key(node.key) then
          local_tickets.prompt_status(node.key, function()
            board.refresh_view()
          end)
        else
          board.change_status()
        end
      end, map_opts('Change status'))
      vim.keymap.set('n', 'n', function()
        local_tickets.prompt_create(function()
          board.refresh_view()
        end)
      end, map_opts('New local ticket'))
      vim.keymap.set('n', 'X', function()
        local node = bhelper.get_node_at_cursor()
        if node and local_tickets.is_local_key(node.key) then
          local_tickets.prompt_delete(node.key, function()
            board.refresh_view()
          end)
        end
      end, map_opts('Delete local ticket'))
      vim.keymap.set('n', '/', function()
        board.prompt_jql()
      end, map_opts('Custom JQL query'))
    end

    -- 5. Add `S` (Change status) inside the jira.issue ticket viewer (matching `D`, `C`, `H`)
    local issue_mod = require('jira.issue')
    local issue_state = require('jira.issue.state')
    local issue_render = require('jira.issue.render')
    local orig_render_content = issue_render.render_content

    local function change_viewer_status()
      local key = issue_state.issue and issue_state.issue.key
      if not key then
        return
      end
      local common_ui = require('jira.common.ui')
      common_ui.start_loading('Fetching transitions for ' .. key .. '...')
      jira_api.get_transitions(key, function(transitions, err)
        vim.schedule(function()
          common_ui.stop_loading()
          if err then
            vim.notify('Error fetching transitions: ' .. tostring(err), vim.log.levels.ERROR)
            return
          end
          if not transitions or #transitions == 0 then
            vim.notify('No available transitions for ' .. key, vim.log.levels.WARN)
            return
          end

          local choices = {}
          local id_map = {}
          for _, t in ipairs(transitions) do
            table.insert(choices, t.name)
            id_map[t.name] = t.id
          end

          vim.ui.select(choices, { prompt = 'Select Status for ' .. key .. ':' }, function(choice)
            if not choice then
              return
            end
            local transition_id = id_map[choice]
            common_ui.start_loading('Updating status to ' .. choice .. '...')
            jira_api.transition_issue(key, transition_id, function(_, t_err)
              vim.schedule(function()
                common_ui.stop_loading()
                if t_err then
                  vim.notify('Error updating status: ' .. tostring(t_err), vim.log.levels.ERROR)
                  return
                end
                vim.notify('Updated ' .. key .. ' to ' .. choice, vim.log.levels.INFO)
                issue_mod.refresh()
                if bstate.win and vim.api.nvim_win_is_valid(bstate.win) then
                  board.refresh_view()
                end
              end)
            end)
          end)
        end)
      end)
    end

    issue_render.render_content = function(...)
      local res = orig_render_content(...)
      local buf = issue_state.buf
      if buf and vim.api.nvim_buf_is_valid(buf) then
        vim.bo[buf].bufhidden = 'hide'
        vim.b[buf].panel_zone = 'right'
        vim.b[buf].panel_type = 'jira'

        -- Dock the ticket viewer in-place inside the Jira Right Panel instead of floating
        if issue_state.win and vim.api.nvim_win_is_valid(issue_state.win) then
          local cfg = vim.api.nvim_win_get_config(issue_state.win)
          if cfg.relative and cfg.relative ~= '' then
            local float_win = issue_state.win
            local target_win = ensure_jira_panel_win()
            vim.api.nvim_win_set_buf(target_win, buf)
            pcall(vim.api.nvim_win_close, float_win, true)
            issue_state.win = target_win
            bstate.win = target_win
            vim.api.nvim_set_current_win(target_win)
            style_jira_win(target_win, false)
            if _G.RightPanel and _G.RightPanel.ensure_precedence then
              vim.schedule(function()
                _G.RightPanel.ensure_precedence()
              end)
            end
          end
        end

        if not vim.b[buf].jira_viewer_keymaps then
          vim.b[buf].jira_viewer_keymaps = true
          vim.schedule(function()
            if not vim.api.nvim_buf_is_valid(buf) then
              return
            end
            vim.keymap.set('n', 'S', change_viewer_status, {
              noremap = true,
              silent = true,
              nowait = true,
              buffer = buf,
              desc = 'Jira: Change status',
            })
            vim.keymap.set('n', 'q', function()
              local win = issue_state.win
              if win and vim.api.nvim_win_is_valid(win) and bstate.buf and vim.api.nvim_buf_is_valid(bstate.buf) then
                vim.wo[win].winfixbuf = false
                vim.api.nvim_win_set_buf(win, bstate.buf)
                bstate.win = win
                style_jira_win(win, true)
                vim.api.nvim_set_current_win(win)
                pcall(vim.api.nvim_buf_delete, buf, { force = true })
                issue_state.buf = nil
                issue_state.win = nil
              elseif _G.RightPanel then
                _G.RightPanel.close_all()
                local ed = _G.RightPanel.get_editor_win and _G.RightPanel.get_editor_win()
                if ed and vim.api.nvim_win_is_valid(ed) then
                  vim.api.nvim_set_current_win(ed)
                end
              end
            end, {
              noremap = true,
              silent = true,
              nowait = true,
              buffer = buf,
              desc = 'Jira: Back to board',
            })
          end)
        end
      end
      return res
    end

    -- 6. Dock the Jira ticket editor (`Jira Edit: <key>`) in-place inside the Right Panel
    local edit_group = vim.api.nvim_create_augroup('JiraEditRightPanel', { clear = true })
    vim.api.nvim_create_autocmd('BufWinEnter', {
      group = edit_group,
      pattern = 'Jira Edit: *',
      callback = function(args)
        local buf = args.buf
        if not (buf and vim.api.nvim_buf_is_valid(buf)) then
          return
        end
        local cur_win = vim.api.nvim_get_current_win()
        local cfg = vim.api.nvim_win_is_valid(cur_win) and vim.api.nvim_win_get_config(cur_win) or nil
        if cfg and cfg.relative and cfg.relative ~= '' then
          vim.schedule(function()
            if not (vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_win_is_valid(cur_win)) then
              return
            end
            local prev_buf = (issue_state.buf and vim.api.nvim_buf_is_valid(issue_state.buf)) and issue_state.buf
              or (bstate.buf and vim.api.nvim_buf_is_valid(bstate.buf)) and bstate.buf
              or nil
            vim.bo[buf].bufhidden = 'hide'
            vim.b[buf].panel_zone = 'right'
            vim.b[buf].panel_type = 'jira'
            local target_win = ensure_jira_panel_win()
            vim.api.nvim_win_set_buf(target_win, buf)
            pcall(vim.api.nvim_win_close, cur_win, true)
            bstate.win = target_win
            vim.api.nvim_set_current_win(target_win)
            style_jira_win(target_win, false)

            vim.keymap.set('n', 'q', function()
              local back = (prev_buf and vim.api.nvim_buf_is_valid(prev_buf)) and prev_buf
                or (bstate.buf and vim.api.nvim_buf_is_valid(bstate.buf)) and bstate.buf
                or nil
              if back and vim.api.nvim_win_is_valid(target_win) then
                vim.wo[target_win].winfixbuf = false
                vim.api.nvim_win_set_buf(target_win, back)
                local back_is_board = (back == bstate.buf)
                style_jira_win(target_win, back_is_board)
                if back == issue_state.buf then
                  issue_state.win = target_win
                end
                vim.api.nvim_set_current_win(target_win)
                pcall(vim.api.nvim_buf_delete, buf, { force = true })
              elseif _G.RightPanel then
                _G.RightPanel.close_all()
                local ed = _G.RightPanel.get_editor_win and _G.RightPanel.get_editor_win()
                if ed and vim.api.nvim_win_is_valid(ed) then
                  vim.api.nvim_set_current_win(ed)
                end
              end
            end, {
              noremap = true,
              silent = true,
              nowait = true,
              buffer = buf,
              desc = 'Jira: Close editor & return',
            })

            if _G.RightPanel and _G.RightPanel.ensure_precedence then
              _G.RightPanel.ensure_precedence()
            end
          end)
        end
      end,
    })
  end,
}
