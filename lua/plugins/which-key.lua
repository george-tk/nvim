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
      { '<leader>D', group = 'Docker', mode = { 'n', 'v' } },
      { '<leader>m', group = 'Markdown' },
      { '<leader>j', group = 'Jira' },
      { '<leader>s', group = 'Spelling' },
      { '<leader>w', group = 'Window' },

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
      { '<leader>fs', desc = 'Search & Replace (GrugFar)', mode = { 'n', 'v' } },
      { '<leader>fW', desc = 'Replace Word Under Cursor' },
      { '<leader>fu', desc = 'Undo History' },
      { '<leader>fr', desc = 'Resume Last Picker' },
      { '<leader>fp', desc = 'Projects' },
      { '<leader>fP', desc = 'All Pickers' },
      { '<leader>fn', desc = 'Notifications' },
      { '<leader>fh', desc = 'Help Tags' },
      { '<leader>fk', desc = 'Keymaps' },

      -- Database Group (<leader>b)
      { '<leader>bb', desc = 'Database Explorer' },
      { '<leader>bf', desc = 'Find DB Tables & Columns' },
      { '<leader>be', desc = 'Visual Explain Plan', mode = { 'n', 'v' } },
      { '<leader>bt', desc = 'SQL Query Templates' },
      { '<leader>bn', desc = 'New Query Scratchpad' },
      { '<leader>bs', desc = 'Switch / Bind Database' },
      { '<leader>bo', desc = 'Query Output' },
      { '<leader>bO', desc = 'Toggle Float Output' },
      { '<leader>br', desc = 'Run Whole Buffer' },
      { '<leader>bw', desc = 'Save Query' },
      { '<leader>bl', desc = 'Load Saved Query' },
      { '<leader>bv', desc = 'Review & Apply In-Grid Edits' },
      { '<leader>bx', desc = 'Export Results' },
      { '<leader>bd', desc = 'Disconnect Database' },
      { '<leader>bA', desc = 'Add Database' },
      { '<leader>bD', desc = 'Delete Database' },

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

      -- Docker Group (<leader>D)
      { '<leader>DD', desc = 'Docker Panel' },
      { '<leader>Db', desc = 'Build Dockerfile' },
      { '<leader>Dr', desc = 'Run Docker Compose', mode = { 'n', 'v' } },

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
      { '<leader>aa', desc = 'Ask AI', mode = { 'n', 'v' } },
      { '<leader>ap', desc = 'AI Panel' },
      { '<leader>as', desc = 'AI Prompts', mode = { 'n', 'v' } },
      { '<leader>au', desc = 'Undo AI Prompt' },
      { '<leader>an', desc = 'New AI Session' },
      { '<leader>ac', desc = 'Compact AI Session' },
      { '<leader>ax', desc = 'Stop AI Generation' },
      { '<leader>aU', desc = 'AI Auth / Status' },

      -- Window Group (<leader>w)
      { '<leader>ws', desc = 'Split Horizontally' },
      { '<leader>wv', desc = 'Split Vertically' },
      { '<leader>we', desc = 'Balance Splits' },
      { '<leader>wq', desc = 'Close Window Split' },
      { '<leader>wo', desc = 'Close Other Splits' },

      -- Jira Group (<leader>j)
      { '<leader>jj', desc = 'Jira (My Tasks)' },
      { '<leader>jn', desc = 'New Local Ticket' },
      { '<leader>jN', desc = 'New Jira Issue' },
      { '<leader>jp', desc = 'Select Projects' },
      { '<leader>ji', desc = 'Issue Details' },
      { '<leader>ja', desc = 'Jira Auth / Login' },
    },
  },
}
