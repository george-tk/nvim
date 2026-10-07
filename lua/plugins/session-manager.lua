return {
  'folke/persistence.nvim',
  event = 'BufReadPre',
  opts = {
    need = 1, -- Only save session when at least 1 real file is open
    branch = true,
  },
  config = function(_, opts)
    local persistence = require('persistence')
    persistence.setup(opts)

    local function is_real_file_buf(b)
      if not b or not vim.api.nvim_buf_is_valid(b) or not vim.bo[b].buflisted or vim.bo[b].buftype ~= '' then
        return false
      end
      local name = vim.api.nvim_buf_get_name(b)
      if name == '' or name:match('^%[') or name:find('/db_ui/') or name:match('%.sqlite%d?$') or name:match('%.db$') then
        return false
      end
      return true
    end

    local function has_real_bufs()
      for _, b in ipairs(vim.api.nvim_list_bufs()) do
        if is_real_file_buf(b) then
          return true
        end
      end
      return false
    end

    local function cleanup_transient_bufs()
      for _, b in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(b) then
          local ft = vim.bo[b].filetype
          local name = vim.api.nvim_buf_get_name(b)
          if ft == 'sqmeow-drawer' or ft == 'sqmeow-result' or ft == 'dbui' or ft == 'dbout'
            or (vim.b[b].is_preview_buffer and vim.bo[b].buftype == 'nofile')
            or (name:match('^%[Preview:') and vim.bo[b].buftype == 'nofile')
          then
            pcall(vim.api.nvim_buf_delete, b, { force = true })
          end
        end
      end
    end

    local function safe_save()
      if has_real_bufs() then
        pcall(function() persistence.save() end)
      end
    end

    local save_timer = vim.uv.new_timer()
    local function debounced_save(delay_ms)
      if not save_timer then return end
      save_timer:stop()
      save_timer:start(delay_ms or 1000, 0, vim.schedule_wrap(function()
        safe_save()
      end))
    end

    local group = vim.api.nvim_create_augroup('UserPersistenceAutoSave', { clear = true })

    -- Save on FocusLost (switching away from Neovim or terminal window)
    vim.api.nvim_create_autocmd('FocusLost', {
      group = group,
      callback = function()
        safe_save()
      end,
      desc = 'Auto-save session on focus lost',
    })

    -- Debounced auto-save on BufWritePost (saving files)
    vim.api.nvim_create_autocmd('BufWritePost', {
      group = group,
      callback = function()
        debounced_save(1000)
      end,
      desc = 'Debounced auto-save session on file write',
    })

    -- Debounced auto-save on buffer lifecycle changes (opening/closing buffers)
    vim.api.nvim_create_autocmd({ 'BufDelete', 'BufWipeout' }, {
      group = group,
      callback = function()
        debounced_save(1000)
      end,
      desc = 'Debounced auto-save session on buffer delete',
    })

    vim.api.nvim_create_autocmd('BufReadPost', {
      group = group,
      callback = function(args)
        if is_real_file_buf(args.buf) then
          debounced_save(1500)
        end
      end,
      desc = 'Debounced auto-save session on buffer read',
    })

    -- Clean transient buffers before Persistence saves
    vim.api.nvim_create_autocmd('User', {
      group = group,
      pattern = 'PersistenceSavePre',
      callback = function()
        cleanup_transient_bufs()
      end,
      desc = 'Clean transient buffers before saving session',
    })

    -- Clean empty unnamed placeholder buffers and seed buffer ring after session loads
    vim.api.nvim_create_autocmd('User', {
      group = group,
      pattern = 'PersistenceLoadPost',
      callback = function()
        for _, b in ipairs(vim.api.nvim_list_bufs()) do
          if vim.api.nvim_buf_is_valid(b)
            and vim.bo[b].buflisted
            and vim.api.nvim_buf_get_name(b) == ''
            and not vim.bo[b].modified
            and vim.bo[b].buftype == ''
            and vim.api.nvim_buf_line_count(b) <= 1
            and (vim.api.nvim_buf_get_lines(b, 0, 1, false)[1] or '') == ''
          then
            pcall(vim.api.nvim_buf_delete, b, { force = true })
          end
        end

        local ok_ring, ring = pcall(require, 'utils.buffer-ring')
        if ok_ring and ring then
          ring.clean_slots()
          for _, b in ipairs(vim.api.nvim_list_bufs()) do
            if vim.api.nvim_buf_is_valid(b) and vim.bo[b].buflisted and ring.is_qualifying(b) then
              ring.on_buf_enter(b)
            end
          end
          pcall(function() require('lualine').refresh() end)
        end
      end,
      desc = 'Clean placeholder buffers and seed buffer ring after session load',
    })

    -- Save outgoing session before directory changes
    vim.api.nvim_create_autocmd('DirChangedPre', {
      group = group,
      callback = function()
        safe_save()
      end,
      desc = 'Auto-save session before directory change',
    })
  end,
}
