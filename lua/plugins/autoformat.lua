return {
  -- Code Formatter (Manual trigger via <leader>cf)
  'stevearc/conform.nvim',
  cmd = { 'ConformInfo' },
  keys = {
    {
      '<leader>cf',
      function()
        require('conform').format { async = true, lsp_format = 'fallback' }
      end,
      mode = 'n',
      desc = 'Format Buffer',
    },
  },
  opts = {
    notify_on_error = false,
    format_on_save = false, -- Disabled autoformat on save (manual trigger only via <leader>cf)
    formatters_by_ft = {
      lua = { 'stylua' },
      python = { 'ruff_organize_imports', 'ruff_format' },
      markdown = { 'prettier' },
      json = { 'prettier' },
      yaml = { 'prettier' },
      sql = { 'sql_formatter' },
    },
  },
}
