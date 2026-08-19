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
      debounce = false, -- instant suggestions as you type
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
        if buftype == 'prompt' or buftype == 'terminal' or ft:match '^snacks' then
          return false
        end
        return true
      end,
    }

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
    vim.keymap.set('n', '<leader>ae', '<cmd>NeoCodeium toggle<CR>', { desc = 'Toggle AI Completion' })
    vim.keymap.set('n', '<leader>au', '<cmd>NeoCodeium auth<CR>', { desc = 'AI Auth / Status' })
  end,
}
