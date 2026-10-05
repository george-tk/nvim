return { -- Useful plugin to show you pending keybinds.
  'folke/which-key.nvim',
  event = 'VeryLazy',
  opts = {
    delay = 0,
    icons = {
      group = '',
      mappings = false,
    },
    spec = {
      -- Core Top-Level Groups (Uniform 2-Key Length, Zero Prefix Collisions)
      { '<leader>c', group = 'Code', mode = { 'n', 'v' } },
      { '<leader>f', group = 'Find' },
      { '<leader>b', group = 'Database', mode = { 'n', 'v' } },
      { '<leader>a', group = 'Ai', mode = { 'n', 'v' } },
      { '<leader>T', group = 'Todo' },
      { '<leader>g', group = 'Git', mode = { 'n', 'v' } },
      { '<leader>m', group = 'Markdown' },
      { '<leader>s', group = 'Spelling' },
      { '<leader>w', group = 'Window' },
      { '<leader>j', group = 'Jira' },

      -- Direct 1-Key Actions
      { '<leader>t', desc = 'Terminal', mode = { 'n', 't' } },
      { '<leader>p', desc = 'Toggle Pin Buffer' },
      { '<leader>e', desc = 'File Explorer', mode = { 'n', 'v' } },
      { '<leader>d', desc = 'Dashboard' },
      { '<leader>z', desc = 'Zen Mode' },
      { '<leader>n', desc = 'New Buffer (with Filetype)' },
      { '<leader>q', desc = 'Close Buffer' },
      { '<leader>Q', desc = 'Quit Neovim' },
      { '<leader>r', desc = 'Alternate Buffer' },
      { '<leader><Tab>', desc = 'Next Buffer' },
      { '<leader><S-Tab>', desc = 'Previous Buffer' },

      -- Hide 0-9 buffer switching numbers from popup
      { '<leader>0', hidden = true, mode = 'n' },
      { '<leader>1', hidden = true, mode = 'n' },
      { '<leader>2', hidden = true, mode = 'n' },
      { '<leader>3', hidden = true, mode = 'n' },
      { '<leader>4', hidden = true, mode = 'n' },
      { '<leader>5', hidden = true, mode = 'n' },
      { '<leader>6', hidden = true, mode = 'n' },
      { '<leader>7', hidden = true, mode = 'n' },
      { '<leader>8', hidden = true, mode = 'n' },
      { '<leader>9', hidden = true, mode = 'n' },

      -- Hide stray uppercase plugin mappings
      { '<leader>R', hidden = true },
      { '<leader>W', hidden = true },
      { '<leader>S', hidden = true },
      { '<leader>E', hidden = true },
      { '<leader>F', hidden = true },

      -- Find Group (<leader>f)
      { '<leader>ff', desc = 'Find Files' },
      { '<leader>fw', desc = 'Find Word', mode = { 'n', 'v' } },
      { '<leader>fu', desc = 'Undo History' },
      { '<leader>fr', desc = 'Resume Last Picker' },
      { '<leader>fp', desc = 'All Pickers' },
      { '<leader>fn', desc = 'Notifications' },
      { '<leader>fh', desc = 'Help Tags' },
      { '<leader>fk', desc = 'Keymaps' },

      -- Database Group (<leader>b)
      { '<leader>bb', desc = 'Database Explorer' },
      { '<leader>bs', desc = 'Switch / Bind Database' },
      { '<leader>bw', desc = 'Save Query' },
      { '<leader>bl', desc = 'Select Saved Query' },
      { '<leader>br', desc = 'Run Query (Statement / Visual)', mode = { 'n', 'v' } },
      { '<leader>bq', desc = 'Query Scratchpad' },
      { '<leader>bo', desc = 'Query Output' },
      { '<leader>ba', desc = 'Add Database' },
      { '<leader>bd', desc = 'Delete Database' },
      { '<leader>bf', desc = 'Toggle Float Results' },
      { '<leader>bv', desc = 'Review & Apply In-Grid Edits' },
      { '<leader>bx', desc = 'Export Results' },

      -- Todo Group (<leader>T)
      { '<leader>TT', desc = 'Todo List' },
      { '<leader>Tb', desc = 'Todo Board' },
      { '<leader>Tn', desc = 'New Todo' },
      { '<leader>Tr', desc = 'Reference Todo' },
      { '<leader>Tj', desc = 'Jump to Todo' },
      { '<leader>Tl', desc = 'Todo Log' },

      -- Git Group (<leader>g)
      { '<leader>gg', desc = 'Status' },
      { '<leader>gc', desc = 'Commit' },
      { '<leader>gp', desc = 'Pull' },
      { '<leader>gP', desc = 'Push' },
      { '<leader>gb', desc = 'Branch' },
      { '<leader>gd', desc = 'Diff' },

      -- Markdown Group (<leader>m)
      { '<leader>mt', desc = 'Create Table' },
      { '<leader>mr', desc = 'Row Below' },
      { '<leader>ma', desc = 'Row Above' },
      { '<leader>mc', desc = 'Column Right' },
      { '<leader>mb', desc = 'Column Left' },
      { '<leader>md', desc = 'Delete Row' },
      { '<leader>mx', desc = 'Delete Column' },
      { '<leader>mu', desc = 'Update Numbering' },
      { '<leader>mi', desc = 'Insert Image' },
      { '<leader>mp', desc = 'Toggle Markdown Autocomplete' },
      { '<leader>ms', desc = 'Toggle Dictionary Completion' },

      -- Code Group (<leader>c)
      { '<leader>ca', desc = 'Code Action', mode = { 'n', 'v' } },
      { '<leader>cr', desc = 'Rename Symbol' },
      { '<leader>cd', desc = 'Line Diagnostics' },
      { '<leader>cD', desc = 'Workspace Diagnostics' },
      { '<leader>cR', desc = 'References' },
      { '<leader>cs', desc = 'Document Symbols' },
      { '<leader>ci', desc = 'Implementations' },
      { '<leader>ct', desc = 'Change Filetype' },
      { '<leader>cf', desc = 'Format Buffer' },

      -- Spelling Group (<leader>s)
      { '<leader>st', desc = 'Spelling Toggle' },
      { '<leader>ss', desc = 'Spelling Suggestions' },
      { '<leader>sn', desc = 'Next Spell Error' },
      { '<leader>sp', desc = 'Previous Spell Error' },

      -- AI Group (<leader>a)
      { '<leader>aa', desc = 'AI Explorer' },
      { '<leader>ai', desc = 'Ask AI', mode = { 'n', 'v' } },
      { '<leader>as', desc = 'AI Prompts', mode = { 'n', 'v' } },
      { '<leader>an', desc = 'New AI Session' },
      { '<leader>ac', desc = 'Compact AI Session' },
      { '<leader>ax', desc = 'Stop AI Generation' },
      { '<leader>au', desc = 'AI Auth / Status' },

      -- Window Group (<leader>w)
      { '<leader>ws', desc = 'Split Horizontally' },
      { '<leader>wv', desc = 'Split Vertically' },
      { '<leader>we', desc = 'Balance Splits' },
      { '<leader>wq', desc = 'Close Window Split' },
      { '<leader>wo', desc = 'Close Other Splits' },

      -- Jira Group (<leader>j)
      { '<leader>jj', desc = 'Jira Board (Home)' },
      { '<leader>jf', desc = 'Find Issues' },
      { '<leader>jm', desc = 'My Tasks' },
      { '<leader>jc', desc = 'Create Issue' },
      { '<leader>jp', desc = 'Select Projects' },
      { '<leader>ji', desc = 'Issue Details' },
      { '<leader>ja', desc = 'Jira Auth / Login' },
    },
  },
}
