return {
  'mfussenegger/nvim-lint',
  event = { 'BufReadPre', 'BufNewFile' },
  config = function()
    local lint = require 'lint'

    lint.linters_by_ft = {
      dockerfile = { 'hadolint' },
      ['yaml.docker-compose'] = { 'dclint' },
      markdown = { 'markdownlint-cli2' },
      sh = { 'shellcheck' },
      bash = { 'shellcheck' },
    }

    lint.linters['markdownlint-cli2'].args = {
      '--config',
      vim.fs.joinpath(vim.fn.stdpath 'config', 'markdownlint-cli2.yaml'),
      '-',
    }

    lint.linters.dclint.args = { '--no-color' }

    local group = vim.api.nvim_create_augroup('UserLint', { clear = true })
    vim.api.nvim_create_autocmd({ 'BufReadPost', 'BufWritePost', 'InsertLeave' }, {
      group = group,
      callback = function(args)
        if vim.bo[args.buf].buftype ~= '' then
          return
        end
        lint.try_lint()
      end,
    })
  end,
}
