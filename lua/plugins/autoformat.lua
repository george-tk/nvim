return {
  -- Autoformat
  'stevearc/conform.nvim',
  event = { 'BufWritePre' }, -- lazy-load on first format-on-save
  cmd = { 'ConformInfo' },
  keys = {
    {
      '<leader>=',
      function()
        require('conform').format { async = true, lsp_format = 'fallback' }
      end,
      mode = 'n',
      desc = 'format buffer',
    },
  },
  opts = {
    notify_on_error = false,
    -- Conform is the *only* place that formats on save now.
    format_on_save = function(bufnr)
      local disable_filetypes = { c = true, cpp = true }
      local lsp_format_opt = disable_filetypes[vim.bo[bufnr].filetype] and 'never' or 'fallback'
      return {
        timeout_ms = 500,
        lsp_format = lsp_format_opt,
      }
    end,
    formatters_by_ft = {
      lua = { 'stylua', 'lua-language-server' },
      -- python = { 'isort', 'black' },
      markdown = { 'prettier' },
      -- Example: run the first available
      -- javascript = { "prettierd", "prettier", stop_after_first = true },
    },
  },
}
