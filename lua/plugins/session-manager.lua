return {
  'folke/persistence.nvim',
  event = 'BufReadPre',
  opts = {
    need = 1, -- Only save session when at least 1 real file is open
    branch = true,
  },
}
