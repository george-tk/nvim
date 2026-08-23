return {
  -- Code Formatter (Manual trigger via <leader>=)
  'stevearc/conform.nvim',
  cmd = { 'ConformInfo' },
  keys = {
    {
      '<leader>=',
      function()
        require('conform').format { async = true, lsp_format = 'fallback' }
      end,
      mode = 'n',
      desc = 'Format Buffer',
    },
  },
  opts = {
    notify_on_error = false,
    format_on_save = false, -- Disabled autoformat on save (manual trigger only via <leader>=)
    formatters_by_ft = {
      lua = { 'stylua', 'lua-language-server' },
      -- python = { 'isort', 'black' },
      markdown = { 'prettier' },
      sql = { 'sql_formatter' },
      -- Example: run the first available
      -- javascript = { "prettierd", "prettier", stop_after_first = true },
    },
  },
}
