return {
  'letieu/jira.nvim',
  dependencies = {
    'nvim-lua/plenary.nvim',
    'MunifTanjim/nui.nvim',
  },
  cmd = { 'Jira' },
  keys = {
    {
      '<leader>jj',
      function()
        require('utils.jira-picker').with_target_project(function(p)
          require('jira.board').open(p)
        end)
      end,
      desc = 'Jira Board (Home)',
    },
    {
      '<leader>jf',
      function()
        require('utils.jira-picker').find_issues()
      end,
      desc = 'Find Issues',
    },
    {
      '<leader>jm',
      function()
        require('utils.jira-picker').my_tasks()
      end,
      desc = 'My Tasks',
    },
    {
      '<leader>jc',
      function()
        require('utils.jira-picker').with_target_project(function(p)
          require('jira.create').open(p)
        end)
      end,
      desc = 'Create Issue',
    },
    {
      '<leader>jp',
      function()
        require('utils.jira-picker').select_projects()
      end,
      desc = 'Select Projects',
    },
    {
      '<leader>ji',
      function()
        require('utils.jira-picker').show_issue_details()
      end,
      desc = 'Issue Details',
    },
    {
      '<leader>ja',
      function()
        vim.cmd('Jira auth login')
      end,
      desc = 'Jira Auth / Login',
    },
  },
  opts = {
    jira = {
      api_version = '3',
      limit = 200,
      logging = false,
    },
  },
  config = function(_, opts)
    require('jira').setup(opts)
  end,
}
