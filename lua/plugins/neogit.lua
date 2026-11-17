local function open_neogit_with_popup(popup_name)
  local function open_popup()
    require('neogit').open { popup_name }
  end

  if _G.RightPanel and _G.RightPanel.open_neogit then
    _G.RightPanel.open_neogit(true, open_popup)
  else
    require('neogit').open { kind = 'vsplit' }
    vim.schedule(open_popup)
  end
end

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
      kind = 'popup',
    },
    commit_select_view = { kind = 'replace' },
    commit_view = { kind = 'replace' },
    log_view = { kind = 'replace' },
    reflog_view = { kind = 'replace' },
    stash = { kind = 'replace' },
    refs_view = { kind = 'replace' },
    rebase_editor = { kind = 'split_above' },
    merge_editor = { kind = 'split_above' },
    preview_buffer = { kind = 'floating_console' },
    mappings = {
      popup = {
        -- Free `l` for Explorer-style fold toggling; move LogPopup to `L`
        ['l'] = false,
        ['L'] = 'LogPopup',
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

        -- Never hijack floating windows or git console output into Right Panel splits
        if self.kind == 'floating' or self.kind == 'floating_console' or ft == 'NeogitConsole' or bname == 'NeogitConsole' then
          return orig_show(self)
        end

        local anchor_win = get_neogit_anchor_win()
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
            local anchor_h = vim.api.nvim_win_get_height(anchor_win)
            local popup_h = math.min(14, math.max(8, math.floor(anchor_h * 0.45)))
            local win = vim.api.nvim_open_win(self.handle, true, {
              split = 'below',
              win = anchor_win,
              height = popup_h,
            })
            self.win_handle = win
            vim.b[self.handle].panel_zone = 'right'
            vim.b[self.handle].panel_type = 'neogit'
            vim.wo[win].wrap = true
            vim.wo[win].linebreak = true
            vim.wo[win].winfixheight = true
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

    -- 4. GPG Passphrase Loopback & Interactive Console Stability (WSL / Ubuntu)
    -- Prevents `pinentry-curses` from hijacking Neovim's outer terminal (`GPG_TTY`) or drawing an
    -- un-typeable curses box inside `NeogitConsole`. Instead, forces `--pinentry-mode loopback`
    -- so GPG prompts `"Enter passphrase: "` over Neogit's PTY and triggers Neovim's native `inputsecret()`.
    local ok_proc, Process = pcall(require, 'neogit.process')
    local ok_util, neogit_util = pcall(require, 'neogit.lib.util')
    if ok_proc and Process then
      local state_dir = vim.fn.stdpath 'state'
      vim.fn.mkdir(state_dir, 'p')
      local gpg_wrapper_path = state_dir .. '/neogit-gpg-loopback.sh'
      local wrapper_script = table.concat({
        '#!/usr/bin/env sh',
        'gpg_bin="${NEOGIT_REAL_GPG:-gpg}"',
        'case "$1" in',
        '  -Y) exec ssh-keygen "$@" ;;',
        'esac',
        'gnupg_home="${GNUPGHOME:-$HOME/.gnupg}"',
        'if [ -d "$gnupg_home" ]; then',
        '  agent_conf="$gnupg_home/gpg-agent.conf"',
        '  if [ ! -f "$agent_conf" ] || ! grep -q "^allow-loopback-pinentry" "$agent_conf" 2>/dev/null; then',
        '    if ! grep -q "^no-allow-loopback-pinentry" "$agent_conf" 2>/dev/null; then',
        '      printf "\\nallow-loopback-pinentry\\n" >> "$agent_conf" 2>/dev/null',
        '      gpg-connect-agent reloadagent /bye >/dev/null 2>&1 || true',
        '    fi',
        '  fi',
        'fi',
        'exec "$gpg_bin" --pinentry-mode loopback "$@"',
        '',
      }, '\n')
      pcall(vim.fn.writefile, vim.split(wrapper_script, '\n', { plain = true }), gpg_wrapper_path)
      pcall(vim.uv.fs_chmod, gpg_wrapper_path, tonumber('755', 8))

      local user_gpg_prog = nil
      local resolved_gpg_prog = false
      local function get_user_gpg_program()
        if resolved_gpg_prog then
          return user_gpg_prog
        end
        resolved_gpg_prog = true
        if vim.system then
          local ok_sys, res = pcall(function()
            return vim.system({ 'git', 'config', '--get', 'gpg.program' }, { text = true }):wait(1000)
          end)
          if ok_sys and res and res.code == 0 and res.stdout then
            local val = vim.trim(res.stdout)
            if val ~= '' and val ~= gpg_wrapper_path then
              user_gpg_prog = val
            end
          end
        end
        return user_gpg_prog
      end

      local function is_commit_or_rebase_editor_open()
        for _, win in ipairs(vim.api.nvim_list_wins()) do
          if vim.api.nvim_win_is_valid(win) then
            local b = vim.api.nvim_win_get_buf(win)
            if vim.api.nvim_buf_is_valid(b) then
              local ft = vim.bo[b].filetype
              local bname = vim.api.nvim_buf_get_name(b)
              if
                ft == 'gitcommit'
                or ft == 'NeogitRebaseTodo'
                or bname:find 'COMMIT_EDITMSG' ~= nil
                or bname:find 'MERGE_MSG' ~= nil
                or bname:find 'git%-rebase%-todo' ~= nil
              then
                return true
              end
            end
          end
        end
        return false
      end

      local orig_show_console = Process.show_console
      function Process:show_console()
        -- Never pop up NeogitConsole while the commit/merge/rebase message editor is open
        if is_commit_or_rebase_editor_open() then
          return
        end
        return orig_show_console(self)
      end

      local orig_spawn = Process.spawn
      function Process:spawn(cb)
        if self.pty then
          self.env = self.env or {}
          -- Prevent gpg-agent / pinentry-curses from drawing onto Neovim's outer TTY
          self.env.GPG_TTY = ''
          self.env.PINENTRY_USER_DATA = 'USE_TTY=1'
          local real_gpg = get_user_gpg_program()
          if real_gpg then
            self.env.NEOGIT_REAL_GPG = real_gpg
          end

          if type(self.cmd) == 'table' and self.cmd[1] and (self.cmd[1] == 'git' or self.cmd[1]:match '/git$') then
            local has_gpg_override = false
            for _, arg in ipairs(self.cmd) do
              if type(arg) == 'string' and arg:find '^gpg%.program=' then
                has_gpg_override = true
                break
              end
            end
            if not has_gpg_override then
              table.insert(self.cmd, 2, '-c')
              table.insert(self.cmd, 3, 'gpg.program=' .. gpg_wrapper_path)
            end
          end

          if self.on_partial_line then
            local orig_on_partial = self.on_partial_line
            self.on_partial_line = function(proc, line)
              local clean = line or ''
              if ok_util and neogit_util and neogit_util.remove_ansi_escape_codes then
                clean = neogit_util.remove_ansi_escape_codes(clean)
              end
              -- Ignore empty/cursor-erase chunks and git's editor-wait hint so they do not
              -- call `process.defer_show_preview_buffers()` and restart the console timer prematurely
              if clean:match '^%s*$' or clean:find('Waiting for your editor to close the file', 1, true) then
                return
              end
              -- Normalize GPG / pinentry / SSH passphrase prompts so Neogit's runner.lua
              -- reliably triggers Neovim's native `vim.fn.inputsecret()` prompt
              if clean:find '[Ee]nter passphrase' or clean:find 'Please enter the passphrase' or clean:find 'Passphrase:' or clean:find '[Ee]nter PIN' then
                pcall(vim.cmd, 'stopinsert')
                if not clean:match '^Enter passphrase' and not clean:match '^Password for' and not clean:match '^Enter PIN for' then
                  line = 'Enter passphrase: '
                else
                  line = clean
                end
              end
              return orig_on_partial(proc, line)
            end
          end
        end
        return orig_spawn(self, cb)
      end
    end

    -- If NeogitConsole is ever opened directly for an interactive hook, wire its terminal channel
    -- `on_input` callback to the underlying process so keystrokes are forwarded instead of dropped
    local ok_pbuf, ProcessBuffer = pcall(require, 'neogit.buffers.process')
    if ok_pbuf and ProcessBuffer and ok_buf and Buffer then
      local active_opening_process = nil
      local orig_open_term = Buffer.open_terminal_channel
      function Buffer:open_terminal_channel()
        local proc = self._neogit_process or active_opening_process
        if proc then
          self._neogit_process = proc
          assert(self.chan == nil, 'Terminal channel already open')
          self.chan = vim.api.nvim_open_term(self.handle, {
            on_input = function(_, _, _, data)
              if proc and proc.send then
                pcall(proc.send, proc, data)
              end
            end,
          })
          self:unlock()
          self:set_lines(0, -1, false, {})
          self:lock()
          return
        end
        return orig_open_term(self)
      end

      local orig_pbuf_open = ProcessBuffer.open
      function ProcessBuffer:open()
        active_opening_process = self.process
        local ok_open, res = pcall(orig_pbuf_open, self)
        active_opening_process = nil
        if not ok_open then
          error(res)
        end
        if self.buffer and self.process then
          self.buffer._neogit_process = self.process
        end
        return res
      end
    end
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
    {
      '<leader>gc',
      function()
        open_neogit_with_popup 'commit'
      end,
      desc = 'Commit',
    },
    {
      '<leader>gl',
      function()
        open_neogit_with_popup 'log'
      end,
      desc = 'Log',
    },
    {
      '<leader>gp',
      function()
        open_neogit_with_popup 'pull'
      end,
      desc = 'Pull',
    },
    {
      '<leader>gP',
      function()
        open_neogit_with_popup 'push'
      end,
      desc = 'Push',
    },
    {
      '<leader>gb',
      function()
        open_neogit_with_popup 'branch'
      end,
      desc = 'Branch',
    },
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
