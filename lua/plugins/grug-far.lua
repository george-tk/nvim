return {
  'MagicDuck/grug-far.nvim',
  cmd = 'GrugFar',
  opts = {
    headerMaxWidth = 80,
  },
  keys = {
    {
      '<leader>sr',
      function()
        local ext = vim.bo.buftype == '' and vim.fn.expand('%:e')
        require('grug-far').open({
          transient = true,
          prefills = {
            filesFilter = ext and ext ~= '' and ('*.' .. ext) or nil,
          },
        })
      end,
      desc = 'Search & Replace in Project',
    },
    {
      '<leader>sw',
      function()
        local current_word = vim.fn.expand('<cword>')
        require('grug-far').open({
          transient = true,
          prefills = {
            search = current_word,
          },
        })
      end,
      desc = 'Search Current Word in Project',
    },
  },
}
