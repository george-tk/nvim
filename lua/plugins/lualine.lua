return {
  'nvim-lualine/lualine.nvim',
  event = 'BufWinEnter', -- or 'VeryLazy' if you prefer even later
  -- Load devicons only if/when lualine renders with icons
  dependencies = {
    { 'nvim-tree/nvim-web-devicons', lazy = true },
  },

  -- Initialize buffer-ring and terminal-tracker
  init = function()
    local function setup_dock_highlights()
      local ok, ctp = pcall(require, 'catppuccin.palettes')
      local C = ok and ctp.get_palette 'mocha' or {}
      local blue = C.blue or '#89b4fa'
      local base = C.base or '#1e1e2e'
      local text = C.text or '#cdd6f4'

      vim.api.nvim_set_hl(0, 'BufferRingActive', { bg = blue, fg = base, bold = true, default = true })
      vim.api.nvim_set_hl(0, 'BufferRingInactive', { bg = 'NONE', fg = text, default = true })
      vim.api.nvim_set_hl(0, 'TerminalTrackerActive', { bg = blue, fg = base, bold = true, default = true })
      vim.api.nvim_set_hl(0, 'TerminalTrackerInactive', { bg = 'NONE', fg = text, default = true })
      local green = C.green or '#a6e3a1'
      vim.api.nvim_set_hl(0, 'TerminalTrackerRunning', { bg = 'NONE', fg = green, bold = true, default = true })
    end

    setup_dock_highlights()
    vim.api.nvim_create_autocmd('ColorScheme', {
      callback = setup_dock_highlights,
    })

    require('utils.buffer-ring').setup()
    require('utils.terminal-tracker').setup()

    local macro_group = vim.api.nvim_create_augroup('LualineMacroRefresh', { clear = true })
    vim.api.nvim_create_autocmd('RecordingEnter', {
      group = macro_group,
      callback = function()
        local ok_l, lualine = pcall(require, 'lualine')
        if ok_l then
          lualine.refresh { place = { 'statusline' } }
        end
      end,
    })
    vim.api.nvim_create_autocmd('RecordingLeave', {
      group = macro_group,
      callback = function()
        vim.schedule(function()
          local ok_l, lualine = pcall(require, 'lualine')
          if ok_l then
            lualine.refresh { place = { 'statusline' } }
          end
        end)
      end,
    })
  end,

  opts = function()
    -- Helpers
    -- Centered mode with fixed width (10 columns) to prevent mode-switch jitter
    local function center_mode(str)
      local clean = vim.trim(str or '')
      local width = 10
      local len = vim.fn.strdisplaywidth(clean)
      if len >= width then
        return clean
      end
      local total_pad = width - len
      local left_pad = math.floor(total_pad / 2)
      local right_pad = total_pad - left_pad
      return string.rep(' ', left_pad) .. clean .. string.rep(' ', right_pad)
    end

    local cached_workspace_branch = ''

    local function get_workspace_branch()
      local b_head = vim.b.gitsigns_head
      if b_head and b_head ~= '' then
        cached_workspace_branch = b_head
        return cached_workspace_branch
      end

      local ok_gs, gs = pcall(require, 'gitsigns')
      if ok_gs and gs.get_head then
        local head = gs.get_head()
        if head and head ~= '' then
          cached_workspace_branch = head
          return cached_workspace_branch
        end
      end

      return cached_workspace_branch
    end

    vim.api.nvim_create_autocmd('DirChanged', {
      callback = function()
        cached_workspace_branch = ''
      end,
    })

    -- Resolve active editor buffer (locks to editor file so tool panels don't jitter the right side)
    local function get_active_editor_buf()
      local ed_win = nil
      if _G.RightPanel and _G.RightPanel.get_editor_win then
        ed_win = _G.RightPanel.get_editor_win()
      end
      if ed_win and vim.api.nvim_win_is_valid(ed_win) then
        local b = vim.api.nvim_win_get_buf(ed_win)
        if vim.api.nvim_buf_is_valid(b) then
          return b
        end
      end

      local ok_ring, ring = pcall(require, 'utils.buffer-ring')
      if ok_ring and ring and ring.is_qualifying then
        for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
          if vim.api.nvim_win_is_valid(w) then
            local b = vim.api.nvim_win_get_buf(w)
            if ring.is_qualifying(b) then
              return b
            end
          end
        end
      end

      return vim.api.nvim_get_current_buf()
    end

    local last_main_zone = 'editor'

    local function get_focused_zone()
      local ok_layout, layout = pcall(require, 'utils.layout')
      if ok_layout and layout.get_win_info then
        local info = layout.get_win_info(vim.api.nvim_get_current_win())
        if info.zone == 'bottom' or info.zone == 'right' or info.zone == 'editor' then
          last_main_zone = info.zone
          return info.zone
        end
      end
      return last_main_zone
    end

    vim.api.nvim_create_autocmd({ 'WinEnter', 'BufEnter' }, {
      callback = function()
        local prev = last_main_zone
        local now_zone = get_focused_zone()
        if now_zone ~= prev or now_zone == 'right' then
          local ok_l, lualine = pcall(require, 'lualine')
          if ok_l then
            lualine.refresh { place = { 'statusline' } }
          end
        end
      end,
    })

    local ok_ctp, ctp = pcall(require, 'catppuccin.palettes')
    local C = ok_ctp and ctp.get_palette 'mocha' or {}
    local red = C.red or '#f38ba9'

    -- Transparent statusline theme: mode-colored active blocks with black text, normal text color elsewhere
    local function get_theme()
      if not ok_ctp then
        return 'auto'
      end
      local function make_mode(accent)
        return {
          a = { bg = accent, fg = C.base, gui = 'bold' },
          b = { bg = 'NONE', fg = C.text },
          c = { bg = 'NONE', fg = C.text },
          x = { bg = 'NONE', fg = C.text },
          y = { bg = 'NONE', fg = C.text },
          z = { bg = 'NONE', fg = C.text },
        }
      end
      return {
        normal = make_mode(C.blue),
        insert = make_mode(C.green),
        terminal = make_mode(C.green),
        command = make_mode(C.peach),
        visual = make_mode(C.mauve),
        replace = make_mode(C.red),
        inactive = {
          a = { bg = 'NONE', fg = C.surface1, gui = 'bold' },
          b = { bg = 'NONE', fg = C.surface1 },
          c = { bg = 'NONE', fg = C.surface1 },
          x = { bg = 'NONE', fg = C.surface1 },
          y = { bg = 'NONE', fg = C.surface1 },
          z = { bg = 'NONE', fg = C.surface1 },
        },
      }
    end

    return {
      options = {
        theme = get_theme(),
        component_separators = { left = '', right = '' },
        section_separators = { left = '', right = '' },
        -- If you don’t need icons, set to false and delete the devicons dep
        icons_enabled = true,
        globalstatus = true,
        -- Avoid doing work when the UI is tiny
        disabled_filetypes = {
          statusline = { 'alpha', 'starter', 'neo-tree', 'TelescopePrompt' },
        },
        -- Only enable lualine when terminal has enough columns
        refresh = {
          statusline = 500, -- default 1000; lower if you want snappier updates
        },
      },

      sections = {
        lualine_a = {
          {
            'mode',
            fmt = center_mode,
            padding = { left = 0, right = 0 },
          },
        },
        lualine_b = {
          {
            get_workspace_branch,
            icon = '󰊢',
            cond = function()
              return get_workspace_branch() ~= ''
            end,
          },
        },
        lualine_c = {
          {
            function()
              local zone = get_focused_zone()
              if zone == 'bottom' then
                return require('utils.terminal-tracker').lualine_component()
              elseif zone == 'right' then
                local ok_layout, layout = pcall(require, 'utils.layout')
                if ok_layout and layout.RightPanel and layout.RightPanel.lualine_component then
                  return layout.RightPanel.lualine_component()
                end
              end
              return require('utils.buffer-ring').lualine_component()
            end,
            padding = { left = 0, right = 0 },
          },
        },

        -- Right-side sections: Active column (in SQL result grid) / Active macro / database + telemetry / filetype
        lualine_x = {
          {
            function()
              local ok_view, view = pcall(require, 'sqmeow.api.view')
              if ok_view and view and view.column then
                return view.column()
              end
              return ''
            end,
            cond = function()
              if vim.fn.reg_recording() ~= '' then
                return false
              end
              local fb = vim.api.nvim_get_current_buf()
              if not fb or not vim.api.nvim_buf_is_valid(fb) then
                return false
              end
              local ft = vim.bo[fb].filetype
              local name = vim.api.nvim_buf_get_name(fb)
              return ft == 'sqmeow-result' or ft == 'dbout' or name:find 'sqmeow://result' ~= nil
            end,
            color = { fg = C.subtext1 or '#bac2de' },
          },
        },
        lualine_y = {
          -- Active macro recording indicator (takes priority over database & filetype)
          {
            function()
              return '● @' .. vim.fn.reg_recording()
            end,
            cond = function()
              return vim.fn.reg_recording() ~= ''
            end,
            color = { fg = red, gui = 'bold' },
          },
          {
            function()
              local fb = vim.api.nvim_get_current_buf()
              local fb_ft = (fb and vim.api.nvim_buf_is_valid(fb)) and vim.bo[fb].filetype or ''
              local fb_name = (fb and vim.api.nvim_buf_is_valid(fb)) and vim.api.nvim_buf_get_name(fb) or ''
              local in_grid = fb_ft == 'sqmeow-result' or fb_ft == 'dbout' or fb_name:find 'sqmeow://result' ~= nil

              local cur_buf = get_active_editor_buf()
              local target_buf = in_grid and fb or cur_buf
              local ft = vim.bo[cur_buf].filetype
              local bname = vim.api.nvim_buf_get_name(cur_buf)

              local ok_view, view = pcall(require, 'sqmeow.api.view')
              local info = (ok_view and view and view.status) and view.status(target_buf) or nil

              local is_db = info ~= nil
                or in_grid
                or ft == 'sql'
                or ft == 'mysql'
                or ft == 'plsql'
                or ft == 'surql'
                or ft == 'cql'
                or ft == 'sqmeow-result'
                or ft == 'dbout'
                or vim.b[cur_buf].sqmeow_connection
                or vim.b[cur_buf].db_name
                or vim.b[cur_buf].is_preview_buffer
                or bname:match '%[Preview: '
                or bname:match '%[Alter: '
                or bname:match '%[Routine: '
                or bname:find 'sqmeow://'

              if is_db then
                local db_utils = _G.DatabaseUtils
                if not db_utils then
                  local ok_u, u = pcall(require, 'utils.database')
                  if ok_u then
                    db_utils = u
                  end
                end

                local db_name = (info and info.connection) or vim.b[cur_buf].sqmeow_connection or vim.b[cur_buf].db_name
                local is_ro = (info and info.read_only) or false

                if not db_name or db_name == '' then
                  if db_utils and db_utils.get_active_db then
                    local _, dname = db_utils.get_active_db(cur_buf)
                    db_name = dname
                  end
                end
                if not db_name or db_name == '' then
                  if db_utils and db_utils.current_db_name then
                    db_name = db_utils.current_db_name
                  end
                end

                if not is_ro and db_name and db_name ~= '' then
                  local ok_st, st = pcall(require, 'sqmeow.core.state')
                  if ok_st and st and st.connection_by_name then
                    local c = st.connection_by_name(db_name)
                    if c and c.read_only then
                      is_ro = true
                    end
                  end
                end

                -- Format query telemetry from upstream `sqmeow.api.view.status()`
                local telemetry = ''
                if info and info.state then
                  if info.state == 'executing' then
                    telemetry = ' ·  running…'
                  elseif info.state == 'error' then
                    telemetry = ' ·  error'
                  elseif info.state == 'cancelled' then
                    telemetry = ' · cancelled'
                  elseif info.state == 'done' then
                    local parts = {}
                    local plus = info.truncated and '+' or ''
                    if info.view_rows ~= nil then
                      table.insert(parts, string.format('%d/%d%s rows', info.view_rows, info.rows or 0, plus))
                    elseif info.rows ~= nil then
                      local plural = (info.rows == 1 and not info.truncated) and '' or 's'
                      table.insert(parts, string.format('%d%s row%s', info.rows, plus, plural))
                    elseif info.affected ~= nil then
                      table.insert(parts, string.format('%d affected', info.affected))
                    else
                      table.insert(parts, '0 rows')
                    end

                    if info.elapsed and info.elapsed ~= '' then
                      table.insert(parts, info.elapsed)
                    end
                    if info.total_pages and info.total_pages > 1 then
                      table.insert(parts, string.format('p%d/%d', info.page or 1, info.total_pages))
                    end
                    if info.filtered then
                      table.insert(parts, '󰈲')
                    end
                    if info.staged_changes and info.staged_changes > 0 then
                      table.insert(parts, '●')
                    end

                    if #parts > 0 then
                      telemetry = ' · ' .. table.concat(parts, ' · ')
                    end
                  end
                end

                local label = (db_name and db_name ~= '') and db_name
                  or (info and info.role ~= 'query' and info.role)
                  or (vim.b[cur_buf].is_preview_buffer and 'preview')
                  or 'sql'

                local display = '󰆼 ' .. label
                if is_ro then
                  display = display .. ' 󰌾'
                end
                return display .. telemetry
              end

              if not ft or ft == '' then
                return '󰈔 none'
              end
              local ok_devicons, devicons = pcall(require, 'nvim-web-devicons')
              local icon = '󰈔'
              if ok_devicons and devicons.get_icon_by_filetype then
                local i = devicons.get_icon_by_filetype(ft, { default = true })
                if i then
                  icon = i
                end
              end
              return icon .. ' ' .. ft
            end,
            cond = function()
              return vim.fn.reg_recording() == ''
            end,
          },
        },
        lualine_z = {},
      },

      -- Don’t render tabline/winbar unless you need them
      tabline = nil,
      winbar = nil,
      inactive_winbar = nil,
      extensions = { 'quickfix', 'man' }, -- load small integrations when those filetypes open
    }
  end,
}
