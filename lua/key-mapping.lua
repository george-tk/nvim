--  NOTE: Must happen before plugins are loaded (otherwise wrong leader will be used)
vim.g.mapleader = ' '
vim.g.maplocalleader = ' '

-- Clear highlights on search
vim.keymap.set('n', '<Esc>', '<cmd>nohlsearch<CR>')

-- Exit terminal mode
vim.keymap.set('t', '<Esc><Esc>', '<C-\\><C-n>', { desc = 'Exit terminal mode' })

-- spelling
vim.keymap.set('n', '<leader>sS', '<cmd>set spell!<CR>', { desc = '[S]et [S]pell' })

-- autoindent pasted text
-- vim.keymap.set('n', 'p', 'p=`]', { desc = 'Indented Paste' })

-- next and previews spelling
vim.keymap.set('n', '<leader>sn', ']s <leader>ss', { desc = '[S]pell [N]ext', remap = true })
vim.keymap.set('n', '<leader>sp', '[s <leader>ss', { desc = '[S]pell [P]revious', remap = true })

-- Buffer management
vim.keymap.set('n', '<leader><Tab>', ':bn<CR>', { desc = 'next buffer' })
vim.keymap.set('n', '<leader><S-Tab>', ':bp<CR>', { desc = 'previous buffer' })
vim.keymap.set('n', '<leader>q', ':bd<CR>', { desc = '[q]uit buffer' })
vim.keymap.set('n', '<leader>r', '<C-6>', { desc = '[r]eturn to buffer' })

-- Snacks Dashboard
vim.keymap.set('n', '<leader>d', function()
  -- If we are already on the dashboard, do nothing
  if vim.bo.filetype == 'snacks_dashboard' then
    return
  end
  -- Save session first if persistence is loaded
  pcall(function() require('persistence').save() end)
  -- Open dashboard first, forcing it to use the current window (prevents floating window bugs)
  Snacks.dashboard.open({ win = vim.api.nvim_get_current_win() })
  -- Get dashboard buffer
  local dashboard_buf = vim.api.nvim_get_current_buf()
  -- Delete all other buffers
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if buf ~= dashboard_buf and vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buflisted then
      vim.cmd('silent! bd ' .. buf)
    end
  end
end, { desc = 'Go to Dashboard' })
