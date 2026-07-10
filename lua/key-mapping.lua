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
