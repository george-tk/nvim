return {
  {
    'MeanderingProgrammer/render-markdown.nvim',
    ft = {
      'markdown',
      'text',
      'tex',
      'plaintex',
      'norg',
    },
    opts = {
      render_modes = true,
      bullet = {
        enabled = true,
      },
      heading = {
        sign = false,
        icons = { '󰎤 ', '󰎧 ', '󰎪 ', '󰎭 ', '󰎱 ', '󰎳 ' },
        backgrounds = {
          'Headline1Bg',
          'Headline2Bg',
          'Headline3Bg',
          'Headline4Bg',
          'Headline5Bg',
          'Headline6Bg',
        },

        width = 'block',
        left_pad = 0,
        right_pad = 0,
      },
    },
    dependencies = { 'nvim-treesitter/nvim-treesitter', 'nvim-tree/nvim-web-devicons' }, -- if you prefer nvim-web-devicons
  },
  {
    'jakewvincent/mkdnflow.nvim',
    ft = { 'markdown', 'text', 'tex', 'plaintex', 'norg' },
    config = function(_, opts)
      require('mkdnflow').setup(opts)
    end,
    opts = {
      on_attach = function(bufnr)
        vim.keymap.set('n', '<leader>mt', function()
          vim.ui.input({ prompt = 'Table size (cols x rows): ' }, function(input)
            if not input or input == '' then
              return
            end
            local cols, rows = input:match '^(%d+)[%s,xX]+(%d+)$'
            if cols and rows then
              vim.cmd('MkdnTable ' .. cols .. ' ' .. rows)
            else
              vim.notify("Invalid table dimensions. Use 'cols x rows' (e.g., 3x2) or 'cols rows' (e.g., 3 2)", vim.log.levels.ERROR)
            end
          end)
        end, { buffer = bufnr, desc = 'Create Table' })
      end,
      modules = {
        bib = false,
        buffers = false,
        conceal = false,
        cursor = false,
        folds = false,
        foldtext = false,
        links = false,
        lists = true,
        maps = true,
        paths = false,
        tables = true,
        yaml = false,
        completion = false,
      },
      mappings = {
        MkdnEnter = { 'i', '<CR>' },
        MkdnGoBack = false,
        MkdnGoForward = false,
        MkdnMoveSource = false,
        MkdnNextLink = false,
        MkdnPrevLink = false,
        MkdnFollowLink = false,
        MkdnDestroyLink = false,
        MkdnTagSpan = false,
        MkdnYankAnchorLink = false,
        MkdnYankFileAnchorLink = false,
        MkdnNextHeading = false,
        MkdnPrevHeading = false,
        MkdnNextHeadingSame = false,
        MkdnPrevHeadingSame = false,
        MkdnIncreaseHeading = false,
        MkdnDecreaseHeading = false,
        MkdnIncreaseHeadingOp = false,
        MkdnDecreaseHeadingOp = false,
        MkdnToggleToDo = false,
        MkdnNewListItem = false,
        MkdnNewListItemBelowInsert = false,
        MkdnNewListItemAboveInsert = false,
        MkdnExtendList = false,
        MkdnUpdateNumbering = { 'n', '<leader>mu' },
        MkdnTableNextCell = false,
        MkdnTablePrevCell = false,
        MkdnTableCellNewLine = { 'i', '<M-CR>' },
        MkdnTableNextRow = false,
        MkdnTablePrevRow = false,
        MkdnTableNewRowBelow = { 'n', '<leader>mr' },
        MkdnTableNewRowAbove = { 'n', '<leader>ma' },
        MkdnTableNewColAfter = { 'n', '<leader>mc' },
        MkdnTableNewColBefore = { 'n', '<leader>mb' },
        MkdnTableDeleteRow = { 'n', '<leader>md' },
        MkdnTableDeleteCol = { 'n', '<leader>mx' },
        MkdnTableAlignLeft = false,
        MkdnTableAlignRight = false,
        MkdnTableAlignCenter = false,
        MkdnTableAlignDefault = false,
        MkdnFoldSection = false,
        MkdnUnfoldSection = false,
        MkdnTab = false,
        MkdnSTab = false,
        MkdnIndentListItem = false,
        MkdnDedentListItem = false,
        MkdnCreateLink = false,
        MkdnCreateLinkFromClipboard = false,
      },
    },
  },
}
