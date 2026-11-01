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

    local function set_prompt_running(running)
      if _G.OpencodePromptRunning ~= running then
        _G.OpencodePromptRunning = running
        local ok_l, lualine = pcall(require, 'lualine')
        if ok_l then
          lualine.refresh { place = { 'statusline' } }
        end
      end
    end

    -- Keymaps for OpenCode AI under <leader>a (matching upstream recommended workflow)
    vim.keymap.set({ 'n' }, '<leader>aa', function()
      if _G.RightPanel then
        _G.RightPanel.open_opencode()
      else
        require('snacks.terminal').toggle(opencode_cmd, snacks_terminal_opts)
      end
    end, { desc = 'AI Explorer' })

    vim.keymap.set({ 'n', 'x' }, '<leader>ai', function()
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

    vim.keymap.set({ 'n', 'x' }, '<leader>as', function()
      capture_editor_context()
      require('opencode').select()
    end, { desc = 'AI Prompts' })

    vim.keymap.set({ 'n' }, '<leader>an', function()
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
        'OpencodeEvent:server.instance.disposed',
      },
      callback = function(args)
        local event = args.data and args.data.event
        if not event then
          return
        end

        if event.type == 'tui.command.execute' then
          local cmd = event.properties and event.properties.command
          if cmd == 'prompt.submit' then
            set_prompt_running(true)
            local win = require('snacks.terminal').get(opencode_cmd, { create = false })
            if win then
              win:show()
            end
          elseif cmd == 'session.interrupt' or cmd == 'session.new' then
            set_prompt_running(false)
          end
        elseif event.type == 'session.status' then
          local st = event.properties and event.properties.status and event.properties.status.type
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
