-- lua/utils/sql-cell-inspector.lua
-- Read-only JSON / XML / Long-Text Cell Inspector for sqmeow.nvim result grids.

local M = {}

local function format_json_lua(val, indent)
  indent = indent or 0
  local t = type(val)
  if val == nil or val == vim.NIL then
    return 'null'
  elseif t == 'boolean' or t == 'number' then
    return tostring(val)
  elseif t == 'string' then
    return vim.json.encode(val)
  elseif t == 'table' then
    local is_array = vim.islist(val)
    local pad = ('  '):rep(indent + 1)
    local close_pad = ('  '):rep(indent)
    if is_array then
      if #val == 0 then
        return '[]'
      end
      local items = {}
      for _, v in ipairs(val) do
        table.insert(items, pad .. format_json_lua(v, indent + 1))
      end
      return '[\n' .. table.concat(items, ',\n') .. '\n' .. close_pad .. ']'
    else
      local keys = vim.tbl_keys(val)
      if #keys == 0 then
        return '{}'
      end
      table.sort(keys)
      local items = {}
      for _, k in ipairs(keys) do
        table.insert(items, pad .. vim.json.encode(tostring(k)) .. ': ' .. format_json_lua(val[k], indent + 1))
      end
      return '{\n' .. table.concat(items, ',\n') .. '\n' .. close_pad .. '}'
    end
  end
  return vim.json.encode(tostring(val))
end

local function pretty_json(raw)
  if vim.fn.executable('jq') == 1 then
    local res = vim.system({ 'jq', '.' }, { stdin = raw, text = true }):wait()
    if res.code == 0 and res.stdout and res.stdout ~= '' then
      return vim.trim(res.stdout), true
    end
  end
  local ok, decoded = pcall(vim.json.decode, raw)
  if ok then
    return format_json_lua(decoded, 0), true
  end
  return raw, false
end

local function minify_json(raw)
  local ok, decoded = pcall(vim.json.decode, raw)
  if ok then
    local ok_enc, encoded = pcall(vim.json.encode, decoded)
    if ok_enc then
      return encoded
    end
  end
  return raw
end

local function pretty_xml_lua(raw)
  local s = raw:gsub('>%s+<', '><')
  local out = {}
  local depth = 0
  local i = 1
  local len = #s
  while i <= len do
    local lt = s:find('<', i, true)
    if not lt then
      local txt = vim.trim(s:sub(i))
      if txt ~= '' then
        table.insert(out, ('  '):rep(depth) .. txt)
      end
      break
    end
    if lt > i then
      local txt = vim.trim(s:sub(i, lt - 1))
      if txt ~= '' then
        table.insert(out, ('  '):rep(depth) .. txt)
      end
    end
    local gt = s:find('>', lt, true)
    if not gt then
      table.insert(out, ('  '):rep(depth) .. s:sub(lt))
      break
    end
    local tag = s:sub(lt, gt)
    if tag:match('^<%?') or tag:match('^<!') then
      table.insert(out, ('  '):rep(depth) .. tag)
    elseif tag:match('^<%/') then
      depth = math.max(0, depth - 1)
      table.insert(out, ('  '):rep(depth) .. tag)
    elseif tag:match('%/>$') then
      table.insert(out, ('  '):rep(depth) .. tag)
    else
      -- Check if inline text + immediate closing tag: <Tag>text</Tag>
      local tag_name = tag:match('^<([%w_:.-]+)')
      local next_lt = s:find('<', gt + 1, true)
      if tag_name and next_lt then
        local close_pat = '</' .. tag_name .. '>'
        if s:sub(next_lt, next_lt + #close_pat - 1) == close_pat then
          local inner = s:sub(gt + 1, next_lt - 1)
          table.insert(out, ('  '):rep(depth) .. tag .. inner .. close_pat)
          i = next_lt + #close_pat
          goto continue
        end
      end
      table.insert(out, ('  '):rep(depth) .. tag)
      depth = depth + 1
    end
    i = gt + 1
    ::continue::
  end
  return table.concat(out, '\n')
end

local function pretty_xml(raw)
  if vim.fn.executable('xmllint') == 1 then
    local res = vim.system({ 'xmllint', '--format', '-' }, { stdin = raw, text = true }):wait()
    if res.code == 0 and res.stdout and res.stdout ~= '' then
      return vim.trim(res.stdout)
    end
  end
  return pretty_xml_lua(raw)
end

local function detect_and_format(val)
  if val == nil or val == vim.NIL then
    return 'NULL', 'NULL', 'text', 'NULL'
  end
  local raw = (type(val) == 'table') and vim.json.encode(val) or tostring(val)
  local trimmed = vim.trim(raw)

  if trimmed:match('^%{') or trimmed:match('^%[') then
    local formatted, ok = pretty_json(trimmed)
    if ok then
      return formatted, minify_json(trimmed), 'json', 'JSON'
    end
  end

  if trimmed:match('^<[%w%?%!_]') and trimmed:match('>$') then
    local formatted = pretty_xml(trimmed)
    local minified = trimmed:gsub('>%s+<', '><')
    return formatted, minified, 'xml', 'XML'
  end

  local ft = trimmed:match('^#%s+') and 'markdown' or 'text'
  return raw:gsub('\r\n', '\n'), raw:gsub('\r\n', '\n'), ft, ft == 'markdown' and 'Markdown' or 'Text'
end

function M.inspect_current_cell()
  local ok_res, result = pcall(require, 'sqmeow.ui.result')
  if not ok_res or not result or not result.current_cell then
    vim.notify('sqmeow result grid is not active', vim.log.levels.WARN, { title = 'Cell Inspector' })
    return
  end

  local cell = result.current_cell()
  if not cell then
    vim.notify('Place cursor on a data cell in the result grid', vim.log.levels.INFO, { title = 'Cell Inspector' })
    return
  end

  local formatted, minified, ft, kind_label = detect_and_format(cell.value)
  local col_name = cell.name or ('col_' .. tostring((cell.column or 0) + 1))
  local row_num = (cell.row ~= nil) and (cell.row + 1) or '?'
  local buf_name = ('[Cell: %s · row %s (%s)]'):format(col_name, tostring(row_num), kind_label)

  local existing = vim.fn.bufnr('^' .. vim.pesc(buf_name) .. '$')
  if existing ~= -1 and vim.api.nvim_buf_is_valid(existing) then
    pcall(vim.api.nvim_buf_delete, existing, { force = true })
  end

  local prev_win = vim.api.nvim_get_current_win()
  local ed_win = (_G.RightPanel and _G.RightPanel.get_editor_win and _G.RightPanel.get_editor_win()) or prev_win
  local prev_ed_buf = (ed_win and vim.api.nvim_win_is_valid(ed_win)) and vim.api.nvim_win_get_buf(ed_win) or nil

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = ft
  vim.b[buf].is_sql_inspector = true
  pcall(vim.api.nvim_buf_set_name, buf, buf_name)

  local lines = vim.split(formatted, '\n', { plain = true })
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  if ed_win and vim.api.nvim_win_is_valid(ed_win) then
    if vim.fn.exists('&winfixbuf') == 1 then
      vim.wo[ed_win].winfixbuf = false
    end
    vim.api.nvim_win_set_buf(ed_win, buf)
    vim.api.nvim_set_current_win(ed_win)
    vim.wo[ed_win].wrap = (ft == 'text' or ft == 'markdown')
    vim.wo[ed_win].linebreak = true
    vim.wo[ed_win].spell = false
    if ft == 'json' or ft == 'xml' then
      pcall(vim.treesitter.start, buf)
      vim.wo[ed_win].foldenable = true
      vim.wo[ed_win].foldlevel = 99
    end
  end

  local function close_inspector()
    if ed_win and vim.api.nvim_win_is_valid(ed_win) and vim.api.nvim_win_get_buf(ed_win) == buf then
      if prev_ed_buf and prev_ed_buf ~= buf and vim.api.nvim_buf_is_valid(prev_ed_buf) then
        vim.api.nvim_win_set_buf(ed_win, prev_ed_buf)
      else
        vim.api.nvim_win_call(ed_win, function()
          vim.cmd.enew()
        end)
      end
    end
    if vim.api.nvim_buf_is_valid(buf) then
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
    if prev_win and vim.api.nvim_win_is_valid(prev_win) then
      vim.api.nvim_set_current_win(prev_win)
    end
  end

  vim.keymap.set('n', 'q', close_inspector, { buffer = buf, silent = true, nowait = true, desc = 'Close Cell Inspector' })
  vim.keymap.set('n', '<Esc>', close_inspector, { buffer = buf, silent = true, nowait = true, desc = 'Close Cell Inspector' })
  vim.keymap.set('n', 'y', function()
    vim.fn.setreg('+', formatted)
    vim.fn.setreg('"', formatted)
    vim.notify('Yanked formatted ' .. kind_label .. ' (' .. col_name .. ')', vim.log.levels.INFO, { title = 'Cell Inspector' })
  end, { buffer = buf, silent = true, nowait = true, desc = 'Yank formatted cell' })
  vim.keymap.set('n', 'Y', function()
    vim.fn.setreg('+', minified)
    vim.fn.setreg('"', minified)
    vim.notify('Yanked minified ' .. kind_label .. ' (' .. col_name .. ')', vim.log.levels.INFO, { title = 'Cell Inspector' })
  end, { buffer = buf, silent = true, nowait = true, desc = 'Yank minified cell' })

  vim.notify(
    ('%s (%s · %d lines) — q close · y yank · Y minified · za fold'):format(col_name, kind_label, #lines),
    vim.log.levels.INFO,
    { title = 'Cell Inspector' }
  )
end

return M
