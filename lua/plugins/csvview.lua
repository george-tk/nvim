return {
  'hat0uma/csvview.nvim',
  ft = { 'csv', 'tsv' },
  cmd = { 'CsvViewEnable', 'CsvViewDisable', 'CsvViewToggle' },
  keys = {
    {
      '<leader>cv',
      '<cmd>CsvViewToggle<CR>',
      ft = { 'csv', 'tsv' },
      desc = 'Toggle CSV Table / Raw View',
    },
  },
  opts = {
    parser = {
      comments = { '#', '//' },
    },
    view = {
      display_mode = 'border',
    },
    keymaps = {
      textobject_field_inner = { 'if', mode = { 'o', 'x' } },
      textobject_field_outer = { 'af', mode = { 'o', 'x' } },
      jump_next_field_end = { '<Tab>', mode = { 'n', 'v' } },
      jump_prev_field_end = { '<S-Tab>', mode = { 'n', 'v' } },
      jump_next_row = { '<Enter>', mode = { 'n', 'v' } },
      jump_prev_row = { '<S-Enter>', mode = { 'n', 'v' } },
    },
  },
  config = function(_, opts)
    local csvview = require 'csvview'
    csvview.setup(opts)

    local raw_ns = vim.api.nvim_create_namespace 'UserCsvRawRainbow'

    local function paint_raw_rainbow(buf)
      if not (buf and vim.api.nvim_buf_is_valid(buf)) then
        return
      end
      vim.api.nvim_buf_clear_namespace(buf, raw_ns, 0, -1)
      if csvview.is_enabled(buf) then
        return
      end
      local delim = vim.bo[buf].filetype == 'tsv' and '\t' or ','
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      for lnum, line in ipairs(lines) do
        local col_idx = 0
        local start_col = 0
        local in_quote = false
        local i = 1
        local len = #line
        while i <= len do
          local ch = line:sub(i, i)
          if ch == '"' then
            if in_quote and line:sub(i + 1, i + 1) == '"' then
              i = i + 1
            else
              in_quote = not in_quote
            end
          elseif ch == delim and not in_quote then
            if i - 1 > start_col then
              vim.api.nvim_buf_set_extmark(buf, raw_ns, lnum - 1, start_col, {
                end_col = i - 1,
                hl_group = 'CsvViewCol' .. (col_idx % 9),
              })
            end
            col_idx = col_idx + 1
            start_col = i
          end
          i = i + 1
        end
        if len > start_col then
          vim.api.nvim_buf_set_extmark(buf, raw_ns, lnum - 1, start_col, {
            end_col = len,
            hl_group = 'CsvViewCol' .. (col_idx % 9),
          })
        end
      end
    end

    -- Keep rainbow column highlights active whenever toggled to raw mode
    local orig_enable = csvview.enable
    csvview.enable = function(bufnr, enable_opts)
      local res = orig_enable(bufnr, enable_opts)
      local b = bufnr or vim.api.nvim_get_current_buf()
      if vim.api.nvim_buf_is_valid(b) then
        vim.api.nvim_buf_clear_namespace(b, raw_ns, 0, -1)
      end
      return res
    end

    local orig_disable = csvview.disable
    csvview.disable = function(bufnr)
      local res = orig_disable(bufnr)
      paint_raw_rainbow(bufnr or vim.api.nvim_get_current_buf())
      return res
    end

    local group = vim.api.nvim_create_augroup('UserCsvViewAuto', { clear = true })
    vim.api.nvim_create_autocmd('FileType', {
      group = group,
      pattern = { 'csv', 'tsv' },
      callback = function(ev)
        if not csvview.is_enabled(ev.buf) then
          csvview.enable(ev.buf)
        end
      end,
      desc = 'Enable CsvView automatically for CSV/TSV files',
    })

    vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI' }, {
      group = group,
      pattern = { '*.csv', '*.tsv' },
      callback = function(ev)
        if not csvview.is_enabled(ev.buf) then
          paint_raw_rainbow(ev.buf)
        end
      end,
      desc = 'Refresh rainbow highlights while editing raw CSV/TSV',
    })

    -- Enable immediately for the buffer that triggered lazy ft load
    local cur = vim.api.nvim_get_current_buf()
    local ft = vim.bo[cur].filetype
    if (ft == 'csv' or ft == 'tsv') and not csvview.is_enabled(cur) then
      csvview.enable(cur)
    end
  end,
}
