return {
  'monkoose/neocodeium',
  event = 'VeryLazy',
  config = function()
    local neocodeium = require 'neocodeium'

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
        ['.'] = false,
      },
      filter = function(bufnr)
        local buftype = vim.bo[bufnr].buftype
        local ft = vim.bo[bufnr].filetype
        if buftype == 'prompt' or buftype == 'terminal' or ft:match '^snacks' or ft == 'dbui' or ft == 'dbout' then
          return false
        end
        return true
      end,
    }

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
        if path == '' or path == '/' then
          local ext = (data.editor_language and data.editor_language ~= '' and data.editor_language ~= 'unspecified')
              and ('.' .. data.editor_language)
            or '.sql'
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
    vim.keymap.set('n', '<leader>au', '<cmd>NeoCodeium auth<CR>', { desc = 'AI Auth / Status' })
  end,
}
