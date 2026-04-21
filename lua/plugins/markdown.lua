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
        MkdnEnter = { { 'n', 'v', 'i' }, '<CR>' },
        MkdnNextLink = false,
        MkdnPrevLink = false,
        MkdnGoBack = false,
        MkdnGoForward = false,
        MkdnCreateLinkFromClipboard = false,
        MkdnDestroyLink = false,
        MkdnTagSpan = false,
        MkdnMoveSource = false,
        MkdnYankAnchorLink = false,
        MkdnYankFileAnchorLink = false,
        MkdnIncreaseHeading = false,
        MkdnDecreaseHeading = false,
        MkdnToggleToDo = false,
        MkdnNewListItemBelowInsert = false,
        MkdnNewListItemAboveInsert = false,
        MkdnTableCellNewLine = false,
        MkdnUpdateNumbering = { 'n', '<leader>mu' },
        MkdnTableNextCell = { 'i', '<Tab>' },
        MkdnTablePrevCell = { 'i', '<S-Tab>' },
        MkdnTableNewRowBelow = { 'n', '<leader>mr' },
        MkdnTableNewRowAbove = { 'n', '<leader>mR' },
        MkdnTableNewColAfter = { 'n', '<leader>mc' },
        MkdnTableNewColBefore = { 'n', '<leader>mC' },
        MkdnFoldSection = false,
        MkdnUnfoldSection = false,
      },
      perspective = {
        priority = 'current',
      },
      links = {
        transform_explicit = function(text)
          text = text:gsub('%S+', function(w)
            return w:sub(1, 1):upper() .. w:sub(2):lower()
          end)
          text = text:gsub(' ', '')
          local folder = 'unorganised/'
          text = folder .. os.date '%d-%m-%Y_' .. text
          return text
        end,
      },
      new_file_template = {
        use_template = true,
        placeholders = {
          title = 'link_title',
          date = 'os_date',
          filename = function()
            local text = vim.api.nvim_buf_get_name(0)
            local pattern = '_([^_]+)%.md$'
            local name = text:match(pattern)

            local result = ''
            for i = 1, #name do
              local char = name:sub(i, i)
              if i > 1 and char:match '%u' then
                result = result .. ' ' .. char
              else
                result = result .. char
              end
            end
            return result
          end,
        },
        template = '# {{ filename }}',
      },
    },
  },
}
