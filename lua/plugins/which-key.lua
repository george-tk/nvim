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
      { '<leader>f', group = 'Find' },
      { '<leader>b', group = 'Database', mode = { 'n', 'v' } },
      { '<leader>a', group = 'Ai', mode = { 'n', 'v' } },
      { '<leader>t', group = 'Todo' },
      { '<leader>g', group = 'Git', mode = { 'n', 'v' } },
      { '<leader>m', group = 'Markdown' },
      { '<leader>s', group = 'Spelling' },

      -- Direct 1-Key Actions
      { '<leader>/', desc = 'Terminal', mode = { 'n', 't' } },
      { '<leader>e', desc = 'File Explorer', mode = { 'n', 'v' } },
      { '<leader>d', desc = 'Dashboard' },
      { '<leader>z', desc = 'Zen Mode' },
      { '<leader>q', desc = 'Close Buffer' },
      { '<leader>r', desc = 'Alternate Buffer' },
      { '<leader>=', desc = 'Format Buffer' },
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
      { '<leader>T', hidden = true },
      { '<leader>F', hidden = true },

      -- Find Group (<leader>f)
      { '<leader>fa', desc = 'All Pickers' },
      { '<leader>fn', desc = 'Notifications' },
      { '<leader>ff', desc = 'Find Files' },
      { '<leader>fb', desc = 'Open Buffers' },
      { '<leader>fg', desc = 'Word in Workspace' },
      { '<leader>fl', desc = 'Word in Current Buffer' },
      { '<leader>fo', desc = 'Word in Open Buffers' },
      { '<leader>fw', desc = 'Word Under Cursor' },
      { '<leader>fc', desc = 'Neovim Config' },
      { '<leader>fd', desc = 'Diagnostics' },
      { '<leader>fr', desc = 'Recent Files' },
      { '<leader>fp', desc = 'Projects' },
      { '<leader>fs', desc = 'Sessions' },
      { '<leader>fi', desc = 'Images' },
      { '<leader>fh', desc = 'Help Tags' },
      { '<leader>fk', desc = 'Keymaps' },

      -- Database Group (<leader>b)
      { '<leader>bq', desc = 'Query Scratchpad' },
      { '<leader>br', desc = 'Run Query' },
      { '<leader>bo', desc = 'Query Output' },
      { '<leader>bc', desc = 'Switch Database' },
      { '<leader>ba', desc = 'Add Database' },
      { '<leader>bt', desc = 'Database Explorer' },
      { '<leader>bs', desc = 'Save Query' },

      -- Todo Group (<leader>t)
      { '<leader>tt', desc = 'Todo List' },
      { '<leader>tb', desc = 'Todo Board' },
      { '<leader>tn', desc = 'New Todo' },
      { '<leader>tr', desc = 'Reference Todo' },
      { '<leader>tj', desc = 'Jump to Todo' },
      { '<leader>tl', desc = 'Todo Log' },

      -- Git Group (<leader>g)
      { '<leader>gs', desc = 'Status' },
      { '<leader>gc', desc = 'Commit' },
      { '<leader>gp', desc = 'Push' },
      { '<leader>gl', desc = 'Pull' },
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

      -- Spelling Group (<leader>s)
      { '<leader>st', desc = 'Spelling Toggle' },
      { '<leader>ss', desc = 'Spelling Suggestions' },
      { '<leader>sn', desc = 'Next Spell Error' },
      { '<leader>sp', desc = 'Previous Spell Error' },

      -- AI Group (<leader>a)
      { '<leader>aa', desc = 'Ask AI' },
      { '<leader>as', desc = 'AI Prompts' },
      { '<leader>at', desc = 'AI Panel' },
      { '<leader>an', desc = 'New AI Session' },
      { '<leader>ac', desc = 'Compact AI Session' },
      { '<leader>ae', desc = 'Toggle AI Completion' },
      { '<leader>au', desc = 'AI Auth / Status' },
    },
  },
}
