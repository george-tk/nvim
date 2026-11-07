return {
  'NeogitOrg/neogit',
  dependencies = {
    'nvim-lua/plenary.nvim', -- required
    'sindrets/diffview.nvim', -- optional - Diff integration
    'folke/snacks.nvim',
  },
  opts = {
    -- Dock NeogitStatus and all sub-views/popups inside the Right Panel (VS Code Source Control style)
    kind = 'vsplit',
    commit_editor = {
      kind = 'split_above',
      show_staged_diff = false,
      spell_check = true,
    },
    popup = {
      kind = 'split',
    },
    commit_select_view = { kind = 'replace' },
    commit_view = { kind = 'replace' },
    log_view = { kind = 'replace' },
    reflog_view = { kind = 'replace' },
    stash = { kind = 'replace' },
    refs_view = { kind = 'replace' },
    rebase_editor = { kind = 'split_above' },
    merge_editor = { kind = 'split_above' },
    preview_buffer = { kind = 'split' },
    mappings = {
      popup = {
        -- Free `l` for Explorer-style fold toggling; move LogPopup to `L`
        ['l'] = false,
        ['L'] = 'LogPopup',
        -- Move full Commit Options popup (amend/reword/fixup/flags) to `C` so `c` commits directly like VS Code
        ['c'] = false,
        ['C'] = 'CommitPopup',
      },
      status = {
        -- Explorer-style fold navigation: `l` opens/toggles folds, `h` closes/collapses folds
        ['l'] = 'Toggle',
        ['h'] = 'CloseFold',
        ['<tab>'] = false,
      },
    },
  },
  config = function(_, opts)
    require('neogit').setup(opts)

    -- 1. Reflow Neogit Popup Action Grids to at most 2 columns side-by-side so popups fit cleanly inside the Right Panel
    local ok_pui, popup_ui = pcall(require, 'neogit.lib.popup.ui')
    local ok_com, common = pcall(require, 'neogit.buffers.common')
    local ok_ui, Ui = pcall(require, 'neogit.lib.ui')
    if ok_pui and popup_ui and ok_com and common and ok_ui and Ui then
      local orig_items = popup_ui.items
      popup_ui.items = function(state)
        if not state or not state.actions or #state.actions <= 2 then
          return orig_items(state)
        end
        local saved_actions = state.actions
        state.actions = {}
        local items = orig_items(state)
        state.actions = saved_actions

        -- Render action groups in pairs of 2 columns so they never overflow the Right Panel width
        for idx = 1, #saved_actions, 2 do
          local chunk = { saved_actions[idx] }
          if saved_actions[idx + 1] then
            table.insert(chunk, saved_actions[idx + 1])
          end
          local temp_state = { config = {}, args = {}, actions = chunk }
          local chunk_items = orig_items(temp_state)
          for _, ci in ipairs(chunk_items) do
            table.insert(items, ci)
          end
          if idx + 2 <= #saved_actions then
            table.insert(items, common.EmptyLine())
          end
        end
        return items
      end
    end

    -- 2. Confine ALL Neogit buffers (Popups, Commit Editor, Log/Commit/Refs views) to the Right Panel
    local ok_buf, Buffer = pcall(require, 'neogit.lib.buffer')
    if ok_buf and Buffer then
      local function get_neogit_anchor_win()
        local layout_ok, layout = pcall(require, 'utils.layout')
        -- Prefer the NeogitStatus window if visible
        for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
          if vim.api.nvim_win_is_valid(win) then
            local b = vim.api.nvim_win_get_buf(win)
            if vim.bo[b].filetype == 'NeogitStatus' then
              return win
            end
          end
        end
        if layout_ok and layout.get_right_sidebar_win then
          local rw = layout.get_right_sidebar_win()
          if rw and vim.api.nvim_win_is_valid(rw) then
            return rw
          end
        end
        return nil
      end

      local function close_neogit_popups_sync()
        local anchor = get_neogit_anchor_win()
        for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
          if vim.api.nvim_win_is_valid(win) then
            local b = vim.api.nvim_win_get_buf(win)
            if vim.bo[b].filetype == 'NeogitPopup' then
              if anchor and vim.api.nvim_win_is_valid(anchor) and anchor ~= win then
                pcall(vim.api.nvim_set_current_win, anchor)
              end
              pcall(vim.api.nvim_win_close, win, true)
            end
          end
        end
      end

      local orig_show = Buffer.show
      function Buffer:show()
        local existing_wins = vim.fn.win_findbuf(self.handle)
        if #existing_wins > 0 and vim.api.nvim_win_is_valid(existing_wins[1]) then
          vim.api.nvim_set_current_win(existing_wins[1])
          return existing_wins[1]
        end

        local ft = self.handle and vim.api.nvim_buf_is_valid(self.handle) and vim.bo[self.handle].filetype or ''
        local bname = (self.name or '')

        -- Main NeogitStatus opens via standard vsplit docked in Right Panel
        if ft == 'NeogitStatus' or bname == 'NeogitStatus' then
          local win = orig_show(self)
          if win and vim.api.nvim_win_is_valid(win) then
            vim.b[self.handle].panel_zone = 'right'
            vim.b[self.handle].panel_type = 'neogit'
            vim.wo[win].wrap = true
            vim.wo[win].linebreak = true
            vim.wo[win].breakindent = true
          end
          return win
        end

        local anchor_win = get_neogit_anchor_win()
        if not (anchor_win and vim.api.nvim_win_is_valid(anchor_win)) then
          if _G.RightPanel and _G.RightPanel.open_neogit then
            _G.RightPanel.open_neogit(true)
            anchor_win = get_neogit_anchor_win()
          end
        end

        local is_popup = (ft == 'NeogitPopup' or self.kind == 'popup' or bname:match 'Popup$' ~= nil)
        local is_editor = (
          ft == 'gitcommit'
          or ft == 'NeogitRebaseTodo'
          or bname:find 'COMMIT_EDITMSG' ~= nil
          or bname:find 'MERGE_MSG' ~= nil
          or bname:find 'git%-rebase%-todo' ~= nil
        )

        if anchor_win and vim.api.nvim_win_is_valid(anchor_win) then
          if is_popup then
            close_neogit_popups_sync()
            anchor_win = get_neogit_anchor_win() or anchor_win
            local win = vim.api.nvim_open_win(self.handle, true, {
              split = 'below',
              win = anchor_win,
              height = 14,
            })
            self.win_handle = win
            vim.b[self.handle].panel_zone = 'right'
            vim.b[self.handle].panel_type = 'neogit'
            vim.wo[win].wrap = true
            vim.wo[win].linebreak = true
            vim.wo[win].winfixwidth = true
            return win
          elseif is_editor then
            close_neogit_popups_sync()
            anchor_win = get_neogit_anchor_win() or anchor_win
            local win = vim.api.nvim_open_win(self.handle, true, {
              split = 'above',
              win = anchor_win,
              height = 12,
            })
            self.win_handle = win
            vim.b[self.handle].panel_zone = 'right'
            vim.b[self.handle].panel_type = 'neogit'
            vim.wo[win].wrap = true
            vim.wo[win].linebreak = true
            vim.wo[win].winfixheight = true
            vim.wo[win].winfixwidth = true
            return win
          else
            -- Sub-views (LogView, CommitView, RefsView, StashView) open in-place inside the Right Panel
            close_neogit_popups_sync()
            anchor_win = get_neogit_anchor_win() or anchor_win
            vim.api.nvim_set_current_win(anchor_win)
            vim.wo[anchor_win].winfixbuf = false
            self.kind = 'replace'
            self.old_buf = vim.api.nvim_win_get_buf(anchor_win)
            self.old_cwd = vim.uv.cwd()
            vim.api.nvim_win_set_buf(anchor_win, self.handle)
            vim.wo[anchor_win].winfixbuf = false
            vim.wo[anchor_win].wrap = true
            vim.wo[anchor_win].linebreak = true
            vim.wo[anchor_win].breakindent = true
            vim.b[self.handle].panel_zone = 'right'
            vim.b[self.handle].panel_type = 'neogit'
            self.win_handle = anchor_win
            return anchor_win
          end
        end

        return orig_show(self)
      end

      local orig_close = Buffer.close
      function Buffer:close(force)
        if self.kind == 'replace' and self.win_handle and vim.api.nvim_win_is_valid(self.win_handle) then
          vim.wo[self.win_handle].winfixbuf = false
          orig_close(self, force)
          if vim.api.nvim_win_is_valid(self.win_handle) then
            vim.wo[self.win_handle].winfixbuf = false
            vim.wo[self.win_handle].wrap = true
            vim.wo[self.win_handle].linebreak = true
            vim.wo[self.win_handle].breakindent = true
          end
          return
        end

        local ft = self.handle and vim.api.nvim_buf_is_valid(self.handle) and vim.bo[self.handle].filetype or ''
        local bname = (self.name or '')
        local is_subsplit = (
          ft == 'NeogitPopup'
          or ft == 'gitcommit'
          or ft == 'NeogitRebaseTodo'
          or bname:find 'COMMIT_EDITMSG' ~= nil
          or bname:find 'MERGE_MSG' ~= nil
        )

        if self.handle and vim.api.nvim_buf_is_valid(self.handle) then
          local winnr = vim.fn.bufwinnr(self.handle)
          local anchor = get_neogit_anchor_win()
          if winnr ~= -1 then
            local winid = vim.fn.win_getid(winnr)
            if is_subsplit and anchor and vim.api.nvim_win_is_valid(anchor) and anchor ~= winid then
              pcall(vim.api.nvim_set_current_win, anchor)
            end
            pcall(vim.api.nvim_win_close, winid, true)
          end
          pcall(vim.api.nvim_buf_delete, self.handle, { force = force or true })
          if is_subsplit and anchor and vim.api.nvim_win_is_valid(anchor) then
            pcall(vim.api.nvim_set_current_win, anchor)
          end
          return
        end

        orig_close(self, force)
      end
    end

    -- 3. Enforce soft wrapping & VS Code-style direct commit on `c` in NeogitStatus
    vim.api.nvim_create_autocmd({ 'FileType', 'BufWinEnter', 'User' }, {
      pattern = { 'NeogitStatus', 'NeogitStatusRefreshed' },
      callback = function()
        vim.schedule(function()
          for _, win in ipairs(vim.api.nvim_list_wins()) do
            if vim.api.nvim_win_is_valid(win) then
              local buf = vim.api.nvim_win_get_buf(win)
              if vim.bo[buf].filetype == 'NeogitStatus' then
                vim.wo[win].wrap = true
                vim.wo[win].linebreak = true
                vim.wo[win].breakindent = true
                vim.wo[win].spell = false

                -- Bind `c` in NeogitStatus to open the Commit Message box directly at the top of the Right Panel (VS Code style)
                -- while `C` opens the full Commit Options popup (for amend/reword/fixup/flags)
                vim.keymap.set('n', 'c', function()
                  local a = require 'neogit.lib.async'
                  local git = require 'neogit.lib.git'
                  local client = require 'neogit.client'
                  local input = require 'neogit.lib.input'
                  local notification = require 'neogit.lib.notification'
                  a.run(function()
                    if not git.status.anything_staged() then
                      if git.status.anything_unstaged() or #git.repo.state.untracked.items > 0 then
                        if input.get_permission 'Nothing is staged. Stage all changes and commit?' then
                          git.status.stage_all()
                        else
                          return
                        end
                      else
                        notification.warn 'No changes to commit.'
                        return
                      end
                    end
                    client.wrap(git.cli.commit, {
                      autocmd = 'NeogitCommitComplete',
                      msg = {
                        success = 'Committed',
                        fail = 'Commit failed',
                      },
                      interactive = true,
                      show_diff = false,
                    })
                  end)
                end, { buffer = buf, nowait = true, silent = true, desc = 'Direct Commit (Top of Right Panel)' })
              end
            end
          end
        end)
      end,
    })

    local ok_act, actions = pcall(require, 'neogit.buffers.status.actions')
    if ok_act and actions then
      -- Helper to open/jump to a file/hunk inside the left Editor zone without closing or splitting Neogit
      local function open_in_editor_zone(self, item, split_cmd)
        local cursor = nil
        if rawget(item, 'diff') and item.diff and item.diff.hunks then
          local ok_j, jump = pcall(require, 'neogit.lib.jump')
          local line = self.buffer:cursor_line()
          for _, hunk in ipairs(item.diff.hunks) do
            if line >= hunk.first and line <= hunk.last then
              local offset = line - hunk.first
              if ok_j and jump and jump.adjust_row then
                local row = jump.adjust_row(hunk.disk_from, offset, hunk.lines, '-')
                cursor = { row, 0 }
              else
                cursor = { hunk.disk_from, 0 }
              end
              break
            end
          end
        end

        vim.schedule(function()
          local ed_win = _G.RightPanel and _G.RightPanel.get_editor_win and _G.RightPanel.get_editor_win() or nil
          if not (ed_win and vim.api.nvim_win_is_valid(ed_win)) then
            vim.cmd 'topleft vsplit'
            ed_win = vim.api.nvim_get_current_win()
          else
            vim.api.nvim_set_current_win(ed_win)
            if split_cmd == 'split' then
              vim.cmd 'split'
              ed_win = vim.api.nvim_get_current_win()
            elseif split_cmd == 'vsplit' then
              vim.cmd 'vsplit'
              ed_win = vim.api.nvim_get_current_win()
            end
          end

          local prev_wfb = vim.wo[ed_win].winfixbuf
          if prev_wfb then
            vim.wo[ed_win].winfixbuf = false
          end

          vim.cmd('edit ' .. vim.fn.fnameescape(item.absolute_path))
          if cursor and cursor[1] then
            local line_count = vim.api.nvim_buf_line_count(0)
            local target_row = math.max(1, math.min(cursor[1], line_count))
            pcall(vim.api.nvim_win_set_cursor, ed_win, { target_row, cursor[2] or 0 })
            vim.cmd 'normal! zz'
          end

          if _G.RightPanel and _G.RightPanel.ensure_precedence then
            _G.RightPanel.ensure_precedence()
          end
        end)
      end

      -- Override <CR> (GoToFile), <C-s> (SplitOpen), and <C-v> (VSplitOpen) in NeogitStatus
      -- so files/hunks always open in the left Editor zone while keeping the Neogit right sidebar open
      local orig_goto_file = actions.n_goto_file
      actions.n_goto_file = function(self)
        local orig_fn = orig_goto_file and orig_goto_file(self)
        return function()
          local item = self.buffer and self.buffer.ui and self.buffer.ui:get_item_under_cursor()
          if item and item.absolute_path then
            if self:has_submodule(item.absolute_path) then
              if orig_fn then
                orig_fn()
              end
              return
            end
            open_in_editor_zone(self, item, 'edit')
            return
          end

          if orig_fn then
            orig_fn()
          end
        end
      end

      actions.n_split_open = function(self)
        return function()
          local item = self.buffer and self.buffer.ui and self.buffer.ui:get_item_under_cursor()
          if item and item.absolute_path then
            open_in_editor_zone(self, item, 'split')
          end
        end
      end

      actions.n_vertical_split_open = function(self)
        return function()
          local item = self.buffer and self.buffer.ui and self.buffer.ui:get_item_under_cursor()
          if item and item.absolute_path then
            open_in_editor_zone(self, item, 'vsplit')
          end
        end
      end

      -- Enhance `h` (CloseFold) to behave like an Explorer tree:
      -- closes the current fold if open, or climbs to the parent file/section and closes it
      local orig_close_fold = actions.n_close_fold
      actions.n_close_fold = function(self)
        local orig_fn = orig_close_fold and orig_close_fold(self)
        return function()
          local fold = self.buffer and self.buffer.ui and self.buffer.ui:get_fold_under_cursor()
          if fold and not fold.options.folded then
            if orig_fn then
              orig_fn()
            end
            return
          end

          -- If current fold is already closed (e.g., folded hunk), climb to parent item or section
          local item = self.buffer and self.buffer.ui and self.buffer.ui:get_item_under_cursor()
          local cur_line = vim.fn.line '.'
          if item and item.first and cur_line > item.first then
            self.buffer:move_cursor(item.first)
            if orig_fn then
              orig_fn()
            end
            return
          end

          local section = self.buffer and self.buffer.ui and self.buffer.ui:get_current_section()
          if section and section.first and cur_line > section.first then
            self.buffer:move_cursor(section.first)
            if orig_fn then
              orig_fn()
            end
          end
        end
      end

      -- Ensure pressing `q` in NeogitStatus cleanly returns focus to the left Editor window
      local orig_close = actions.n_close
      actions.n_close = function(self)
        local orig_fn = orig_close and orig_close(self)
        return function()
          if orig_fn then
            orig_fn()
          end
          vim.schedule(function()
            if not (self.buffer and self.buffer:is_visible()) then
              local layout_ok, layout = pcall(require, 'utils.layout')
              if layout_ok and layout.get_right_sidebar_win and layout.get_right_sidebar_win() ~= nil then
                return
              end
              local ed_win = _G.RightPanel and _G.RightPanel.get_editor_win and _G.RightPanel.get_editor_win() or nil
              if ed_win and vim.api.nvim_win_is_valid(ed_win) then
                vim.api.nvim_set_current_win(ed_win)
              end
              if _G.RightPanel and _G.RightPanel.equalize_splits then
                _G.RightPanel.equalize_splits()
              end
              pcall(function()
                require('lualine').refresh()
              end)
            end
          end)
        end
      end
    end

    -- Explorer-style `l` to open commits/items in Neogit sub-views (LogView, RefsView, StashView)
    vim.api.nvim_create_autocmd('FileType', {
      pattern = { 'NeogitLogView', 'NeogitRefsView', 'NeogitStashView', 'NeogitCommitSelectView' },
      callback = function(ev)
        vim.keymap.set('n', 'l', '<CR>', { buffer = ev.buf, remap = true, silent = true, nowait = true, desc = 'Open Commit / Item' })
      end,
    })
  end,
  keys = {
    {
      '<leader>gg',
      function()
        if _G.RightPanel and _G.RightPanel.open_neogit then
          _G.RightPanel.open_neogit()
        else
          require('neogit').open { kind = 'vsplit' }
        end
      end,
      desc = 'Status (Right Panel)',
    },
    {
      '<leader>gs',
      function()
        if _G.RightPanel and _G.RightPanel.open_neogit then
          _G.RightPanel.open_neogit()
        else
          require('neogit').open { kind = 'vsplit' }
        end
      end,
      desc = 'Status (Right Panel)',
    },
    { '<leader>gc', ':Neogit commit <CR>', desc = 'Commit' },
    { '<leader>gl', ':Neogit log <CR>', desc = 'Log' },
    { '<leader>gp', ':Neogit pull <CR>', desc = 'Pull' },
    { '<leader>gP', ':Neogit push <CR>', desc = 'Push' },
    { '<leader>gb', ':Neogit branch <CR>', desc = 'Branch' },
    {
      '<leader>gd',
      function()
        local ok, dv = pcall(require, 'diffview.lib')
        if ok and next(dv.views) ~= nil then
          vim.cmd 'DiffviewClose'
        else
          vim.cmd 'DiffviewOpen'
        end
      end,
      desc = 'Diff (Toggle)',
    },
  },
}
