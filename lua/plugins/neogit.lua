return {
  'NeogitOrg/neogit',
  dependencies = {
    'nvim-lua/plenary.nvim', -- required
    'sindrets/diffview.nvim', -- optional - Diff integration
    'folke/snacks.nvim',
  },
  opts = {
    -- Run 100% in floating windows to prevent disrupting window splits or creating tabpages
    kind = 'floating',
    floating = {
      relative = 'editor',
      width = 0.88,
      height = 0.85,
      border = 'rounded',
    },
    popup = {
      kind = 'split',
    },
    commit_editor = {
      kind = 'floating',
      show_staged_diff = false,
      spell_check = true,
    },
    commit_select_view = { kind = 'floating' },
    commit_view = { kind = 'floating' },
    log_view = { kind = 'floating' },
    reflog_view = { kind = 'floating' },
    stash = { kind = 'floating' },
    refs_view = { kind = 'floating' },
    rebase_editor = { kind = 'floating' },
    merge_editor = { kind = 'floating' },
    preview_buffer = { kind = 'floating' },
  },
  keys = {
    { '<leader>gg', ':Neogit<CR>', desc = 'Status' },
    { '<leader>gs', ':Neogit<CR>', desc = 'Status' },
    { '<leader>gc', ':Neogit commit <CR>', desc = 'Commit' },
    { '<leader>gp', ':Neogit pull <CR>', desc = 'Pull' },
    { '<leader>gP', ':Neogit push <CR>', desc = 'Push' },
    { '<leader>gb', ':Neogit branch <CR>', desc = 'Branch' },
    {
      '<leader>gd',
      function()
        local ok, dv = pcall(require, 'diffview.lib')
        if ok and next(dv.views) ~= nil then
          vim.cmd('DiffviewClose')
        else
          vim.cmd('DiffviewOpen')
        end
      end,
      desc = 'Diff (Toggle)',
    },
  },
}
