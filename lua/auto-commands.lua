-- auto-commands.lua
-- Autocommands and functions for Neovim, focused on Markdown notes.

local M = {}

-- Aliases for Neovim APIs
local api = vim.api
local fn = vim.fn
local cmd = vim.cmd
local bo = vim.bo
local wo = vim.wo
local opt_local = vim.opt_local
local uv = vim.uv

-- Simple notification helper
local function notify(msg, level, opts)
  vim.notify(msg, level or vim.log.levels.INFO, opts or {})
end
-- Autocommand Groups
-------------------------------------------------------------------------------
local augroups = {
  user_highlight_yank = api.nvim_create_augroup('UserHighlightYank', { clear = true }),
  user_auto_create_dir = api.nvim_create_augroup('UserAutoCreateDir', { clear = true }),
  user_markdown_autosave = api.nvim_create_augroup('UserMarkdownAutosave', { clear = true }),
  user_markdown_folding = api.nvim_create_augroup('UserMarkdownFolding', { clear = true }),
  user_render_markdown_fixes = api.nvim_create_augroup('UserRenderMarkdownFixes', { clear = true }),
}

---
-- General Autocommands
-------------------------------------------------------------------------------

-- Highlight yanked text
api.nvim_create_autocmd('TextYankPost', {
  desc = 'Highlight yanked text',
  group = augroups.user_highlight_yank,
  callback = function()
    vim.highlight.on_yank()
  end,
})

-- Auto create parent directories on save
api.nvim_create_autocmd('BufWritePre', {
  desc = 'Auto create parent directories',
  group = augroups.user_auto_create_dir,
  callback = function(event)
    -- Skip non-file protocols
    if event.match:match '^%w%w+:[\\/][\\/]' then
      return
    end
    local file = uv.fs_realpath(event.match) or event.match
    vim.fn.mkdir(vim.fn.fnamemodify(file, ':p:h'), 'p')
  end,
})

---
-- Markdown Specific Autocommands & Functions
-------------------------------------------------------------------------------

-- Callback to format and save markdown files
-- local function autosave_and_format_markdown(args)
--   local ok, conform = pcall(require, 'conform')
--   if ok then
--     conform.format { bufnr = args.buf }
--   end
--   cmd 'silent! write'
-- end
--
-- -- Autosave & format markdown on leaving Insert mode
-- api.nvim_create_autocmd('InsertLeave', {
--   group = augroups.user_markdown_autosave,
--   pattern = '*.md,*.markdown',
--   callback = autosave_and_format_markdown,
--   desc = 'Autosave & format *.md, *.markdown on InsertLeave',
-- })



-- Markdown specific foldexpr function
function M.markdown_foldexpr()
  local lnum = vim.v.lnum
  local line = fn.getline(lnum)

  local syn_name = fn.synIDattr(fn.synID(lnum, 1, 1), 'name')
  if syn_name and (syn_name:match 'markdownCodeBlock' or syn_name:match 'markdownCode') then
    return '='
  end

  if line:match '^%s*[-*+>]%s' then
    return '='
  end
  local heading_match = line:match '^(#+)%s.+'
  if heading_match then
    local level = #heading_match
    if level == 1 then
      local fm_end = vim.b.frontmatter_end
      if fm_end and type(fm_end) == 'number' and (lnum == fm_end + 1) then
        return '>1'
      elseif lnum == 1 then
        return '>1'
      end
      return '>1'
    elseif level >= 2 and level <= 6 then
      return '>' .. level
    end
  end
  return '='
end

-- User command to echo current buffer's foldexpr
api.nvim_create_user_command('EchoFoldExpr', function()
  local expr = vim.api.nvim_get_option_value('foldexpr', { scope = 'local' })
  notify('Current buffer foldexpr: ' .. expr)
end, { desc = 'Echo current buffer foldexpr' })

-- FileType markdown setup
api.nvim_create_autocmd('FileType', {
  pattern = { 'markdown' },
  group = augroups.user_markdown_folding,
  callback = function(args)
    vim.wo.foldmethod = 'expr'
    vim.wo.foldexpr = "v:lua.require('auto-commands').markdown_foldexpr()"
    opt_local.fillchars:append { eob = ' ' }
    cmd 'normal! zM'
    cmd 'normal! zr'
  end,
  desc = 'Setup Markdown folding and local options',
})

api.nvim_create_autocmd('BufReadPost', {
  pattern = { '*.md', '*.markdown' },
  group = augroups.user_markdown_folding,
  callback = function(args)
    vim.bo[args.buf].filetype = 'markdown'
    vim.wo.foldmethod = 'expr'
    vim.wo.foldexpr = "v:lua.require('auto-commands').markdown_foldexpr()"
    opt_local.fillchars:append { eob = ' ' }
    cmd 'normal! zM'
    cmd 'normal! zr'
  end,
  desc = 'Force markdown folding for markdown extensions',
})

-- Ensure render-markdown re-activates on buffer enter
api.nvim_create_autocmd('BufEnter', {
  group = augroups.user_render_markdown_fixes,
  pattern = { '*.md', '*.markdown' },
  callback = function(args)
    vim.schedule(function()
      local success_rm, rm = pcall(require, 'render-markdown')
      if not success_rm or not rm or not rm.buf_enable then
        return
      end

      if not api.nvim_buf_is_valid(args.buf) or not bo[args.buf].modifiable then
        return
      end

      local ft = bo[args.buf].filetype
      if ft == 'markdown' or ft == '' then
        pcall(rm.buf_enable, args.buf)
      end
    end)
  end,
  desc = 'Ensure render-markdown is active on BufEnter for Markdown',
})

-- Function to choose fold level
function M.choose_fold_level(level_to_apply)
  local current_foldmethod = wo[0].foldmethod
  if not (current_foldmethod == 'expr' or current_foldmethod == 'manual' or current_foldmethod == 'syntax') then
    notify("Current foldmethod ('" .. current_foldmethod .. "') does not support level-based folding.", vim.log.levels.WARN)
    return
  end

  if level_to_apply <= 0 then
    cmd 'normal! zM'
    notify('All folds closed.', vim.log.levels.INFO, { title = 'Folding' })
  else
    cmd 'normal! zM'
    cmd('normal! ' .. level_to_apply .. 'zr')
  end
end

-- Keymap for choosing fold level
vim.keymap.set('n', '<leader>F', function()
  M.choose_fold_level(vim.v.count1)
end, { desc = '[f]old level' })

return M
