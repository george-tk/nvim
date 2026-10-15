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
    end

    setup_dock_highlights()
    vim.api.nvim_create_autocmd('ColorScheme', {
      callback = setup_dock_highlights,
    })

    require('utils.buffer-ring').setup()
    require('utils.terminal-tracker').setup()
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

    -- Transparent statusline theme: mode-colored active blocks with black text, normal text color elsewhere
    local function get_theme()
      local ok, ctp = pcall(require, 'catppuccin.palettes')
      if not ok then
        return 'auto'
      end
      local C = ctp.get_palette 'mocha'
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
              return require('utils.buffer-ring').lualine_component()
            end,
            padding = { left = 1, right = 0 },
          },
        },

        -- Right-side sections: Terminal Instances tracker & Active database
        lualine_x = {
          {
            function()
              return require('utils.terminal-tracker').lualine_component()
            end,
            padding = { left = 0, right = 0 },
          },
        },
        lualine_y = {
          {
            function()
              local cur_buf = get_active_editor_buf()
              local ft = vim.bo[cur_buf].filetype
              local bname = vim.api.nvim_buf_get_name(cur_buf)
              local is_db = ft == 'sql'
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

                local db_name = nil
                local is_ro = false

                -- 1. Query sqmeow authoritative execution target for this buffer
                local ok_conn, conn_api = pcall(require, 'sqmeow.api.connection')
                if ok_conn and conn_api and conn_api.target then
                  local target = conn_api.target(cur_buf)
                  if target and target.name then
                    db_name = target.name
                    is_ro = target.read_only == true
                  end
                end

                -- 2. Buffer-local connection bindings
                if not db_name or db_name == '' then
                  db_name = vim.b[cur_buf].sqmeow_connection or vim.b[cur_buf].db_name
                end

                -- 3. DatabaseUtils active db / current db
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

                -- 4. Result buffer fallback
                if not db_name or db_name == '' then
                  local ok_st, st = pcall(require, 'sqmeow.core.state')
                  if ok_st and st then
                    if st.call and st.call.conn_id and st.connections and st.connections[st.call.conn_id] then
                      local c = st.connections[st.call.conn_id]
                      db_name = c.name
                      is_ro = c.read_only == true
                    elseif st.current and st.connections and st.connections[st.current] then
                      local c = st.connections[st.current]
                      db_name = c.name
                      is_ro = c.read_only == true
                    end
                  end
                end

                if db_name and db_name ~= '' then
                  if not is_ro then
                    local ok_st, st = pcall(require, 'sqmeow.core.state')
                    if ok_st and st and st.connection_by_name then
                      local c = st.connection_by_name(db_name)
                      if c and c.read_only then
                        is_ro = true
                      end
                    end
                  end

                  local display = '󰆼 ' .. db_name
                  if is_ro then
                    display = display .. ' 󰌾'
                  end
                  return display
                end

                if vim.b[cur_buf].is_preview_buffer or bname:match '%[Preview: ' then
                  return '󰆼 preview'
                end
                if bname:match '%[Alter: ' then
                  return '󰆼 alter'
                end
                if bname:match '%[Routine: ' then
                  return '󰆼 routine'
                end
                return '󰆼 sql'
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
