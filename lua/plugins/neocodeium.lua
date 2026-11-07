return {
  'monkoose/neocodeium',
  event = 'VeryLazy',
  config = function()
    local neocodeium = require 'neocodeium'

    -- Ensure Codeium language server routes inference requests through server.codeium.com
    -- (default inference.codeium.com / server.windsurf.com times out or is blocked on some ISP/WSL networks)
    local function spawn_with_inference_url(orig_spawn)
      return function(path, spawn_opts, on_exit)
        if spawn_opts and type(spawn_opts.args) == 'table' and tostring(path):find 'language_server' then
          local has_inference = false
          for _, arg in ipairs(spawn_opts.args) do
            if arg == '--inference_api_server_url' then
              has_inference = true
              break
            end
          end
          if not has_inference then
            local api_url = 'https://server.codeium.com'
            for i, arg in ipairs(spawn_opts.args) do
              if arg == '--api_server_url' and spawn_opts.args[i + 1] then
                api_url = spawn_opts.args[i + 1]
                break
              end
            end
            table.insert(spawn_opts.args, '--inference_api_server_url')
            table.insert(spawn_opts.args, api_url)
          end
        end
        return orig_spawn(path, spawn_opts, on_exit)
      end
    end

    -- Send an immediate Heartbeat as soon as the language server port is discovered
    -- (by default neocodeium waits 10s for the first heartbeat tick, leaving state INACTIVE)
    vim.api.nvim_create_autocmd('User', {
      pattern = 'NeoCodeiumServerConnected',
      callback = function()
        pcall(function()
          local server = require 'neocodeium.server'
          local state = require 'neocodeium.state'
          server:request('Heartbeat', state.request_data)
        end)
      end,
    })

    local orig_uv_spawn = vim.uv.spawn
    vim.uv.spawn = spawn_with_inference_url(orig_uv_spawn)
    neocodeium.setup {
      enabled = true,
      manual = false,
      silent = true,
      show_label = false, -- Disabled suggestion counter box in line number column
      disable_in_special_buftypes = false, -- Allow suggestions in SQL query buffers and scratchpads
      filetypes = {
        help = false,
        gitcommit = false,
        gitrebase = false,
        opencode_ask = false,
        markdown = false,
        ['.'] = false,
      },
      filter = function(bufnr)
        local buftype = vim.bo[bufnr].buftype
        local ft = vim.bo[bufnr].filetype
        if buftype == 'prompt' or buftype == 'terminal' or ft:match '^snacks' or ft == 'dbui' or ft == 'dbout' or ft == 'markdown' then
          return false
        end
        return true
      end,
    }
    vim.uv.spawn = orig_uv_spawn

    -- Also wrap server.start for any future server:run() / server:restart() calls
    local server = require 'neocodeium.server'
    local orig_start = server.start
    server.start = function(self)
      local saved_spawn = vim.uv.spawn
      vim.uv.spawn = spawn_with_inference_url(saved_spawn)
      local ok, err = pcall(orig_start, self)
      vim.uv.spawn = saved_spawn
      if not ok then
        error(err)
      end
    end

    -- Ensure buffers created via nvim_create_buf (scratchpads, new buffers, previews)
    -- always have neocodeium_allowed_encoding initialized before InsertEnter checks status
    vim.api.nvim_create_autocmd({ 'BufEnter', 'InsertEnter' }, {
      callback = function(ev)
        local b = ev.buf
        if b and vim.api.nvim_buf_is_valid(b) and vim.b[b].neocodeium_allowed_encoding == nil then
          local enc = vim.bo[b].fileencoding
          vim.b[b].neocodeium_allowed_encoding = (enc == '' or enc == 'utf-8' or enc == 'latin1')
        end
      end,
    })

    -- Intercept document generation so buffers outside cwd (DBUI queries, scratchpads, unnamed buffers)
    -- are assigned a valid relative workspace_uri. Codeium server strictly rejects requests if
    -- absolute_uri isn't relative to workspace_uri.
    local doc = require 'neocodeium.doc'
    local orig_get = doc.get
    doc.get = function(buf, ft, max_lines, pos)
      local data = orig_get(buf, ft, max_lines, pos)
      if data then
        local path = data.absolute_uri:gsub('^file://', '')
        local root = require('neocodeium.state').project_root or vim.fn.getcwd()
        local ext = (data.editor_language and data.editor_language ~= '' and data.editor_language ~= 'unspecified') and ('.' .. data.editor_language) or '.sql'
        if path == '' or path == '/' or path:find '%[' or path:find '://' then
          data.absolute_uri = 'file://' .. root .. '/__virtual_scratchpad' .. ext
          data.workspace_uri = 'file://' .. root
        elseif not path:find(root, 1, true) then
          local parent = vim.fs.dirname(path)
          if parent and parent ~= '' then
            data.workspace_uri = 'file://' .. parent
          end
        end
      end
      return data
    end

    -- Ensure ghost-text highlight is clearly visible (muted grey)
    vim.api.nvim_set_hl(0, 'NeoCodeiumSuggestion', { fg = '#7f849c', ctermfg = 244, default = false })

    -- Dedicated Alt-keys for AI Autocomplete (Coexists simultaneously with Blink popup menu)
    vim.keymap.set('i', '<M-a>', function()
      neocodeium.accept()
    end, { desc = 'NeoCodeium: Accept Full' })

    vim.keymap.set('i', '<M-w>', function()
      neocodeium.accept_word()
    end, { desc = 'NeoCodeium: Accept Word' })

    vim.keymap.set('i', '<M-e>', function()
      neocodeium.accept_line()
    end, { desc = 'NeoCodeium: Accept Line' })

    vim.keymap.set('i', '<M-n>', function()
      neocodeium.cycle_or_complete()
    end, { desc = 'NeoCodeium: Next Suggestion' })

    vim.keymap.set('i', '<M-p>', function()
      neocodeium.cycle_or_complete(-1)
    end, { desc = 'NeoCodeium: Prev Suggestion' })

    vim.keymap.set('i', '<M-c>', function()
      neocodeium.clear()
    end, { desc = 'NeoCodeium: Clear Suggestion' })

    -- Normal mode management keybindings under <leader>a
    vim.keymap.set('n', '<leader>aU', '<cmd>NeoCodeium auth<CR>', { desc = 'AI Auth / Status' })
  end,
}
