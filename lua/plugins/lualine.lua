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
      local C = ok and ctp.get_palette('mocha') or {}
      local blue = C.blue or '#89b4fa'
      local base = C.base or '#1e1e2e'

      vim.api.nvim_set_hl(0, 'BufferRingActive', { bg = blue, fg = base, bold = true, default = true })
      vim.api.nvim_set_hl(0, 'BufferRingInactive', { bg = 'NONE', fg = blue, default = true })
      vim.api.nvim_set_hl(0, 'TerminalTrackerActive', { bg = blue, fg = base, bold = true, default = true })
      vim.api.nvim_set_hl(0, 'TerminalTrackerInactive', { bg = 'NONE', fg = blue, default = true })
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

    -- Transparent statusline theme: mode-colored active blocks with black text, mode-colored inactive text
    local function get_theme()
      local ok, ctp = pcall(require, 'catppuccin.palettes')
      if not ok then return 'auto' end
      local C = ctp.get_palette('mocha')
      local function make_mode(accent)
        return {
          a = { bg = accent, fg = C.base, gui = 'bold' },
          b = { bg = 'NONE', fg = accent },
          c = { bg = 'NONE', fg = accent },
          x = { bg = 'NONE', fg = accent },
          y = { bg = 'NONE', fg = accent },
          z = { bg = 'NONE', fg = accent },
        }
      end
      return {
        normal = {
          a = { bg = C.blue, fg = C.base, gui = 'bold' },
          b = { bg = 'NONE', fg = C.blue },
          c = { bg = 'NONE', fg = C.blue },
          x = { bg = 'NONE', fg = C.blue },
          y = { bg = 'NONE', fg = C.blue },
          z = { bg = 'NONE', fg = C.blue },
        },
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
            padding = { left = 0, right = 0 },
          },
        },

        -- Right-side sections: Terminal Instances tracker & Active database
        lualine_x = {
          {
            function()
              return require('utils.terminal-tracker').lualine_component()
            end,
            padding = { left = 0, right = 1 },
          },
          {
            function()
              local cur_buf = get_active_editor_buf()
              local db_name = vim.b[cur_buf].db_name
              if not db_name and _G.DatabaseUtils and _G.DatabaseUtils.current_db_name then
                db_name = _G.DatabaseUtils.current_db_name
              end
              return db_name and ('󰆼 ' .. db_name) or ''
            end,
            cond = function()
              local cur_buf = get_active_editor_buf()
              local ft = vim.bo[cur_buf].filetype
              return ft == 'sql' or ft == 'mysql' or ft == 'plsql'
            end,
            color = { fg = '#fab387', gui = 'bold' },
          },
        },
        lualine_y = {
          {
            function()
              local cur_buf = get_active_editor_buf()
              local bname = vim.api.nvim_buf_get_name(cur_buf)
              if vim.b[cur_buf].is_preview_buffer or bname:match('%[Preview: ') then
                return '󰆼 preview'
              end
              local ft = vim.bo[cur_buf].filetype
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
