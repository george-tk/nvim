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
      '<leader>jk',
      function()
        require('utils.jira-picker').show_kanban('board')
      end,
      desc = 'Kanban Board List',
    },
    {
      '<leader>jK',
      function()
        require('utils.jira-picker').show_kanban('backlog')
      end,
      desc = 'Kanban Backlog List',
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
    queries = {
      ['Kanban Board'] = require('utils.jira-picker').AGILE_BOARD_JQL,
      ['Kanban Backlog'] = require('utils.jira-picker').AGILE_BACKLOG_JQL,
    },
  },
  config = function(_, opts)
    require('jira').setup(opts)

    local picker = require('utils.jira-picker')
    local sprint = require('jira.jira-api.sprint')
    local original_get_issues_by_jql = sprint.get_issues_by_jql

    sprint.get_issues_by_jql = function(project, jql, callback)
      if jql == picker.AGILE_BOARD_JQL then
        return picker.get_kanban_issues('board', callback)
      elseif jql == picker.AGILE_BACKLOG_JQL then
        return picker.get_kanban_issues('backlog', callback)
      end
      return original_get_issues_by_jql(project, jql, callback)
    end
  end,
}
