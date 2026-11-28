return {
  'folke/snacks.nvim',
  opts = {
    terminal = {
      enabled = true,
      win = {
        position = 'bottom',
        relative = 'editor',
        height = 0.38,
        wo = {
          winbar = '',
          winfixheight = true,
          winfixbuf = true,
        },
      },
    },
  },
}
