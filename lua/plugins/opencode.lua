return {
  'nickjvandyke/opencode.nvim',
  version = '*', -- Latest stable release
  event = 'VeryLazy',
  dependencies = {
    'folke/snacks.nvim',
  },
  config = function()
    -- Automatically locate opencode executable in PATH or ~/.opencode/bin
    local binary = vim.fn.exepath 'opencode'
    if binary == '' then
      local opencode_path = vim.fn.expand '~/.opencode/bin/opencode'
      if (vim.uv or vim.loop).fs_stat(opencode_path) then
        binary = opencode_path
      else
        binary = 'opencode'
      end
    end
    local opencode_cmd = binary .. ' --port'

    ---@type snacks.terminal.Opts
    local snacks_terminal_opts = {
      start_insert = false,
      auto_insert = true,
      win = {
        position = 'right',
        width = 0.38,
        enter = false,
        wo = {
          winbar = '',
          winfixwidth = true,
          winfixbuf = true,
        },
        on_buf = function(t)
          vim.b[t.buf].panel_zone = 'right'
          vim.b[t.buf].panel_type = 'opencode'
          vim.keymap.set('t', '<leader>t', '<Space>t', { buffer = t.buf, noremap = true, silent = true })
        end,
      },
    }

    ---@type opencode.Opts
    vim.g.opencode_opts = {
      server = {
        start = function()
          if _G.RightPanel then
            _G.RightPanel.open_opencode(true, { focus = false })
          else
            require('snacks.terminal').open(opencode_cmd, snacks_terminal_opts)
          end
        end,
      },
    }

    -- Capture visual selection & editor window BEFORE `discovery.get()` / `server.start()`
    -- so opening the OpenCode right split on first use never loses the visual selection.
    local pending_ctx = nil
    local function capture_editor_context()
      local win = vim.api.nvim_get_current_win()
      local buf = vim.api.nvim_win_get_buf(win)
      local cursor = vim.api.nvim_win_get_cursor(win)
      local mode = vim.fn.mode()
      local kind = (mode == 'V' and 'line') or (mode == 'v' and 'char') or (mode == '\22' and 'block') or nil
      local range = nil
      if kind then
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<esc>', true, false, true), 'x', true)
        local from = vim.api.nvim_buf_get_mark(buf, '<')
        local to = vim.api.nvim_buf_get_mark(buf, '>')
        if from[1] > to[1] or (from[1] == to[1] and from[2] > to[2]) then
          from, to = to, from
        end
        if kind == 'block' and from[2] > to[2] then
          from[2], to[2] = to[2], from[2]
        end
        range = {
          from = { from[1], from[2] },
          to = { to[1], to[2] },
          kind = kind,
        }
      end
      pending_ctx = { win = win, buf = buf, cursor = cursor, range = range }
      return kind ~= nil
    end

    local ok_ctx, oc_context = pcall(require, 'opencode.context')
    if ok_ctx and oc_context and oc_context.new and not oc_context._preserve_wrapped then
      local orig_new = oc_context.new
      oc_context._preserve_wrapped = true
      oc_context.new = function(server, range)
        local saved = pending_ctx
        pending_ctx = nil
        if saved and not range then
          if saved.win and vim.api.nvim_win_is_valid(saved.win) then
            pcall(vim.api.nvim_set_current_win, saved.win)
            if saved.cursor then
              pcall(vim.api.nvim_win_set_cursor, saved.win, saved.cursor)
            end
          end
          return orig_new(server, saved.range)
        end
        return orig_new(server, range)
      end
    end

    -- Ensure pressing <CR> in `ask()` always submits the prompt (even if there is a trailing space)
    local ok_ask, oc_ask = pcall(require, 'opencode.ui.ask')
    if ok_ask and oc_ask and oc_ask.ask and not oc_ask._trim_wrapped then
      local orig_ask = oc_ask.ask
      oc_ask._trim_wrapped = true
      oc_ask.ask = function(default, context)
        return orig_ask(default, context):next(function(input)
          if type(input) == 'string' then
            input = input:gsub('%s+$', '')
          end
          return require('opencode.promise').resolve(input)
        end)
      end
    end

    -- Advertise '@' and '/' as trigger characters on `opencode_ask_cmp`
    -- and serve recursive workspace file completions when typing `./`
    local file_cache = { cwd = nil, ts = 0, items = {} }
    local function get_workspace_file_items()
      local cwd = vim.fn.getcwd()
      local now = (vim.uv or vim.loop).now()
      if file_cache.cwd == cwd and (now - file_cache.ts) < 10000 and #file_cache.items > 0 then
        return file_cache.items
      end
      local files
      if vim.fn.executable 'rg' == 1 then
        files = vim.fn.systemlist { 'rg', '--files', '--color=never', '--hidden', '-g', '!.git' }
      else
        files = vim.fn.systemlist { 'git', 'ls-files', '--cached', '--others', '--exclude-standard' }
      end
      local items = {}
      if vim.v.shell_error == 0 and type(files) == 'table' then
        local file_kind = vim.lsp.protocol.CompletionItemKind.File
        local plain_fmt = vim.lsp.protocol.InsertTextFormat.PlainText
        for _, f in ipairs(files) do
          local clean = f:gsub('^%./', '')
          if clean ~= '' then
            table.insert(items, {
              label = clean,
              filterText = clean,
              insertText = clean,
              insertTextFormat = plain_fmt,
              kind = file_kind,
            })
          end
        end
      end
      file_cache = { cwd = cwd, ts = now, items = items }
      return items
    end

    local ok_cmp, oc_cmp = pcall(require, 'opencode.ui.ask.cmp')
    if ok_cmp and oc_cmp and oc_cmp.cmd and not oc_cmp._trigger_wrapped then
      local orig_cmd = oc_cmp.cmd
      oc_cmp._trigger_wrapped = true
      oc_cmp.cmd = function(dispatchers, config)
        local srv = orig_cmd(dispatchers, config)
        local orig_req = srv.request
        srv.request = function(method, params, callback)
          if method == vim.lsp.protocol.Methods.initialize then
            return orig_req(method, params, function(err, result)
              if result and result.capabilities and result.capabilities.completionProvider then
                result.capabilities.completionProvider.triggerCharacters = { '@', '/' }
              end
              callback(err, result)
            end)
          elseif method == vim.lsp.protocol.Methods.textDocument_completion then
            local line = vim.api.nvim_get_current_line()
            local col = vim.api.nvim_win_get_cursor(0)[2]
            local before = line:sub(1, col)
            if before:find '^%./[%w_%-%.%/]*$' or before:find '%s%./[%w_%-%.%/]*$' then
              callback(nil, get_workspace_file_items())
              return
            end
          end
          return orig_req(method, params, callback)
        end
        return srv
      end
    end

    local active_session_id = nil

    local function set_prompt_running(running)
      if _G.OpencodePromptRunning ~= running then
        _G.OpencodePromptRunning = running
        local ok_l, lualine = pcall(require, 'lualine')
        if ok_l then
          lualine.refresh { place = { 'statusline' } }
        end
      end
    end

    -- Open a Snacks picker of user prompts in the active OpenCode session to revert back N turns
    local function pick_undo_prompt()
      require('opencode.server.discovery')
        .get()
        :next(function(server)
          return server:get_sessions():next(function(sessions)
            if not sessions or #sessions == 0 then
              vim.notify('No active OpenCode session found', vim.log.levels.INFO, { title = 'OpenCode' })
              return
            end

            -- Prefer root (non-subagent) sessions sorted by most recently updated
            local root_sessions = vim.tbl_filter(function(s)
              return not s.parentID
            end, sessions)
            local pool = #root_sessions > 0 and root_sessions or sessions
            table.sort(pool, function(a, b)
              return (a.time and a.time.updated or 0) > (b.time and b.time.updated or 0)
            end)

            local session = pool[1]
            if active_session_id then
              for _, s in ipairs(pool) do
                if s.id == active_session_id then
                  session = s
                  break
                end
              end
            end

            server:curl('/session/' .. session.id .. '/message', 'GET', nil, function(messages)
              if type(messages) ~= 'table' or #messages == 0 then
                vim.notify('No prompts to undo in current session', vim.log.levels.INFO, { title = 'OpenCode' })
                return
              end

              local revert_msg_id = session.revert and session.revert.messageID or nil
              local user_msgs = {}
              for _, msg in ipairs(messages) do
                local info = msg.info
                if info and revert_msg_id and info.id >= revert_msg_id then
                  break
                end
                if info and info.role == 'user' then
                  local text_parts = {}
                  for _, part in ipairs(msg.parts or {}) do
                    if part.type == 'text' and not part.synthetic and type(part.text) == 'string' then
                      local t = vim.trim(part.text)
                      if t ~= '' then
                        table.insert(text_parts, t)
                      end
                    end
                  end
                  local full_text = table.concat(text_parts, '\n\n')
                  if full_text == '' and info.summary and info.summary.title then
                    full_text = info.summary.title
                  end
                  if full_text ~= '' then
                    table.insert(user_msgs, {
                      id = info.id,
                      created = info.time and info.time.created or 0,
                      full_text = full_text,
                      one_line = full_text:gsub('%s+', ' '),
                      diffs = (info.summary and info.summary.diffs) or {},
                    })
                  end
                end
              end

              if #user_msgs == 0 then
                vim.notify('No prompts to undo in current session', vim.log.levels.INFO, { title = 'OpenCode' })
                return
              end

              local items = {}
              local total = #user_msgs
              for i = total, 1, -1 do
                local m = user_msgs[i]
                local steps_back = total - i + 1
                local time_str = m.created > 0 and os.date('%H:%M:%S', math.floor(m.created / 1000)) or ''
                local preview_lines = {
                  string.format('# Prompt (-%d%s)', steps_back, steps_back == 1 and ' · latest' or ''),
                  '',
                  m.full_text,
                }
                if #m.diffs > 0 then
                  table.insert(preview_lines, '')
                  table.insert(preview_lines, '## Files modified in this turn')
                  for _, d in ipairs(m.diffs) do
                    if d.file then
                      table.insert(preview_lines, string.format('- `%s` (+%d / -%d)', d.file, d.additions or 0, d.deletions or 0))
                    end
                  end
                end

                table.insert(items, {
                  idx = steps_back,
                  steps_back = steps_back,
                  message_id = m.id,
                  text = string.format('[-%d] %s', steps_back, m.one_line),
                  prompt_line = m.one_line,
                  time_str = time_str,
                  preview = {
                    text = table.concat(preview_lines, '\n'),
                    ft = 'markdown',
                  },
                })
              end

              Snacks.picker.pick {
                title = 'Undo AI Prompt (' .. (session.title or 'Current Session') .. ')',
                items = items,
                preview = 'preview',
                layout = {
                  preset = 'vscode',
                  hidden = {},
                },
                format = function(item)
                  local ret = {
                    { string.format('-%d ', item.steps_back), 'Number' },
                    { item.prompt_line, 'Normal' },
                  }
                  if item.time_str ~= '' then
                    table.insert(ret, { '  ' .. item.time_str, 'Comment' })
                  end
                  return ret
                end,
                confirm = function(picker, item)
                  picker:close()
                  if not item or not item.message_id then
                    return
                  end
                  server:curl('/session/' .. session.id .. '/revert', 'POST', { messageID = item.message_id }, function()
                    set_prompt_running(false)
                    vim.cmd 'checktime'
                    vim.notify(
                      string.format(
                        'Reverted %d prompt%s back: %s',
                        item.steps_back,
                        item.steps_back == 1 and '' or 's',
                        vim.fn.strcharpart(item.prompt_line, 0, 50)
                      ),
                      vim.log.levels.INFO,
                      { title = 'OpenCode' }
                    )
                  end, function(err)
                    vim.notify('Failed to revert prompt: ' .. tostring(err), vim.log.levels.ERROR, { title = 'OpenCode' })
                  end)
                end,
              }
            end, function(err)
              vim.notify('Failed to fetch session messages: ' .. tostring(err), vim.log.levels.ERROR, { title = 'OpenCode' })
            end)
          end)
        end)
        :catch(function(err)
          if err then
            vim.notify(tostring(err), vim.log.levels.ERROR, { title = 'OpenCode' })
          end
        end)
    end

    -- Keymaps for OpenCode AI under <leader>a
    vim.keymap.set({ 'n', 'x' }, '<leader>aa', function()
      local is_visual = capture_editor_context()
      if is_visual then
        require('opencode').ask '@this: '
        return
      end

      local buf = vim.api.nvim_get_current_buf()
      local bname = vim.api.nvim_buf_get_name(buf)
      if vim.bo[buf].buftype ~= '' or bname == '' then
        require('opencode').ask ''
        return
      end

      local lnum = vim.api.nvim_win_get_cursor(0)[1] - 1
      local line_diags = vim.diagnostic.get(buf, { lnum = lnum })
      if #line_diags > 0 then
        require('opencode').ask '@this @diagnostics: '
      else
        require('opencode').ask '@buffer: '
      end
    end, { desc = 'Ask AI' })

    vim.keymap.set({ 'n' }, '<leader>ap', function()
      if _G.RightPanel then
        _G.RightPanel.open_opencode()
      else
        require('snacks.terminal').toggle(opencode_cmd, snacks_terminal_opts)
      end
    end, { desc = 'AI Panel' })

    vim.keymap.set({ 'n', 'x' }, '<leader>as', function()
      capture_editor_context()
      require('opencode').select()
    end, { desc = 'AI Prompts' })

    vim.keymap.set({ 'n' }, '<leader>au', pick_undo_prompt, { desc = 'Undo AI Prompt' })

    vim.keymap.set({ 'n' }, '<leader>an', function()
      active_session_id = nil
      set_prompt_running(false)
      require('opencode').command 'session.new'
    end, { desc = 'New AI Session' })

    vim.keymap.set({ 'n' }, '<leader>ac', function()
      require('opencode').command 'session.compact'
    end, { desc = 'Compact AI Session' })

    vim.keymap.set({ 'n' }, '<leader>ax', function()
      set_prompt_running(false)
      require('opencode').command 'session.interrupt'
    end, { desc = 'Stop AI Generation' })

    vim.keymap.set({ 'n', 'x' }, 'go', function()
      return require('opencode').operator '@this '
    end, { desc = 'Append Range to AI', expr = true })

    vim.keymap.set({ 'n' }, 'goo', function()
      return require('opencode').operator '@this ' .. '_'
    end, { desc = 'Append Line to AI', expr = true })

    vim.keymap.set({ 'n' }, '<S-C-u>', function()
      require('opencode').command 'session.half.page.up'
    end, { desc = 'Scroll AI Up' })

    vim.keymap.set({ 'n' }, '<S-C-d>', function()
      require('opencode').command 'session.half.page.down'
    end, { desc = 'Scroll AI Down' })

    vim.keymap.set({ 'n', 't' }, '<C-.>', function()
      if _G.RightPanel then
        _G.RightPanel.open_opencode()
      else
        require('snacks.terminal').toggle(opencode_cmd, snacks_terminal_opts)
      end
    end, { desc = 'AI Panel' })

    -- Automatically show terminal on prompt submit & update Lualine running indicator
    vim.api.nvim_create_autocmd('User', {
      pattern = {
        'OpencodeEvent:tui.command.execute',
        'OpencodeEvent:session.status',
        'OpencodeEvent:session.busy',
        'OpencodeEvent:session.idle',
        'OpencodeEvent:session.error',
        'OpencodeEvent:session.updated',
        'OpencodeEvent:message.updated',
        'OpencodeEvent:server.instance.disposed',
      },
      callback = function(args)
        local event = args.data and args.data.event
        if not event then
          return
        end

        local props = event.properties or {}
        local sid = props.sessionID
          or (props.info and props.info.sessionID)
          or (props.info and props.info.id and tostring(props.info.id):match '^ses_' and props.info.id)
        if sid then
          active_session_id = sid
        end

        if event.type == 'tui.command.execute' then
          local cmd = props.command
          if cmd == 'prompt.submit' then
            set_prompt_running(true)
            if _G.RightPanel then
              _G.RightPanel.open_opencode(true, { focus = false })
            else
              local win = require('snacks.terminal').get(opencode_cmd, { create = false })
              if win then
                win:show()
              end
            end
          elseif cmd == 'session.interrupt' or cmd == 'session.new' then
            if cmd == 'session.new' then
              active_session_id = nil
            end
            set_prompt_running(false)
          end
        elseif event.type == 'session.status' then
          local st = props.status and props.status.type
          set_prompt_running(st == 'busy')
        elseif event.type == 'session.busy' then
          set_prompt_running(true)
        elseif event.type == 'session.idle' or event.type == 'session.error' or event.type == 'server.instance.disposed' then
          set_prompt_running(false)
        end
      end,
    })
  end,
}
