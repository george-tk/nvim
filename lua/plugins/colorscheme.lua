return {
  'catppuccin/nvim',
  name = 'catppuccin',
  priority = 1000,
  init = function()
    vim.cmd.colorscheme 'catppuccin-mocha'
    vim.cmd.hi 'Comment gui=none'
    vim.cmd.hi 'Folded guibg=none'
  end,
  opts = {
    flavour = 'mocha',
    transparent_background = true,
    show_end_of_buffer = false,
    styles = {
      comments = {},
      conditionals = {},
    },
    auto_integrations = true,
    custom_highlights = function(colors)
      return {
        LineNr = { fg = colors.overlay2 },
        CursorLineNr = { fg = colors.lavender, bold = true },
      }
    end,
  },
}
