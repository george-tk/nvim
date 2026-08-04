return {
  'nickjvandyke/opencode.nvim',
  version = '*', -- Latest stable release
  event = 'VeryLazy',
  dependencies = {
    'folke/snacks.nvim',
  },
  config = function()
    -- Automatically locate opencode executable in PATH or ~/.opencode/bin
    local binary = vim.fn.exepath('opencode')
    if binary == '' then
      local opencode_path = vim.fn.expand('~/.opencode/bin/opencode')
      if (vim.uv or vim.loop).fs_stat(opencode_path) then
        binary = opencode_path
      else
        binary = 'opencode'
      end
    end
    local opencode_cmd = binary .. ' --port'

    ---@type snacks.terminal.Opts
    local snacks_terminal_opts = {
      win = {
        position = 'right',
        width = 0.3,
        enter = false,
        wo = {
          winbar = '',
        },
      },
    }

    ---@type opencode.Opts
    vim.g.opencode_opts = {
      server = {
        start = function()
          require('snacks.terminal').open(opencode_cmd, snacks_terminal_opts)
        end,
      },
    }

    -- Keymaps for OpenCode AI under <leader>a
    vim.keymap.set({ 'n', 'x' }, '<leader>aa', function()
      require('opencode').ask('@this: ')
    end, { desc = 'Ask AI' })

    vim.keymap.set({ 'n', 'x' }, '<leader>as', function()
      require('opencode').select()
    end, { desc = 'AI Prompts' })

    vim.keymap.set({ 'n' }, '<leader>at', function()
      if _G.RightPanel then
        _G.RightPanel.open_opencode()
      else
        local binary = vim.fn.exepath('opencode')
        if binary == '' then binary = vim.fn.expand('~/.opencode/bin/opencode') end
        require('snacks.terminal').toggle(binary .. ' --port', { win = { position = 'right', width = 0.3, relative = 'editor' } })
      end
    end, { desc = 'AI Panel' })

    vim.keymap.set({ 'n' }, '<leader>an', function()
      require('opencode').command('session.new')
    end, { desc = 'New AI Session' })

    vim.keymap.set({ 'n' }, '<leader>ac', function()
      require('opencode').command('session.compact')
    end, { desc = 'Compact AI Session' })

    vim.keymap.set({ 'n', 'x' }, 'go', function()
      return require('opencode').operator('@this ')
    end, { desc = 'Append Range to AI', expr = true })

    vim.keymap.set({ 'n' }, 'goo', function()
      return require('opencode').operator('@this ') .. '_'
    end, { desc = 'Append Line to AI', expr = true })

    vim.keymap.set({ 'n' }, '<S-C-u>', function()
      require('opencode').command('session.half.page.up')
    end, { desc = 'Scroll AI Up' })

    vim.keymap.set({ 'n' }, '<S-C-d>', function()
      require('opencode').command('session.half.page.down')
    end, { desc = 'Scroll AI Down' })

    -- Toggle OpenCode terminal via Snacks.terminal (<C-.>)
    vim.keymap.set({ 'n', 't' }, '<C-.>', function()
      require('snacks.terminal').toggle(opencode_cmd, snacks_terminal_opts)
    end, { desc = 'AI Panel' })

    -- Automatically show terminal when submitting a prompt
    vim.api.nvim_create_autocmd('User', {
      pattern = { 'OpencodeEvent:tui.command.execute' },
      callback = function(args)
        ---@type opencode.server.Event
        local event = args.data.event
        if event.properties.command == 'prompt.submit' then
          local win = require('snacks.terminal').get(opencode_cmd, { create = false })
          if win then
            win:show()
          end
        end
      end,
    })
  end,
}
