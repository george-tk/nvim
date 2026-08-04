return {
  'nvim-lualine/lualine.nvim',
  event = 'BufWinEnter', -- or 'VeryLazy' if you prefer even later
  -- Load devicons only if/when lualine renders with icons
  dependencies = {
    { 'nvim-tree/nvim-web-devicons', lazy = true },
  },

  -- Define keymaps without forcing plugin to load
  init = function()
    for i = 1, 9 do
      vim.keymap.set('n', '<leader>' .. i, function()
        vim.cmd('LualineBuffersJump ' .. i)
      end, { desc = 'buffer ' .. i })
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

    -- Buffers component options, computed on render
    local buffers_component = {
      'buffers',
      mode = 2, -- 2 = buffer index + filename
      -- Recompute width at render time so it adapts to current UI width
      max_length = function()
        return math.floor(vim.o.columns * 0.85)
      end,
      symbols = { alternate_file = '' },
    }

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
        lualine_c = { buffers_component },

        -- Show active database when editing SQL buffers
        lualine_x = {
          {
            function()
              local db_name = vim.b.db_name
              if not db_name and _G.DatabaseUtils and _G.DatabaseUtils.current_db_name then
                db_name = _G.DatabaseUtils.current_db_name
              end
              return db_name and ('󰆼 ' .. db_name) or ''
            end,
            cond = function()
              return vim.bo.filetype == 'sql' or vim.bo.filetype == 'mysql' or vim.bo.filetype == 'plsql'
            end,
            color = { fg = '#fab387', gui = 'bold' },
          },
        },
        lualine_y = {},
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
