return {
  'folke/snacks.nvim',
  priority = 1000,
  lazy = false,
  init = function()
    -- Hook snacks.picker.actions.jump so opening files never fails on windows with 'winfixbuf'
    local function setup_picker_jump_protection()
      local ok_actions, actions = pcall(require, 'snacks.picker.actions')
      if not ok_actions or not actions.jump or actions._winfixbuf_hooked then return end
      actions._winfixbuf_hooked = true

      local orig_jump = actions.jump
      actions.jump = function(picker, item, action)
        local function is_editor_win(w)
          if not w or not vim.api.nvim_win_is_valid(w) then return false end
          if vim.api.nvim_win_get_tabpage(w) ~= vim.api.nvim_get_current_tabpage() then return false end
          if vim.api.nvim_win_get_config(w).relative ~= '' then return false end
          local b = vim.api.nvim_win_get_buf(w)
          local ft = vim.bo[b].filetype
          local bname = vim.api.nvim_buf_get_name(b):lower()
          if ft:match('^sqmeow%-') or ft == 'sqmeow' or ft == 'dbui' or ft == 'dbout'
             or ft:match('opencode') or bname:find('opencode')
             or ft:match('terminal') or bname:find('term://')
             or ft:match('^snacks_') or ft == 'neo-tree' or ft == 'qf' then
            return false
          end
          return true
        end

        local main_win = picker and picker.main
        local needs_redirect = false

        if not main_win or not vim.api.nvim_win_is_valid(main_win) then
          needs_redirect = true
        elseif not is_editor_win(main_win) or (vim.fn.exists('&winfixbuf') == 1 and vim.wo[main_win].winfixbuf) then
          needs_redirect = true
        end

        if needs_redirect then
          local target_win = nil
          for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
            if is_editor_win(w) then
              target_win = w
              break
            end
          end
          if not target_win then
            for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
              if vim.api.nvim_win_get_config(w).relative == '' then
                if vim.fn.exists('&winfixbuf') == 0 or not vim.wo[w].winfixbuf then
                  target_win = w
                  break
                end
              end
            end
          end
          if not target_win then
            vim.cmd('botright vnew')
            target_win = vim.api.nvim_get_current_win()
          end

          if target_win and vim.api.nvim_win_is_valid(target_win) then
            if vim.fn.exists('&winfixbuf') == 1 then
              vim.wo[target_win].winfixbuf = false
            end
            picker.main = target_win
          end
        else
          if vim.fn.exists('&winfixbuf') == 1 and vim.wo[main_win].winfixbuf then
            vim.wo[main_win].winfixbuf = false
          end
        end

        return orig_jump(picker, item, action)
      end
    end

    setup_picker_jump_protection()
  end,
  opts = {
    picker = {
      enabled = true,
      win = {
        input = {
          keys = {
            ['<Tab>'] = { 'list_down', mode = { 'i', 'n' } },
            ['<S-Tab>'] = { 'list_up', mode = { 'i', 'n' } },
            ['<C-j>'] = { function() vim.cmd('stopinsert'); _G.BottomPanel.toggle_active() end, mode = { 'i', 'n' }, desc = 'Bottom Output' },
            ['<M-h>'] = { function() _G.smart_resize_width(-3) end, mode = { 'i', 'n' }, desc = 'Expand Explorer' },
            ['<M-l>'] = { function() _G.smart_resize_width(3) end, mode = { 'i', 'n' }, desc = 'Shrink Explorer' },
          },
        },
        list = {
          keys = {
            ['<Tab>'] = { 'list_down', mode = { 'n', 'x' } },
            ['<S-Tab>'] = { 'list_up', mode = { 'n', 'x' } },
            ['<C-j>'] = { function() _G.BottomPanel.toggle_active() end, mode = { 'n' }, desc = 'Bottom Output' },
            ['<M-h>'] = { function() _G.smart_resize_width(-3) end, mode = { 'n' }, desc = 'Expand Explorer' },
            ['<M-l>'] = { function() _G.smart_resize_width(3) end, mode = { 'n' }, desc = 'Shrink Explorer' },
          },
        },
      },
      sources = {
        files = { hidden = true, ignored = true },
        grep = { hidden = true, ignored = true },
      },
    },
    explorer = { enabled = true },
    dashboard = { enabled = true },
    terminal = { enabled = true },
  },
  keys = {
    -- Find Files
    {
      '<leader>ff',
      function()
        Snacks.picker.files()
      end,
      desc = 'Find Files',
    },

    -- Find Word (Normal mode: live grep prompt | Visual mode: grep visual selection)
    {
      '<leader>fw',
      function()
        Snacks.picker.grep {
          search = function(p)
            return p.visual and p.visual.text or ''
          end,
        }
      end,
      desc = 'Find Word',
      mode = { 'n', 'x' },
    },

    -- Undo History (Visual diff time-travel with <C-y>/<C-S-y> yanking)
    {
      '<leader>fu',
      function()
        Snacks.picker.undo()
      end,
      desc = 'Undo History',
    },

    -- Resume Last Picker
    {
      '<leader>fr',
      function()
        Snacks.picker.resume()
      end,
      desc = 'Resume Last Picker',
    },

    -- All Pickers (Meta escape hatch)
    {
      '<leader>fp',
      function()
        Snacks.picker.pickers()
      end,
      desc = 'All Pickers',
    },

    -- Notifications
    {
      '<leader>fn',
      function()
        Snacks.picker.notifications()
      end,
      desc = 'Notifications',
    },

    -- Help Tags
    {
      '<leader>fh',
      function()
        Snacks.picker.help()
      end,
      desc = 'Help Tags',
    },

    -- Keymaps
    {
      '<leader>fk',
      function()
        Snacks.picker.keymaps()
      end,
      desc = 'Keymaps',
    },

    -- Spelling Picker (Autocomplete-style clean dropdown at cursor with zero prompt icons or counts)
    {
      '<leader>ss',
      function()
        Snacks.picker.spelling {
          title = '',
          prompt = '',
          icon = '',
          layout = {
            backdrop = false,
            layout = {
              box = 'vertical',
              backdrop = false,
              relative = 'cursor',
              row = 1,
              col = 0,
              width = 22,
              min_width = 18,
              height = 7,
              min_height = 5,
              border = 'none',
              { win = 'input', height = 1, border = 'none', title = '', footer = '' },
              { win = 'list', border = 'none' },
            },
          },
        }
      end,
      desc = 'Spelling Suggestions',
    },
  },
}
