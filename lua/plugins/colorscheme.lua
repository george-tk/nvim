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
        NormalNC = { bg = 'NONE' },
        NormalFloat = { bg = 'NONE' },
        FloatBorder = { fg = colors.surface2, bg = 'NONE' },
        FloatTitle = { fg = colors.lavender, bg = 'NONE' },
        Pmenu = { bg = 'NONE' },
        PmenuSel = { bg = colors.surface1, fg = colors.lavender, bold = true },
        SnacksNormalNC = { bg = 'NONE' },
        SnacksTerminal = { bg = 'NONE' },
        SnacksTerminalNC = { bg = 'NONE' },
        SnacksPicker = { bg = 'NONE' },
        SnacksPickerNormal = { bg = 'NONE' },
        SnacksPickerNormalNC = { bg = 'NONE' },
        SnacksPickerList = { bg = 'NONE' },
        SnacksPickerListNormal = { bg = 'NONE' },
        SnacksPickerInput = { bg = 'NONE' },
        SnacksPickerInputNormal = { bg = 'NONE' },
        SnacksPickerBorder = { fg = colors.surface2, bg = 'NONE' },
        SnacksPickerTree = { fg = colors.overlay1, bg = 'NONE' },
        SnacksPickerBox = { bg = 'NONE' },
        SnacksPickerPreview = { bg = 'NONE' },
        SnacksPickerPreviewNormal = { bg = 'NONE' },
        SnacksPickerBackdrop = { bg = 'NONE' },
        Terminal = { bg = 'NONE' },

        -- Blink.cmp transparent floats & borders
        BlinkCmpMenu = { bg = 'NONE' },
        BlinkCmpMenuBorder = { fg = colors.surface2, bg = 'NONE' },
        BlinkCmpMenuSelection = { bg = colors.surface1, fg = colors.lavender, bold = true },
        BlinkCmpDoc = { bg = 'NONE' },
        BlinkCmpDocBorder = { fg = colors.surface2, bg = 'NONE' },
        BlinkCmpDocSeparator = { fg = colors.surface2, bg = 'NONE' },
        BlinkCmpSignatureHelp = { bg = 'NONE' },
        BlinkCmpSignatureHelpBorder = { fg = colors.surface2, bg = 'NONE' },
        BlinkCmpLabelMatch = { fg = colors.lavender, bold = true },

        -- Inlay hints: dimmed elegant ghost labels
        LspInlayHint = { fg = colors.overlay0, bg = 'NONE', italic = true },
      }
    end,
  },
}
