return {
  'MagicDuck/grug-far.nvim',
  cmd = { 'GrugFar', 'GrugFarWithin' },
  keys = {
    {
      '<leader>fs',
      function()
        local is_visual = vim.fn.mode():match '[vV\22]' ~= nil
        if is_visual then
          local ok, grug = pcall(require, 'grug-far')
          if ok and grug.get_current_visual_selection then
            local search_txt = grug.get_current_visual_selection(true)
            vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'nx', false)
            if _G.RightPanel and _G.RightPanel.open_grugfar then
              _G.RightPanel.open_grugfar(true, { prefills = { search = search_txt } })
              return
            end
          end
        end
        if _G.RightPanel and _G.RightPanel.open_grugfar then
          _G.RightPanel.open_grugfar()
        else
          vim.cmd 'GrugFar'
        end
      end,
      mode = { 'n', 'v' },
      desc = 'Search & Replace (GrugFar)',
    },
    {
      '<leader>fW',
      function()
        local word = vim.fn.expand '<cword>'
        if _G.RightPanel and _G.RightPanel.open_grugfar then
          _G.RightPanel.open_grugfar(true, { prefills = { search = word } })
        else
          require('grug-far').open { prefills = { search = word } }
        end
      end,
      desc = 'Replace Word Under Cursor',
    },
  },
  opts = {
    windowCreationCommand = 'botright vsplit | setlocal nowinfixbuf',
    showCompactInputs = true,
    startInInsertMode = false,
    wrap = true,
    transient = false,
    folding = {
      enabled = true,
      foldlevel = 1,
      foldcolumn = '1',
      include_file_path = true,
    },
    openTargetWindow = {
      preferredLocation = 'left',
      exclude = {
        'NeogitStatus',
        'NeogitPopup',
        'dockyard',
        'dockyard-logs',
        'dockyard-files',
        'dockyard_popup',
        'sqmeow-drawer',
        'sqmeow-result',
        'dbui',
        'dbout',
        'qf',
        'snacks_picker_list',
        'snacks_terminal',
        function(win)
          local ok, layout = pcall(require, 'utils.layout')
          if ok and layout.get_win_info then
            local info = layout.get_win_info(win)
            return not info.is_editor
          end
          return false
        end,
      },
    },
    keymaps = {
      replace = { n = '<localleader>r' },
      qflist = { n = 'gq' },
      syncLocations = { n = '<localleader>s' },
      syncLine = { n = '<localleader>l' },
      close = { n = 'q' },
      historyOpen = { n = '<localleader>t' },
      historyAdd = { n = '<localleader>a' },
      refresh = { n = 'R' },
      openLocation = { n = '<localleader>o' },
      openNextLocation = { n = '<down>' },
      openPrevLocation = { n = '<up>' },
      gotoLocation = { n = '<enter>' },
      pickHistoryEntry = { n = '<enter>' },
      abort = { n = '<localleader>b' },
      help = { n = 'g?' },
      toggleShowCommand = { n = '<localleader>w' },
      swapEngine = { n = '<localleader>e' },
      previewLocation = { n = 'K' },
      swapReplacementInterpreter = { n = '<localleader>x' },
      applyNext = { n = '<localleader>j' },
      applyPrev = { n = '<localleader>k' },
      syncNext = { n = '<localleader>n' },
      syncPrev = { n = '<localleader>p' },
      syncFile = { n = '<localleader>v' },
      nextInput = { n = '<tab>' },
      prevInput = { n = '<s-tab>' },
    },
  },
  config = function(_, opts)
    require('grug-far').setup(opts)

    local group = vim.api.nvim_create_augroup('UserGrugFarRightPanel', { clear = true })

    vim.api.nvim_create_autocmd('FileType', {
      group = group,
      pattern = 'grug-far',
      callback = function(ev)
        local buf = ev.buf
        vim.b[buf].panel_zone = 'right'
        vim.b[buf].panel_type = 'grugfar'
        vim.bo[buf].buflisted = false

        -- `q`: Close the Right Panel and focus the left Editor window
        vim.keymap.set('n', 'q', function()
          if _G.RightPanel and _G.RightPanel.close_all then
            _G.RightPanel.close_all()
            local ed = _G.RightPanel.get_editor_win and _G.RightPanel.get_editor_win()
            if ed and vim.api.nvim_win_is_valid(ed) then
              vim.api.nvim_set_current_win(ed)
            end
          else
            pcall(function()
              require('grug-far').get_instance(buf):close()
            end)
          end
        end, { buffer = buf, silent = true, nowait = true, desc = 'Close GrugFar Panel' })

        -- Helper to check if cursor is in the results list (below the inputs separator)
        local function is_in_results_area()
          local ok_inst, inst = pcall(function()
            return require('grug-far').get_instance(buf)
          end)
          if not ok_inst or not inst or not inst._context then
            return false
          end
          local ok_in, inputs = pcall(require, 'grug-far.inputs')
          if not ok_in or not inputs.getHeaderRow then
            return false
          end
          local header_row = inputs.getHeaderRow(inst._context, buf)
          local cur_row = vim.api.nvim_win_get_cursor(0)[1]
          return cur_row > (header_row + 1), inst
        end

        -- `l` in Normal mode:
        -- - In inputs area: normal `l` (move cursor right)
        -- - In results area: unfold file if folded (`zo`), otherwise open location in left Editor window while staying in Right Panel!
        vim.keymap.set('n', 'l', function()
          local in_results, inst = is_in_results_area()
          if not in_results then
            vim.cmd 'normal! l'
            return
          end
          local line = vim.api.nvim_win_get_cursor(0)[1]
          if vim.fn.foldclosed(line) ~= -1 then
            pcall(vim.cmd, 'normal! zo')
          elseif inst and inst.open_location then
            inst:open_location()
          end
        end, { buffer = buf, silent = true, nowait = true, desc = 'Unfold or Open Result in Editor' })

        -- `h` in Normal mode:
        -- - In inputs area: normal `h` (move cursor left)
        -- - In results area: collapse file fold (`zc`)!
        vim.keymap.set('n', 'h', function()
          local in_results = is_in_results_area()
          if not in_results then
            vim.cmd 'normal! h'
            return
          end
          local line = vim.api.nvim_win_get_cursor(0)[1]
          if vim.fn.foldlevel(line) > 0 and vim.fn.foldclosed(line) == -1 then
            pcall(vim.cmd, 'normal! zc')
          end
        end, { buffer = buf, silent = true, nowait = true, desc = 'Collapse File Fold' })
      end,
    })

    vim.api.nvim_create_autocmd('FileType', {
      group = group,
      pattern = { 'grug-far-history', 'grug-far-help' },
      callback = function(ev)
        local buf = ev.buf
        vim.bo[buf].buflisted = false
        vim.keymap.set('n', 'q', function()
          pcall(vim.api.nvim_win_close, 0, true)
        end, { buffer = buf, silent = true, nowait = true })
        vim.keymap.set('n', '<Esc>', function()
          pcall(vim.api.nvim_win_close, 0, true)
        end, { buffer = buf, silent = true, nowait = true })
        if vim.bo[buf].filetype == 'grug-far-history' then
          vim.keymap.set('n', 'l', '<CR>', { buffer = buf, remap = true, silent = true, nowait = true })
        end
      end,
    })
  end,
}
