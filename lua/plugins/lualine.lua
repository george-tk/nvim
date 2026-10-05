return {
  'nvim-lualine/lualine.nvim',
  event = 'BufWinEnter', -- or 'VeryLazy' if you prefer even later
  -- Load devicons only if/when lualine renders with icons
  dependencies = {
    { 'nvim-tree/nvim-web-devicons', lazy = true },
  },

  -- Initialize buffer-ring and define fixed slot keymaps (<leader>1 to <leader>4)
  init = function()
    require('utils.buffer-ring').setup()
    require('utils.terminal-tracker').setup()

    for i = 1, 4 do
      vim.keymap.set('n', '<leader>' .. i, function()
        require('utils.buffer-ring').jump(i)
      end, { desc = 'Buffer Slot ' .. i })
    end
  end,

  opts = function()
    -- Helpers
    local function in_git_repo()
      -- Fast check: only runs when statusline renders
      local ok, git = pcall(vim.b, 'gitsigns_head')
      -- If gitsigns has attached it sets b:gitsigns_head; fallback to checking git dir
      if ok and type(git) == 'string' and git ~= '' then
        return true
      end
      -- fallback (cheap): look for .git from current file
      local dir = vim.fn.finddir('.git', '.;')
      return dir ~= ''
    end

    -- Diff component that defers to gitsigns if available and only in repos
    local diff_component = {
      'diff',
      source = function()
        local ok, gs = pcall(require, 'gitsigns')
        if ok and gs.get_hunks then
          local hunks = gs.get_hunks()
          if not hunks then
            return nil
          end
          local added, changed, removed = 0, 0, 0
          for _, h in ipairs(hunks) do
            if h.type == 'add' then
              added = added + h.added.count
            elseif h.type == 'change' then
              changed = changed + h.added.count + h.removed.count
            elseif h.type == 'delete' then
              removed = removed + h.removed.count
            end
          end
          return { added = added, modified = changed, removed = removed }
        end
        -- fallback: let lualine run its own lightweight diff (may show 0s)
        return nil
      end,
      cond = in_git_repo,
      -- Optional: throttle refresh a bit to avoid recomputing too often
      -- update_in_insert = false, -- default is false; keep it that way for less churn
    }

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

    return {
      options = {
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
        lualine_a = { 'mode' },
        -- Keep branch (light), but only inside repos
        lualine_b = {
          { 'branch', cond = in_git_repo },
          diff_component,
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
