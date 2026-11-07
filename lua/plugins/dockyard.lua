return {
  'emrearmagan/dockyard.nvim',
  cmd = {
    'Dockyard',
    'DockyardFloat',
    'DockyardFull',
    'DockyardBuild',
    'DockyardRun',
    'DockyardLogs',
    'DockyardFiles',
  },
  keys = {
    {
      '<leader>DD',
      function()
        if _G.RightPanel and _G.RightPanel.open_dockyard then
          _G.RightPanel.open_dockyard()
        else
          vim.cmd 'Dockyard'
        end
      end,
      desc = 'Docker Panel',
    },
    {
      '<leader>Dd',
      function()
        if _G.RightPanel and _G.RightPanel.open_dockyard then
          _G.RightPanel.open_dockyard()
        else
          vim.cmd 'Dockyard'
        end
      end,
      desc = 'Docker Panel',
    },
    {
      '<leader>Db',
      '<cmd>DockyardBuild<CR>',
      desc = 'Build Dockerfile',
    },
    {
      '<leader>Dr',
      '<cmd>DockyardRun<CR>',
      mode = { 'n', 'v' },
      desc = 'Run Docker Compose',
    },
  },
  opts = {
    display = {
      views = { 'containers', 'compose', 'images', 'networks', 'volumes' },
    },
    keymaps = {
      ui = {
        help = 'g?',
        close = 'q',
        refresh = 'R',
        next_view = { '<Tab>', ']' },
        prev_view = { '<S-Tab>', '[' },
        toggle_node = '<CR>',
        open_details = 'K',
        open_panel = 'p',
      },
      containers = {
        toggle_start_stop = 's',
        stop = 'x',
        restart = 'r',
        remove = 'd',
        open_terminal = 'T',
        open_logs = 'L',
        open_files = 'f',
      },
      images = {
        remove = 'd',
        prune = 'P',
      },
      networks = {
        remove = 'd',
      },
      volumes = {
        remove = 'd',
      },
      loglens = {
        close = 'q',
        toggle_follow = 'f',
        toggle_raw = 'r',
        filter = '/',
        clear_filter = 'c',
        next_source = '<Tab>',
        prev_source = '<S-Tab>',
        open_detail = { 'l', '<CR>', 'K' },
        help = 'g?',
      },
    },
  },
  config = function(_, opts)
    local dockyard = require 'dockyard'
    dockyard.setup(opts)

    local ui = require 'dockyard.ui'
    local ui_state = require 'dockyard.ui.state'
    local ui_utils = require 'dockyard.ui.utils'
    local navigation = require 'dockyard.ui.navigation'
    local statusline = require 'dockyard.ui.statusline'
    local keymaps = require 'dockyard.ui.keymaps'
    local popup_mod = require 'dockyard.ui.popups.popup'
    local help_mod = require 'dockyard.ui.popups.help'
    local loglens_win = require 'dockyard.ui.loglens.window'
    local loglens = require 'dockyard.ui.loglens'
    local files_browser = require 'dockyard.files.browser'
    local term_view = require 'dockyard.ui.views.terminal'

    -- Fix Dockyard's async navigation callbacks (`navigation.first/last/up/down`) which pass window `0`
    -- instead of `ui_state.win_id` and crash if another window is focused or buffer has fewer lines
    local function sorted_row_lines()
      local lines = {}
      for lnum, _ in pairs(ui_state.line_map or {}) do
        if type(lnum) == 'number' then
          table.insert(lines, lnum)
        end
      end
      table.sort(lines)
      return lines
    end

    local function set_dockyard_cursor(target_line)
      local win = (ui_state.win_id and vim.api.nvim_win_is_valid(ui_state.win_id)) and ui_state.win_id or nil
      if not win then
        return
      end
      local buf = vim.api.nvim_win_get_buf(win)
      if not vim.api.nvim_buf_is_valid(buf) or (ui_state.buf_id and buf ~= ui_state.buf_id) then
        return
      end
      local max_line = vim.api.nvim_buf_line_count(buf)
      if max_line < 1 then
        return
      end
      local clamped = math.max(1, math.min(target_line, max_line))
      pcall(vim.api.nvim_win_set_cursor, win, { clamped, 0 })
    end

    local function move_dockyard_cursor(step)
      local win = (ui_state.win_id and vim.api.nvim_win_is_valid(ui_state.win_id)) and ui_state.win_id or nil
      if not win then
        return
      end
      local buf = vim.api.nvim_win_get_buf(win)
      if not vim.api.nvim_buf_is_valid(buf) or (ui_state.buf_id and buf ~= ui_state.buf_id) then
        return
      end
      local lines = sorted_row_lines()
      if #lines == 0 then
        return
      end
      local ok_cur, cursor = pcall(vim.api.nvim_win_get_cursor, win)
      if not ok_cur or not cursor then
        return
      end
      local cur_line = cursor[1]
      local idx = #lines
      if cur_line <= lines[1] then
        idx = 1
      elseif cur_line >= lines[#lines] then
        idx = #lines
      else
        for i = 1, #lines do
          if lines[i] == cur_line then
            idx = i
            break
          elseif i < #lines and cur_line > lines[i] and cur_line < lines[i + 1] then
            idx = ((cur_line - lines[i]) <= (lines[i + 1] - cur_line)) and i or (i + 1)
            break
          end
        end
      end
      local target_idx = math.max(1, math.min(idx + step, #lines))
      set_dockyard_cursor(lines[target_idx])
    end

    navigation.first = function()
      local lines = sorted_row_lines()
      if #lines == 0 then
        return
      end
      set_dockyard_cursor(lines[1])
    end

    navigation.last = function()
      local lines = sorted_row_lines()
      if #lines == 0 then
        return
      end
      set_dockyard_cursor(lines[#lines])
    end

    navigation.down = function()
      move_dockyard_cursor(1)
    end
    navigation.up = function()
      move_dockyard_cursor(-1)
    end

    local function get_upvalue(fn, target_name)
      if type(fn) ~= 'function' then
        return nil
      end
      local i = 1
      while true do
        local name, val = debug.getupvalue(fn, i)
        if not name then
          break
        end
        if name == target_name then
          return val, i
        end
        i = i + 1
      end
      return nil
    end

    local setup_active_view = get_upvalue(ui.open, 'setup_active_view')
    local update_active_view = get_upvalue(ui.open, 'update_active_view')
    local teardown_active_view = get_upvalue(ui.close, 'teardown_active_view')

    -- Track any active bottom sub-view split inside the Right Panel (Detail Panel / Inspect / LogLens)
    local active_popup_close = nil

    local help_state = get_upvalue(help_mod.show, 'state')
    local help_cleanup = get_upvalue(help_mod.show, 'cleanup_ui')
    local help_get_layout = get_upvalue(help_mod.show, 'get_layout')
    local help_apply_spans = get_upvalue(help_mod.show, 'apply_spans')

    local function close_dockyard_subsplits(keep_kind)
      if help_state and help_state.ui and help_state.ui.visible and help_cleanup then
        pcall(help_cleanup)
      end
      if keep_kind ~= 'popup' and type(active_popup_close) == 'function' then
        pcall(active_popup_close)
        active_popup_close = nil
      end
      if keep_kind ~= 'loglens' then
        pcall(function()
          local ll_state = require 'dockyard.core.stream.loglens.state'
          if ll_state.is_open and ll_state.is_open() then
            loglens.close()
          end
        end)
      end
    end

    ---------------------------------------------------------------------------
    -- 1. Dock Main Dockyard UI in the Right Panel (Vertical Split, Never Tab/Float)
    ---------------------------------------------------------------------------
    local function attach_explorer_navigation(buf)
      -- `l`: Expand compose project / image / network, OR open Detail Panel on container / volume
      vim.keymap.set('n', 'l', function()
        local line = vim.api.nvim_win_get_cursor(0)[1]
        local node = ui_state.line_map and ui_state.line_map[line] or nil
        if not node then
          return
        end

        if node.kind == 'compose_project' then
          require('dockyard.ui.views.containers.controller').toggle(node)
          if update_active_view then
            update_active_view(nil)
          end
        elseif node.kind == 'image' and ui_state.current_view == 'images' then
          require('dockyard.ui.views.images.controller').toggle(node)
          if update_active_view then
            update_active_view(nil)
          end
        elseif node.kind == 'network' and ui_state.current_view == 'networks' then
          require('dockyard.ui.views.networks.controller').toggle(node)
          if update_active_view then
            update_active_view(nil)
          end
        elseif node.item then
          require('dockyard.ui.panel').open {
            kind = node.kind,
            item = node.item,
            key = node.key or (node.item and node.item.id),
          }
        end
      end, { buffer = buf, silent = true, nowait = true, desc = 'Expand or Open Detail Panel' })

      -- `h`: Collapse compose project / image / network (climbing to parent if on child container)
      vim.keymap.set('n', 'h', function()
        local line = vim.api.nvim_win_get_cursor(0)[1]
        local node = ui_state.line_map and ui_state.line_map[line] or nil
        if not node then
          return
        end

        if ui_state.current_view == 'containers' or ui_state.current_view == 'compose' then
          local c_state = require 'dockyard.ui.views.containers.state'
          local target_node = node
          local target_line = line
          if node.kind == 'container' then
            for l = line - 1, 1, -1 do
              local prev = ui_state.line_map and ui_state.line_map[l]
              if prev and prev.kind == 'compose_project' then
                target_node = prev
                target_line = l
                break
              end
            end
          end
          if target_node and target_node.kind == 'compose_project' then
            local is_exp = c_state.expanded[target_node.key]
            if is_exp == nil then
              is_exp = true
            end
            if is_exp then
              c_state.expanded[target_node.key] = false
              pcall(vim.api.nvim_win_set_cursor, 0, { target_line, 0 })
              if update_active_view then
                update_active_view(nil)
              end
              return
            end
          end
        elseif ui_state.current_view == 'images' then
          local i_state = require 'dockyard.ui.views.images.state'
          local target_node = node
          local target_line = line
          if node.kind == 'container' then
            for l = line - 1, 1, -1 do
              local prev = ui_state.line_map and ui_state.line_map[l]
              if prev and prev.kind == 'image' then
                target_node = prev
                target_line = l
                break
              end
            end
          end
          if target_node and target_node.kind == 'image' and i_state.expanded[target_node.key] then
            i_state.expanded[target_node.key] = false
            pcall(vim.api.nvim_win_set_cursor, 0, { target_line, 0 })
            if update_active_view then
              update_active_view(nil)
            end
            return
          end
        elseif ui_state.current_view == 'networks' then
          local n_state = require 'dockyard.ui.views.networks.state'
          local target_node = node
          local target_line = line
          if node.kind == 'container' then
            for l = line - 1, 1, -1 do
              local prev = ui_state.line_map and ui_state.line_map[l]
              if prev and prev.kind == 'network' then
                target_node = prev
                target_line = l
                break
              end
            end
          end
          if target_node and target_node.kind == 'network' and n_state.expanded[target_node.key] then
            n_state.expanded[target_node.key] = false
            pcall(vim.api.nvim_win_set_cursor, 0, { target_line, 0 })
            if update_active_view then
              update_active_view(nil)
            end
            return
          end
        end

        -- If nothing to collapse and detail panel is open, close detail panel
        if type(active_popup_close) == 'function' then
          pcall(active_popup_close)
          active_popup_close = nil
        end
      end, { buffer = buf, silent = true, nowait = true, desc = 'Collapse Node' })
    end

    local function open_docked()
      if ui.is_open() then
        vim.api.nvim_set_current_win(ui_state.win_id)
        if update_active_view then
          update_active_view(nil)
        end
        return ui_state.win_id
      end

      local views = require('dockyard.config').options.display.views or { 'containers', 'compose', 'images', 'networks', 'volumes' }
      if #views > 0 and not vim.tbl_contains(views, ui_state.current_view) then
        ui_state.current_view = views[1]
      end

      local ed = (_G.RightPanel and _G.RightPanel.get_editor_win and _G.RightPanel.get_editor_win()) or vim.api.nvim_get_current_win()
      ui_state.prev_win = ed
      -- Use mode = 'full' with tab_id = nil so `ui.resize()` re-renders in-place and `loglens` uses bottom split
      ui_state.mode = 'full'
      ui_state.tab_id = nil
      statusline.reset()

      if ui_state.buf_id == nil or not vim.api.nvim_buf_is_valid(ui_state.buf_id) then
        ui_state.buf_id = ui_utils.create_buf()
      end
      vim.b[ui_state.buf_id].panel_zone = 'right'
      vim.b[ui_state.buf_id].panel_type = 'dockyard'
      vim.bo[ui_state.buf_id].buflisted = false

      if ed and vim.api.nvim_win_is_valid(ed) then
        vim.api.nvim_set_current_win(ed)
      end

      local width = (_G.RightPanel and _G.RightPanel.custom_widths and _G.RightPanel.custom_widths['dockyard'])
        or math.max(60, math.floor(vim.o.columns * 0.48))
      vim.cmd('botright ' .. width .. 'vsplit')
      ui_state.win_id = vim.api.nvim_get_current_win()
      vim.wo[ui_state.win_id].winfixbuf = false
      vim.api.nvim_win_set_buf(ui_state.win_id, ui_state.buf_id)
      ui_utils.apply_win_config(ui_state.win_id, 'full')
      vim.wo[ui_state.win_id].spell = false
      vim.wo[ui_state.win_id].winfixwidth = true
      vim.wo[ui_state.win_id].winfixbuf = false

      statusline.attach(ui_state.win_id)
      local attached_win = ui_state.win_id
      vim.api.nvim_create_autocmd('WinClosed', {
        pattern = tostring(attached_win),
        once = true,
        callback = function()
          vim.schedule(function()
            if ui_state.win_id == attached_win and not vim.api.nvim_win_is_valid(attached_win) then
              statusline.reset()
            end
          end)
        end,
      })

      keymaps.register_global(ui_state.buf_id, {
        close = function()
          if _G.RightPanel and _G.RightPanel.close_all then
            _G.RightPanel.close_all()
            local editor_win = _G.RightPanel.get_editor_win and _G.RightPanel.get_editor_win()
            if editor_win and vim.api.nvim_win_is_valid(editor_win) then
              vim.api.nvim_set_current_win(editor_win)
            end
          else
            ui.close()
          end
        end,
        refresh = ui.refresh,
        next_view = ui.next_view,
        prev_view = ui.prev_view,
        open_help = function()
          help_mod.toggle { buffer = ui_state.buf_id }
        end,
      })

      help_mod.register_command('Commands', {
        { name = 'Dockyard', desc = 'Open Dockyard UI' },
        { name = 'DockyardBuild', desc = 'Build Docker image from current Dockerfile' },
        { name = 'DockyardRun', desc = 'Run Docker Compose services' },
        { name = 'DockyardFiles', desc = "Browse a container's filesystem" },
      }, { buffer = ui_state.buf_id, index = 999 })

      if setup_active_view then
        setup_active_view()
      end
      attach_explorer_navigation(ui_state.buf_id)
      if update_active_view then
        update_active_view(nil, { force_update = true })
      end

      if _G.RightPanel then
        _G.RightPanel.active_mode = 'dockyard'
        if _G.RightPanel.ensure_precedence then
          _G.RightPanel.ensure_precedence()
        end
      end

      return ui_state.win_id
    end

    ui.open = open_docked
    ui.open_full = open_docked

    local orig_next_view = ui.next_view
    local orig_prev_view = ui.prev_view
    ui.next_view = function()
      orig_next_view()
      if ui_state.buf_id and vim.api.nvim_buf_is_valid(ui_state.buf_id) then
        attach_explorer_navigation(ui_state.buf_id)
      end
    end
    ui.prev_view = function()
      orig_prev_view()
      if ui_state.buf_id and vim.api.nvim_buf_is_valid(ui_state.buf_id) then
        attach_explorer_navigation(ui_state.buf_id)
      end
    end

    ui.close = function()
      close_dockyard_subsplits()
      if ui_state.win_id and vim.api.nvim_win_is_valid(ui_state.win_id) then
        pcall(vim.api.nvim_win_close, ui_state.win_id, true)
      end
      ui_state.win_id = nil
      ui_state.tab_id = nil
      statusline.reset()

      if teardown_active_view then
        teardown_active_view()
      end
      if ui_state.buf_id ~= nil and vim.api.nvim_buf_is_valid(ui_state.buf_id) then
        pcall(keymaps.unregister_global, ui_state.buf_id)
      end

      local ed = (_G.RightPanel and _G.RightPanel.get_editor_win and _G.RightPanel.get_editor_win()) or ui_state.prev_win
      ui_state.prev_win = nil
      if ed and vim.api.nvim_win_is_valid(ed) then
        pcall(vim.api.nvim_set_current_win, ed)
      end
    end

    ---------------------------------------------------------------------------
    -- 2. Confine Popups (Detail Panel `p`, Hover Inspect `K`, Log Entry) to Right Panel Split
    ---------------------------------------------------------------------------
    local popup_seq = 0
    popup_mod.create = function(popts)
      popts = popts or {}
      popup_seq = popup_seq + 1

      local state = {
        id = popup_seq,
        title = popts.title or ' Detail ',
        footer = popts.footer,
        view = popts.view or 'default',
        buf = nil,
        win = nil,
        source_win = nil,
        ns = vim.api.nvim_create_namespace('dockyard.popup.docked.' .. tostring(popup_seq)),
        on_resize = popts.on_resize,
        on_close = popts.on_close,
      }

      local function is_open()
        return state.win ~= nil and vim.api.nvim_win_is_valid(state.win)
      end

      local function ensure_buf()
        if state.buf ~= nil and vim.api.nvim_buf_is_valid(state.buf) then
          return state.buf
        end

        state.buf = vim.api.nvim_create_buf(false, true)
        vim.bo[state.buf].buftype = 'nofile'
        vim.bo[state.buf].bufhidden = 'wipe'
        vim.bo[state.buf].swapfile = false
        vim.bo[state.buf].buflisted = false
        vim.bo[state.buf].modifiable = false
        vim.bo[state.buf].filetype = 'dockyard_popup'
        vim.b[state.buf].panel_zone = 'right'
        vim.b[state.buf].panel_type = 'dockyard'
        vim.b[state.buf].dockyard_popup_view = state.view

        vim.api.nvim_create_autocmd('BufWipeout', {
          buffer = state.buf,
          once = true,
          callback = function()
            state.buf = nil
            state.win = nil
            if type(state.on_close) == 'function' then
              state.on_close()
            end
          end,
        })

        return state.buf
      end

      local function close()
        if is_open() then
          pcall(vim.api.nvim_win_close, state.win, true)
        end
        state.win = nil
        if active_popup_close == close then
          active_popup_close = nil
        end
        if type(state.on_close) == 'function' then
          state.on_close()
        end
        if state.source_win and vim.api.nvim_win_is_valid(state.source_win) then
          pcall(vim.api.nvim_set_current_win, state.source_win)
        elseif ui_state.win_id and vim.api.nvim_win_is_valid(ui_state.win_id) then
          pcall(vim.api.nvim_set_current_win, ui_state.win_id)
        end
      end

      local function recenter()
        if not is_open() then
          return
        end
        if type(state.on_resize) == 'function' then
          state.on_resize(state.win, state.buf)
        end
      end

      local function open(open_opts)
        open_opts = open_opts or {}
        local source_win = vim.api.nvim_get_current_win()
        if not is_open() then
          state.source_win = source_win
        end
        if open_opts.title ~= nil then
          state.title = open_opts.title
        end
        if open_opts.footer ~= nil then
          state.footer = open_opts.footer
        end
        if open_opts.view ~= nil then
          state.view = open_opts.view
        end

        local buf = ensure_buf()
        vim.b[buf].dockyard_popup_view = state.view
        vim.b[buf].panel_zone = 'right'
        vim.b[buf].panel_type = 'dockyard'

        if not is_open() then
          if active_popup_close and active_popup_close ~= close then
            pcall(active_popup_close)
          end

          if state.view == 'entry' and source_win and vim.api.nvim_win_is_valid(source_win) then
            -- LogLens is already the bottom split of the Right Panel; open the log entry detail card
            -- directly over the LogLens split so we never stack 3 splits vertically
            local win_pos = vim.api.nvim_win_get_position(source_win)
            local w = math.max(30, vim.api.nvim_win_get_width(source_win) - 2)
            local h = math.max(8, vim.api.nvim_win_get_height(source_win) - 2)
            state.win = vim.api.nvim_open_win(buf, true, {
              relative = 'editor',
              row = win_pos[1],
              col = win_pos[2],
              width = w,
              height = h,
              style = 'minimal',
              border = 'rounded',
              title = ' ' .. vim.trim(state.title or 'Log Entry') .. ' ',
              title_pos = 'left',
              footer = ' q / h / Esc: back to logs ',
              footer_pos = 'right',
              zindex = 220,
            })
            vim.wo[state.win].wrap = true
            vim.wo[state.win].linebreak = true
            vim.wo[state.win].breakindent = true
            vim.wo[state.win].spell = false
            vim.wo[state.win].cursorline = true
            active_popup_close = close
            local map_opts = { buffer = buf, nowait = true, silent = true }
            vim.keymap.set('n', 'q', close, map_opts)
            vim.keymap.set('n', 'h', close, map_opts)
            vim.keymap.set('n', '<Esc>', close, map_opts)
            return state.win, buf
          end

          close_dockyard_subsplits 'popup'

          local anchor_win = (ui_state.win_id and vim.api.nvim_win_is_valid(ui_state.win_id)) and ui_state.win_id or source_win
          vim.api.nvim_win_call(anchor_win, function()
            local h = math.max(10, math.floor(vim.api.nvim_win_get_height(anchor_win) * 0.46))
            vim.cmd(string.format('belowright %dsplit', h))
            state.win = vim.api.nvim_get_current_win()
          end)
          vim.wo[state.win].winfixbuf = false
          vim.api.nvim_win_set_buf(state.win, buf)
        end

        active_popup_close = close
        vim.api.nvim_set_current_win(state.win)
        vim.wo[state.win].number = false
        vim.wo[state.win].relativenumber = false
        vim.wo[state.win].signcolumn = 'no'
        vim.wo[state.win].spell = false
        vim.wo[state.win].wrap = true
        vim.wo[state.win].linebreak = true
        vim.wo[state.win].breakindent = true
        vim.wo[state.win].cursorline = true
        vim.wo[state.win].winfixheight = true
        vim.wo[state.win].winfixwidth = true
        vim.wo[state.win].winfixbuf = false

        local wb_title = vim.trim(state.title or 'Detail')
        local wb_footer = state.footer and ('  %#Comment#' .. vim.trim(state.footer) .. '  (q: close)%*') or '  %#Comment#(q: close)%*'
        vim.wo[state.win].winbar = ' %#Title#' .. wb_title .. '%*' .. wb_footer

        statusline.inherit(state.win, source_win)
        local map_opts = { buffer = buf, nowait = true, silent = true }
        vim.keymap.set('n', 'q', close, map_opts)
        vim.keymap.set('n', 'h', close, map_opts)
        vim.keymap.set('n', '<Esc>', close, map_opts)
        return state.win, buf
      end

      local function set_content(lines, spans)
        if state.buf == nil or not vim.api.nvim_buf_is_valid(state.buf) then
          return
        end
        vim.bo[state.buf].modifiable = true
        vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines or {})
        vim.bo[state.buf].modifiable = false

        vim.api.nvim_buf_clear_namespace(state.buf, state.ns, 0, -1)
        for _, span in ipairs(spans or {}) do
          local line = vim.api.nvim_buf_get_lines(state.buf, span.line, span.line + 1, false)[1] or ''
          local line_len = #line
          local start_col = math.max(0, math.min(span.start_col or 0, line_len))
          local end_col = span.end_col == nil or span.end_col < 0 and line_len or math.max(start_col, math.min(span.end_col, line_len))
          if end_col > start_col and span.hl_group then
            vim.api.nvim_buf_set_extmark(state.buf, state.ns, span.line, start_col, {
              end_row = span.line,
              end_col = end_col,
              hl_group = span.hl_group,
            })
          end
        end
      end

      return {
        open = open,
        close = close,
        recenter = recenter,
        set_content = set_content,
        is_open = is_open,
        get_win = function()
          return state.win
        end,
        get_buf = function()
          return state.buf
        end,
        get_width = function()
          if is_open() then
            return vim.api.nvim_win_get_width(state.win)
          end
          if ui_state.win_id and vim.api.nvim_win_is_valid(ui_state.win_id) then
            return vim.api.nvim_win_get_width(ui_state.win_id)
          end
          return math.max(60, math.floor(vim.o.columns * 0.48))
        end,
      }
    end

    ---------------------------------------------------------------------------
    -- 3. Confine Help Strip (`g?`) to the Bottom of the Right Panel
    ---------------------------------------------------------------------------
    if help_state and help_cleanup and help_get_layout and help_apply_spans then
      help_mod.show = function(hopts)
        hopts = hopts or {}
        local bufnr = hopts.buffer or vim.api.nvim_get_current_buf()
        if help_state.ui.visible then
          help_cleanup()
          return
        end

        local anchor_win = (ui_state.win_id and vim.api.nvim_win_is_valid(ui_state.win_id)) and ui_state.win_id or vim.api.nvim_get_current_win()
        local win_pos = vim.api.nvim_win_get_position(anchor_win)
        local max_width = vim.api.nvim_win_get_width(anchor_win)
        local layout = help_get_layout(bufnr, max_width)
        if layout.height == 0 then
          return
        end

        local buf_id = vim.api.nvim_create_buf(false, true)
        vim.bo[buf_id].buftype = 'nofile'
        vim.bo[buf_id].bufhidden = 'wipe'
        vim.bo[buf_id].swapfile = false
        vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, layout.lines)
        vim.bo[buf_id].modifiable = false
        help_apply_spans(buf_id, layout.spans)

        local height = math.min(layout.height, math.max(6, vim.o.lines - 4))
        local win_id = vim.api.nvim_open_win(buf_id, false, {
          relative = 'editor',
          width = max_width,
          height = height,
          col = win_pos[2],
          row = math.max(0, vim.o.lines - height - 2),
          style = 'minimal',
          border = 'rounded',
          title = ' Dockyard Keymaps ',
          title_pos = 'center',
          zindex = 250,
          focusable = false,
        })
        vim.wo[win_id].winhighlight = 'Normal:NormalFloat'

        help_state.ui.visible = true
        help_state.ui.win_id = win_id
        help_state.ui.buf_id = buf_id
        help_state.ui.target_bufnr = bufnr

        local on_key_ns = vim.api.nvim_create_namespace 'dockyard_help_onkey'
        vim.on_key(function()
          if not help_state.ui.visible then
            return
          end
          vim.schedule(help_cleanup)
        end, on_key_ns)
        help_state.ui.on_key_ns = on_key_ns
      end
    end

    ---------------------------------------------------------------------------
    -- 4. Confine LogLens (`L`) to Bottom Split Inside the Right Panel
    ---------------------------------------------------------------------------
    local orig_create_fullscreen = loglens_win.create_window_fullscreen
    local function create_right_panel_log_split(buf, state_arg)
      close_dockyard_subsplits 'loglens'
      vim.b[buf].panel_zone = 'right'
      vim.b[buf].panel_type = 'dockyard'
      vim.bo[buf].buflisted = false

      local target_win = (state_arg and state_arg.win_id and vim.api.nvim_win_is_valid(state_arg.win_id)) and state_arg.win_id
        or (ui_state.win_id and vim.api.nvim_win_is_valid(ui_state.win_id) and ui_state.win_id)
        or vim.api.nvim_get_current_win()

      local win = orig_create_fullscreen(buf, { win_id = target_win })
      if win and vim.api.nvim_win_is_valid(win) then
        vim.wo[win].wrap = true
        vim.wo[win].linebreak = true
        vim.wo[win].breakindent = true
        vim.wo[win].spell = false
        vim.wo[win].winfixwidth = true
        vim.wo[win].winfixbuf = true
      end
      return win
    end
    loglens_win.create_window_fullscreen = create_right_panel_log_split
    loglens_win.create_window_split = function(buf)
      return create_right_panel_log_split(buf, ui_state)
    end
    loglens_win.create_window_floating = function(buf)
      return create_right_panel_log_split(buf, ui_state)
    end

    local orig_loglens_close = loglens.close
    loglens.close = function()
      orig_loglens_close()
      if ui_state.win_id and vim.api.nvim_win_is_valid(ui_state.win_id) then
        pcall(vim.api.nvim_set_current_win, ui_state.win_id)
      end
    end

    ---------------------------------------------------------------------------
    -- 5. Container Filesystem Browser (`f`) — Stay in Right Panel & Open Files in Left Editor
    ---------------------------------------------------------------------------
    local orig_files_open = files_browser.open
    local orig_files_attach = get_upvalue(orig_files_open, 'attach_keymaps')
    local orig_files_close = orig_files_attach and get_upvalue(orig_files_attach, 'close') or nil

    files_browser.open = function(container, path, fopts)
      fopts = fopts or {}
      local target_win = fopts.win or (ui_state.win_id and vim.api.nvim_win_is_valid(ui_state.win_id) and ui_state.win_id) or vim.api.nvim_get_current_win()
      if target_win and vim.api.nvim_win_is_valid(target_win) then
        vim.wo[target_win].winfixbuf = false
      end
      local buf = orig_files_open(container, path, { win = target_win })
      if buf and vim.api.nvim_buf_is_valid(buf) then
        vim.b[buf].panel_zone = 'right'
        vim.b[buf].panel_type = 'dockyard'
        vim.bo[buf].buflisted = false
        if orig_files_close then
          vim.keymap.set('n', 'q', function()
            local w = vim.api.nvim_get_current_win()
            if vim.api.nvim_win_is_valid(w) then
              vim.wo[w].winfixbuf = false
            end
            orig_files_close()
            if vim.api.nvim_win_is_valid(w) then
              vim.wo[w].winfixwidth = true
              vim.wo[w].cursorline = true
            end
          end, { buffer = buf, silent = true, nowait = true, desc = 'Close Container Filesystem Browser' })
        end
      end
      if target_win and vim.api.nvim_win_is_valid(target_win) then
        vim.wo[target_win].winfixbuf = false
        vim.wo[target_win].winfixwidth = true
        vim.wo[target_win].cursorline = true
      end
      return buf
    end

    -- When pressing `l` or `<CR>` on a file inside a container, open it in the Left Code Editor!
    files_browser.open_file = function(container, path)
      local core = require 'dockyard.files.core'
      core.read(container, path, function(res)
        if not res.ok then
          vim.notify('[dockyard] ' .. (res.error or 'read failed'), vim.log.levels.ERROR)
          return
        end
        local name = ('dockyard://%s%s'):format(container, path)
        local buf = vim.fn.bufnr(name)
        if buf == -1 then
          buf = vim.api.nvim_create_buf(true, false)
          vim.api.nvim_buf_set_name(buf, name)
          vim.bo[buf].buftype = 'acwrite'
          vim.bo[buf].bufhidden = 'wipe'
          vim.bo[buf].swapfile = false

          vim.api.nvim_create_autocmd('BufWriteCmd', {
            buffer = buf,
            callback = function()
              local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
              core.write(container, path, lines, function(w)
                if not w.ok then
                  vim.notify('[dockyard] ' .. (w.error or 'write failed'), vim.log.levels.ERROR)
                  return
                end
                vim.bo[buf].modified = false
                vim.notify('[dockyard] Saved ' .. container .. ':' .. path, vim.log.levels.INFO)
              end)
            end,
          })
        end
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, res.lines)
        vim.bo[buf].modified = false
        local ft = vim.filetype.match { filename = path }
        if ft then
          vim.bo[buf].filetype = ft
        end

        local ed = (_G.RightPanel and _G.RightPanel.get_editor_win and _G.RightPanel.get_editor_win()) or nil
        if ed and vim.api.nvim_win_is_valid(ed) then
          vim.api.nvim_set_current_win(ed)
          vim.wo[ed].winfixbuf = false
          vim.api.nvim_win_set_buf(ed, buf)
        else
          vim.cmd 'topleft vsplit'
          local new_win = vim.api.nvim_get_current_win()
          vim.wo[new_win].winfixbuf = false
          vim.wo[new_win].winfixwidth = false
          vim.wo[new_win].winfixheight = false
          vim.api.nvim_set_current_buf(buf)
          if _G.RightPanel and _G.RightPanel.ensure_precedence then
            _G.RightPanel.ensure_precedence()
          end
        end
      end)
    end

    ---------------------------------------------------------------------------
    -- 6. Container Shell Terminal (`T`) via Snacks.terminal in Bottom Panel
    ---------------------------------------------------------------------------
    term_view.open = function(container_id, shell)
      if not container_id or container_id == '' then
        vim.notify('Dockyard: no container selected', vim.log.levels.WARN)
        return
      end
      shell = shell or 'sh'
      local cmd = string.format('docker exec -it %s %s', container_id, shell)

      local ed = (_G.RightPanel and _G.RightPanel.get_editor_win and _G.RightPanel.get_editor_win()) or nil
      if ed and vim.api.nvim_win_is_valid(ed) then
        vim.api.nvim_set_current_win(ed)
      end

      Snacks.terminal.open(cmd, {
        win = {
          position = 'bottom',
          relative = ed and 'win' or 'editor',
          win = ed,
          height = 0.38,
          wo = { winbar = '', winfixheight = true, winfixbuf = true },
          on_buf = function(t)
            vim.b[t.buf].panel_zone = 'bottom'
            vim.b[t.buf].panel_type = 'terminal'
          end,
        },
      })
      vim.schedule(function()
        if _G.RightPanel and _G.RightPanel.ensure_precedence then
          _G.RightPanel.ensure_precedence()
        end
      end)
    end
  end,
}
