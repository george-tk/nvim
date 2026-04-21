-- Configuration and UI tokens live at the top of the file so visual and
-- behavioral tuning happens in one place.
local Config = {
  filetypes = { 'markdown', 'text', 'tex', 'plaintex', 'norg' },
  date_format = '%y/%m/%d',
  done_retention_days = 10,
  todo_json_name = 'todo.json',
  statuses = {
    todo = 'TODO',
    blocked = 'BLOCKED',
    doing = 'DOING',
    peer_review = 'PEER_REVIEW',
    done = 'DONE',
  },
  priorities = {
    low = 'LOW',
    medium = 'MEDIUM',
    high = 'HIGH',
  },
  picker_badges = {
    low = '  ',
    medium = '🟡',
    high = '🔴',
  },
}

local STATUS_TODO = Config.statuses.todo
local STATUS_BLOCKED = Config.statuses.blocked
local STATUS_DOING = Config.statuses.doing
local STATUS_PEER_REVIEW = Config.statuses.peer_review
local STATUS_DONE = Config.statuses.done

local PRIORITY_LOW = Config.priorities.low
local PRIORITY_MEDIUM = Config.priorities.medium
local PRIORITY_HIGH = Config.priorities.high

local STATUS_SORT = {
  [STATUS_TODO] = 0,
  [STATUS_BLOCKED] = 1,
  [STATUS_DOING] = 2,
  [STATUS_PEER_REVIEW] = 3,
  [STATUS_DONE] = 4,
}

local PRIORITY_SORT = {
  [PRIORITY_HIGH] = 1,
  [PRIORITY_MEDIUM] = 2,
  [PRIORITY_LOW] = 3,
}

local STATUS_NEXT = {
  [STATUS_TODO] = STATUS_BLOCKED,
  [STATUS_BLOCKED] = STATUS_DOING,
  [STATUS_DOING] = STATUS_PEER_REVIEW,
  [STATUS_PEER_REVIEW] = STATUS_DONE,
  [STATUS_DONE] = STATUS_TODO,
}
local PRIORITY_NEXT = { [PRIORITY_LOW] = PRIORITY_MEDIUM, [PRIORITY_MEDIUM] = PRIORITY_HIGH, [PRIORITY_HIGH] = PRIORITY_LOW }
local STATUS_COLOR = {
  [0] = 'TodoStatusInfo',
  [1] = 'TodoStatusBlocked',
  [2] = 'TodoStatusWarn',
  [3] = 'TodoStatusPeerReview',
  [4] = 'TodoStatusDone',
}
local STATUS_LABEL = {
  [STATUS_TODO] = 'Todo',
  [STATUS_BLOCKED] = 'Blocked',
  [STATUS_DOING] = 'Doing',
  [STATUS_PEER_REVIEW] = 'Peer Review',
  [STATUS_DONE] = 'Done',
}
local PRIORITY_BADGE = { [PRIORITY_HIGH] = Config.picker_badges.high, [PRIORITY_MEDIUM] = Config.picker_badges.medium, [PRIORITY_LOW] = Config.picker_badges.low }
local PRIORITY_HL = { [PRIORITY_HIGH] = 'DiagnosticError', [PRIORITY_MEDIUM] = 'DiagnosticWarn', [PRIORITY_LOW] = 'NonText' }
local PARENT_HINT_HL = 'TodoParentHint'
local TITLE_HL_BLOCKED = 'TodoTitleBlocked'
local TITLE_HL_PEER_REVIEW = 'TodoTitlePeerReview'

local STATUS_SOURCE_HL = {
  [0] = 'DiagnosticInfo',
  [1] = 'DiagnosticError',
  [2] = 'DiagnosticWarn',
  [3] = 'Directory',
  [4] = 'Comment',
}

local UI = {
  picker = {
      title = 'TODOs · / search · Enter log · S status · P priority · p parent · o order · x done-cycle · f filter · t task · a subtask · e source · m reference',
    row_gap = ' ',
    progress_sep = '  ',
    message_indent = 5,
    layout = {
      cycle = true,
      preview = false,
      hidden = { 'preview' },
      auto_hide = { 'input' },
      layout = {
        backdrop = false,
        width = 0.58,
        min_width = 88,
        max_width = 120,
        height = 0.72,
        min_height = 14,
        box = 'vertical',
        border = 'rounded',
        title = '{title} {live} {flags}',
        title_pos = 'center',
        { win = 'input', height = 1, border = 'bottom' },
        { win = 'list', border = 'none' },
        { win = 'preview', title = '{preview}', height = 0.45, border = 'top' },
      },
    },
    tree = {
      base = '  ',
      indent_step = '  ',
      open = '▾ ',
      closed = '▸ ',
      leaf = '↳ ',
    },
  },
  panel = {
    title = 'Task Details',
    border = 'rounded',
    indent = '  ',
    details_indent = '  ',
    section_sep_char = '─',
    meta_label_width = 10,
    inner_width_min = 40,
    inner_width_max = 56,
    inner_width_ratio = 0.62,
    float_width_ratio = 0.82,
    float_height_ratio = 0.76,
    min_height = 14,
    breakindentopt = 'shift:2,min:18',
  },
}

local CORE_FIELDS = {
  item = true,
  status = true,
  priority = true,
  created = true,
  completed = true,
  id = true,
  parent = true,
  description = true,
  log = true,
  labels = true,
}

-- Mutable UI state and forward declarations for helpers referenced before their
-- concrete definitions.
local detail_panel_stack = {}
local picker_help_windows = setmetatable({}, { __mode = 'k' })

local TODO_REF_PATTERN = '^%s*TODO:%s*(.-)%s*%(%#([-%w_]+)%)%s*$'

local toggle_todo_status_line
local open_todo_detail
local get_todo_picker_opts
local refresh_picker_items
local get_focus_key_for_item
local item_matches_focus_key
local restore_picker_focus
local capture_picker_reopen_context
local reopen_picker_from_context
local open_todo_picker

local picker_hierarchy_ui_state = {
  collapsed_by_id = {},
  collapse_all = false,
}

local random_seeded = false

-- Generic helpers.
local function today()
  return os.date(Config.date_format)
end

local function notify_todo(message, level)
  vim.notify(message, level or vim.log.levels.INFO, { title = 'TODO' })
end

local function get_highlight_hex(name, attr)
  local hl_id = vim.fn.hlID(name)
  if hl_id == 0 then
    return nil
  end

  local value = vim.fn.synIDattr(hl_id, attr, 'gui')
  if value == '' then
    return nil
  end

  return value
end

local function apply_todo_status_highlights()
  for status, target in pairs(STATUS_COLOR) do
    local source = STATUS_SOURCE_HL[status]
    local spec = {
      fg = get_highlight_hex(source, 'fg#'),
      bg = get_highlight_hex(source, 'bg#'),
      sp = get_highlight_hex(source, 'sp#'),
      italic = false,
    }

    vim.api.nvim_set_hl(0, target, spec)
  end

  vim.api.nvim_set_hl(0, PARENT_HINT_HL, {
    fg = get_highlight_hex('NonText', 'fg#'),
    bg = get_highlight_hex('NonText', 'bg#'),
    sp = get_highlight_hex('NonText', 'sp#'),
    italic = false,
  })

  vim.api.nvim_set_hl(0, TITLE_HL_BLOCKED, {
    fg = get_highlight_hex('DiagnosticError', 'fg#'),
    bg = get_highlight_hex('DiagnosticError', 'bg#'),
    sp = get_highlight_hex('DiagnosticError', 'sp#'),
    italic = false,
  })

  vim.api.nvim_set_hl(0, TITLE_HL_PEER_REVIEW, {
    fg = get_highlight_hex('Directory', 'fg#') or get_highlight_hex('DiagnosticInfo', 'fg#'),
    bg = get_highlight_hex('Directory', 'bg#') or get_highlight_hex('DiagnosticInfo', 'bg#'),
    sp = get_highlight_hex('Directory', 'sp#') or get_highlight_hex('DiagnosticInfo', 'sp#'),
    italic = false,
  })
end

local function title_highlight_for_status(status, fallback)
  if status == STATUS_BLOCKED then
    return TITLE_HL_BLOCKED
  end
  if status == STATUS_PEER_REVIEW then
    return TITLE_HL_PEER_REVIEW
  end
  return fallback or 'Normal'
end

local function is_valid_date(date_str)
  if not date_str then return false end
  local yy, mm, dd = date_str:match('^(%d%d)/(%d%d)/(%d%d)$')
  if not yy then return false end
  local month = tonumber(mm)
  local day = tonumber(dd)
  return month ~= nil and day ~= nil and month >= 1 and month <= 12 and day >= 1 and day <= 31
end

local function parse_date_to_sortkey(date_str)
  if not is_valid_date(date_str) then return -1 end
  local yy, mm, dd = date_str:match('^(%d%d)/(%d%d)/(%d%d)$')
  local year = 2000 + tonumber(yy)
  local month = tonumber(mm)
  local day = tonumber(dd)
  return (year % 100) * 10000 + month * 100 + day
end

local function parse_date_to_time(date_str)
  if not is_valid_date(date_str) then return nil end
  local yy, mm, dd = date_str:match('^(%d%d)/(%d%d)/(%d%d)$')
  return os.time {
    year = 2000 + tonumber(yy),
    month = tonumber(mm),
    day = tonumber(dd),
    hour = 0,
    min = 0,
    sec = 0,
  }
end

local function parse_log_entry(line)
  if type(line) ~= 'string' then
    return nil, nil
  end

  local trimmed = vim.trim(line)
  if trimmed == '' then
    return nil, nil
  end

  local date_str, text = trimmed:match('^%[?(%d%d/%d%d/%d%d)%]?%s*[-:]%s*(.+)$')
  if date_str and is_valid_date(date_str) then
    local message = vim.trim(text or '')
    if message ~= '' then
      return date_str, message
    end
  end

  return nil, trimmed
end

local function format_log_entry(date_str, message)
  return string.format('%s - %s', date_str, vim.trim(message or ''))
end

local function normalize_log_entries(lines, fallback_date)
  local normalized = {}
  local default_date = is_valid_date(fallback_date) and fallback_date or today()

  for _, line in ipairs(lines or {}) do
    local date_str, message = parse_log_entry(tostring(line or ''))
    if message and message ~= '' then
      normalized[#normalized + 1] = format_log_entry(date_str or default_date, message)
    end
  end

  return normalized
end

local function is_valid_todo_id(value)
  return type(value) == 'string' and value:match('^[-_%w]+$') ~= nil
end

local function get_todo_store_path()
  return vim.fs.normalize(vim.fn.getcwd() .. '/' .. Config.todo_json_name)
end

local function read_file_lines(file)
  local handle = io.open(file, 'r')
  if not handle then
    return nil
  end
  local lines = {}
  for line in handle:lines() do
    lines[#lines + 1] = line
  end
  handle:close()
  return lines
end

local function write_text_file(file, text)
  local handle = io.open(file, 'w')
  if not handle then
    return false
  end
  handle:write(text)
  handle:close()
  return true
end

local function get_loaded_bufnr(file)
  if not file or file == '' then
    return nil
  end
  local bufnr = vim.fn.bufnr(file, true)
  vim.fn.bufload(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return nil
  end
  return bufnr
end

local function maybe_write_buffer(bufnr)
  if not bufnr then
    return
  end
  if vim.bo[bufnr].buftype ~= '' or not vim.bo[bufnr].modifiable or vim.bo[bufnr].readonly then
    return
  end
  pcall(vim.api.nvim_buf_call, bufnr, function()
    vim.cmd 'silent noautocmd write'
  end)
end

local function open_source_at(file, lnum)
  if not file or not lnum then
    return
  end
  vim.schedule(function()
    vim.cmd('edit ' .. vim.fn.fnameescape(file))
    vim.api.nvim_win_set_cursor(0, { lnum, 0 })
    vim.cmd 'normal! zz'
  end)
end

local function close_picker_help(picker)
  local help_win = picker_help_windows[picker]
  if help_win and vim.api.nvim_win_is_valid(help_win) then
    vim.api.nvim_win_close(help_win, true)
  end
  picker_help_windows[picker] = nil
end

local function toggle_picker_help(picker)
  if not picker then
    return
  end

  local help_win = picker_help_windows[picker]
  if help_win and vim.api.nvim_win_is_valid(help_win) then
    close_picker_help(picker)
    return
  end

  local help_lines = {
    '  Todo Picker Keys',
    '',
    '  Enter  Open details',
    '  /      Toggle list and search focus',
    '  i      Focus search input',
    '  S      Cycle status',
    '  x      Cycle done visibility (hide/recent/all)',
    '  P      Cycle priority',
    '  r      Set relationship (choose direction + unlink)',
    '  p      Open parent details',
    '  f      Filter field=value',
    '  t      Create sibling task',
    '  a      Create subtask',
    '  g      Group/Ungroup subtasks',
    '  z      Toggle subtasks',
    '  Z      Toggle all subtasks',
    '  D      Delete todo',
    '  e      Open source (todo.json)',
    '  m      Open markdown reference',
    '  ?      Toggle this help',
    '  q      Close picker',
  }

  local max_len = 0
  for _, line in ipairs(help_lines) do
    max_len = math.max(max_len, vim.fn.strdisplaywidth(line))
  end

  local h = #help_lines
  local w = math.max(44, math.min(max_len + 2, math.floor(vim.o.columns * 0.55)))

  local hbuf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(hbuf, 0, -1, false, help_lines)
  vim.bo[hbuf].modifiable = false
  vim.bo[hbuf].bufhidden = 'wipe'
  vim.bo[hbuf].buftype = 'nofile'

  help_win = vim.api.nvim_open_win(hbuf, true, {
    relative = 'editor',
    width = w,
    height = h,
    row = math.floor((vim.o.lines - h) / 2),
    col = math.floor((vim.o.columns - w) / 2),
    style = 'minimal',
    border = UI.panel.border,
    title = ' Picker Help ',
    title_pos = 'center',
    zindex = 210,
  })

  picker_help_windows[picker] = help_win

  local function close_help_window()
    close_picker_help(picker)
    if picker and not picker.closed and picker.focus then
      picker:focus('list')
    end
  end

  vim.keymap.set('n', 'q', close_help_window, { buffer = hbuf, nowait = true, silent = true })
  vim.keymap.set('n', '<Esc>', close_help_window, { buffer = hbuf, nowait = true, silent = true })
  vim.keymap.set('n', '?', close_help_window, { buffer = hbuf, nowait = true, silent = true })
end

local function parse_reference_line(line)
  local title, todo_id = (line or ''):match(TODO_REF_PATTERN)
  if not title or not todo_id then
    return nil
  end
  return {
    title = vim.trim(title),
    todo_id = todo_id,
  }
end

local function build_reference_line(title, todo_id)
  return string.format('TODO: %s (#%s)', vim.trim(title or ''), todo_id or '')
end

-- Store normalization and persistence.
local function default_store()
  return {
    version = 1,
    todos = {},
  }
end

local function normalize_extra_fields(extra_fields)
  local out = {}
  for _, field in ipairs(extra_fields or {}) do
    local name = field.name and tostring(field.name):lower() or ''
    local value = field.value and tostring(field.value) or ''
    if name ~= '' and not CORE_FIELDS[name] then
      out[#out + 1] = { name = name, value = vim.trim(value:gsub('%s+', ' ')) }
    end
  end
  return out
end

local function normalize_labels(labels)
  if type(labels) == 'string' then
    labels = vim.split(labels, ',', { trimempty = true })
  end

  local out = {}
  local seen = {}

  for _, raw in ipairs(labels or {}) do
    local label = vim.trim(tostring(raw or '')):lower()
    if label ~= '' and not seen[label] then
      out[#out + 1] = label
      seen[label] = true
    end
  end

  return out
end

local function normalize_todo(todo)
  local t = vim.deepcopy(todo or {})

  -- IDs are optional on input, but once present they must stay compatible with
  -- the markdown reference format and picker focus keys.
  if not is_valid_todo_id(t.id) then
    t.id = nil
  end
  t.title = vim.trim(t.title or '')

  -- Persisted status/priority values are normalized back onto the supported
  -- enum set so hand-edited JSON degrades safely instead of breaking the UI.
  local status = (t.status or STATUS_TODO):upper()
  if not STATUS_SORT[status] then
    status = STATUS_TODO
  end

  local normalized_labels = normalize_labels(t.labels)

  t.status = status

  local priority = (t.priority or PRIORITY_LOW):upper()
  if not PRIORITY_SORT[priority] then
    priority = PRIORITY_LOW
  end
  t.priority = priority

  -- Only DONE items carry a completed date. Reset stale values when a task is
  -- moved back to an active state.
  t.created = is_valid_date(t.created) and t.created or today()
  if t.status == STATUS_DONE and is_valid_date(t.completed) then
    t.completed = t.completed
  else
    t.completed = nil
  end

  if not is_valid_todo_id(t.parent_id) or t.parent_id == t.id then
    t.parent_id = nil
  end

  t.extra_fields = normalize_extra_fields(t.extra_fields)
  t.labels = normalized_labels

  t.description = vim.trim(t.description and tostring(t.description) or '')

  local raw_log = type(t.log) == 'table' and t.log or t.details
  t.log = normalize_log_entries(raw_log or {}, t.created)
  -- Keep compatibility with any callers still reading `details`.
  t.details = vim.deepcopy(t.log)

  if type(t.source) ~= 'table' then
    t.source = {}
  end
  t.source.file = t.source.file and vim.fs.normalize(t.source.file) or nil
  t.source.lnum = tonumber(t.source.lnum) or nil
  t.source.todo_id = is_valid_todo_id(t.source.todo_id) and t.source.todo_id or nil

  if type(t.reference) ~= 'table' then
    t.reference = {}
  end
  t.reference.file = t.reference.file and vim.fs.normalize(t.reference.file) or nil
  t.reference.lnum = tonumber(t.reference.lnum) or nil

  return t
end

local function ensure_todo_source(todo)
  if type(todo) ~= 'table' then
    return
  end

  todo.source = type(todo.source) == 'table' and todo.source or {}
  todo.source.file = get_todo_store_path()
  todo.source.todo_id = todo.id
  if not todo.source.lnum then
    todo.source.lnum = nil
  end
end

local function is_json_array_table(tbl)
  if type(tbl) ~= 'table' then
    return false
  end

  local count = 0
  local max_index = 0
  for key, _ in pairs(tbl) do
    if type(key) ~= 'number' or key < 1 or key % 1 ~= 0 then
      return false
    end
    count = count + 1
    if key > max_index then
      max_index = key
    end
  end

  return max_index == count
end

local function encode_json_pretty(value, level)
  level = level or 0
  local indent = string.rep('  ', level)
  local child_indent = string.rep('  ', level + 1)
  local value_type = type(value)

  if value_type ~= 'table' then
    return vim.fn.json_encode(value)
  end

  if is_json_array_table(value) then
    if #value == 0 then
      return '[]'
    end

    local lines = { '[' }
    for i, item in ipairs(value) do
      local suffix = (i < #value) and ',' or ''
      lines[#lines + 1] = child_indent .. encode_json_pretty(item, level + 1) .. suffix
    end
    lines[#lines + 1] = indent .. ']'
    return table.concat(lines, '\n')
  end

  local keys = {}
  for key, _ in pairs(value) do
    keys[#keys + 1] = key
  end
  table.sort(keys, function(a, b)
    return tostring(a) < tostring(b)
  end)

  if #keys == 0 then
    return '{}'
  end

  local lines = { '{' }
  for i, key in ipairs(keys) do
    local encoded_key = vim.fn.json_encode(tostring(key))
    local encoded_value = encode_json_pretty(value[key], level + 1)
    local suffix = (i < #keys) and ',' or ''
    lines[#lines + 1] = string.format('%s%s: %s%s', child_indent, encoded_key, encoded_value, suffix)
  end
  lines[#lines + 1] = indent .. '}'
  return table.concat(lines, '\n')
end

local function write_store(store)
  local store_path = get_todo_store_path()
  local ok, encoded = pcall(encode_json_pretty, store)
  if not ok or type(encoded) ~= 'string' then
    notify_todo('Could not encode todo store', vim.log.levels.ERROR)
    return false
  end
  if not write_text_file(store_path, encoded) then
    notify_todo('Could not write ' .. Config.todo_json_name, vim.log.levels.ERROR)
    return false
  end
  return true
end

local function load_store()
  local store_path = get_todo_store_path()
  local lines = read_file_lines(store_path)

  if not lines then
    local created = default_store()
    write_store(created)
    return created
  end

  local raw = table.concat(lines, '\n')
  local ok, decoded = pcall(vim.fn.json_decode, raw)
  if not ok or type(decoded) ~= 'table' then
    notify_todo('Invalid todo.json; resetting store', vim.log.levels.WARN)
    local reset = default_store()
    write_store(reset)
    return reset
  end

  local store = {
    version = tonumber(decoded.version) or 1,
    todos = {},
  }

  for _, todo in ipairs(decoded.todos or {}) do
    local normalized = normalize_todo(todo)
    if normalized.id and normalized.title ~= '' then
      store.todos[#store.todos + 1] = normalized
    end
  end

  return store
end

local get_todo_index

local function with_todo_store(mutator)
  local store = load_store()
  if not store then
    return nil
  end

  local result = mutator(store, get_todo_index(store))
  if result == false then
    return nil
  end

  if not write_store(store) then
    return nil
  end

  return result, store
end

get_todo_index = function(store)
  local by_id = {}
  for idx, todo in ipairs(store.todos or {}) do
    if todo.id then
      by_id[todo.id] = { todo = todo, idx = idx }
    end
  end
  return by_id
end

local function find_todo_bucket(store, todo_id)
  if not store or not todo_id then
    return nil
  end
  return get_todo_index(store)[todo_id]
end

local function build_todo_fields(todo, parent_title)
  local fields = {
    item = todo.title,
    status = todo.status,
    priority = todo.priority,
    created = todo.created,
    completed = todo.completed,
    id = todo.id,
    parent = todo.parent_id,
    parent_title = parent_title,
    labels = table.concat(todo.labels or {}, ', '),
  }
  for _, field in ipairs(todo.extra_fields or {}) do
    fields[field.name] = field.value
  end
  return fields
end

local function generate_todo_id(store)
  if not random_seeded then
    local seed = os.time()
    if vim.uv and vim.uv.hrtime then
      seed = seed + (vim.uv.hrtime() % 1000000)
    end
    math.randomseed(seed)
    random_seeded = true
  end

  local seen = {}
  for _, todo in ipairs(store.todos or {}) do
    if todo.id then
      seen[todo.id] = true
    end
  end
  while true do
    local candidate = string.format('t_%s_%04x', os.date('!%Y%m%d_%H%M%S'), math.random(0, 0xffff))
    if not seen[candidate] then
      return candidate
    end
  end
end

local function find_reference_lnum_in_file(file, todo_id)
  local bufnr = get_loaded_bufnr(file)
  local lines
  if bufnr then
    lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  else
    lines = read_file_lines(file)
  end
  if not lines then
    return nil
  end
  for lnum, line in ipairs(lines) do
    local parsed = parse_reference_line(line)
    if parsed and parsed.todo_id == todo_id then
      return lnum
    end
  end
  return nil
end

-- Reference synchronization and JSON-to-picker item projection.
local function resolve_reference(todo, store)
  if not todo or not todo.id then
    return nil, nil
  end

  local file = todo.reference and todo.reference.file
  local lnum = todo.reference and todo.reference.lnum

  -- Fast path: trust the cached location only if the line still points at this
  -- todo id. This avoids scanning the file on every picker refresh.
  if file and lnum then
    local bufnr = get_loaded_bufnr(file)
    if bufnr and lnum >= 1 and lnum <= vim.api.nvim_buf_line_count(bufnr) then
      local line = vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1] or ''
      local parsed = parse_reference_line(line)
      if parsed and parsed.todo_id == todo.id then
        return file, lnum
      end
    end
  end

  if not file or file == '' then
    return nil, nil
  end

  -- If the cached line drifted after manual edits, rescan the file once and
  -- repair the persisted reference so future lookups stay cheap.
  local found = find_reference_lnum_in_file(file, todo.id)
  if not found then
    return nil, nil
  end

  todo.reference = todo.reference or {}
  todo.reference.file = file
  todo.reference.lnum = found
  write_store(store)
  return file, found
end

local function update_reference_line_for_todo(todo, store)
  if not todo or not todo.id or not todo.reference or not todo.reference.file then
    return
  end

  local file, lnum = resolve_reference(todo, store)
  if not file or not lnum then
    return
  end

  local bufnr = get_loaded_bufnr(file)
  if not bufnr then
    return
  end

  local desired = build_reference_line(todo.title, todo.id)
  local current = vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1] or ''
  if current == desired then
    return
  end

  vim.api.nvim_buf_set_lines(bufnr, lnum - 1, lnum, false, { desired })
  maybe_write_buffer(bufnr)
end

local function adjust_reference_lines_after_insert(store, file, at_lnum, delta, exclude_todo_id)
  if not file or not at_lnum or delta == 0 then
    return
  end

  for _, todo in ipairs(store.todos or {}) do
    if todo.id ~= exclude_todo_id and todo.reference and todo.reference.file == file and todo.reference.lnum and todo.reference.lnum >= at_lnum then
      todo.reference.lnum = todo.reference.lnum + delta
    end
  end
end

local function find_todo_id_lnum_in_store(file, todo_id)
  local bufnr = get_loaded_bufnr(file)
  local lines
  if bufnr then
    lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  else
    lines = read_file_lines(file)
  end
  if not lines then
    return nil
  end

  local id_pattern = '"id"%s*:%s*"' .. vim.pesc(todo_id or '') .. '"'
  for lnum, line in ipairs(lines) do
    if line:match(id_pattern) then
      return lnum
    end
  end

  return nil
end

local function resolve_source(todo)
  if not todo or not todo.id then
    return nil, nil
  end

  local file = (todo.source and todo.source.file) or get_todo_store_path()
  local lnum = todo.source and todo.source.lnum or nil

  if not lnum then
    lnum = find_todo_id_lnum_in_store(file, todo.id)
  end

  return file, lnum
end

local function build_item_from_todo(todo)
  local file = todo.source and todo.source.file or get_todo_store_path()
  local lnum = todo.source and todo.source.lnum or 1

  return {
    file = file,
    pos = { lnum, 1 },
    text = todo.title,
    todo_id = todo.id,
    todo_parent_id = todo.parent_id,
    todo_text = todo.title,
    todo_fields = build_todo_fields(todo),
    todo_extra_fields = todo.extra_fields or {},
    todo_labels = todo.labels or {},
    todo_description = todo.description or '',
    todo_log = todo.log or todo.details or {},
    todo_details = todo.log or todo.details or {},
    todo_reference = {
      file = todo.reference and todo.reference.file,
      lnum = todo.reference and todo.reference.lnum,
    },
    todo_source = {
      file = todo.source and todo.source.file,
      lnum = todo.source and todo.source.lnum,
      todo_id = todo.source and todo.source.todo_id,
    },
  }
end

local function get_todo_item_by_id(todo_id)
  if not todo_id or todo_id == '' then
    return nil
  end

  local store = load_store()
  local bucket = find_todo_bucket(store, todo_id)
  if not bucket then
    return nil
  end

  return build_item_from_todo(bucket.todo)
end

local function create_todo_record(store, spec)
  local todo = normalize_todo(vim.tbl_extend('force', {
    id = generate_todo_id(store),
    title = '',
    status = STATUS_TODO,
    priority = PRIORITY_LOW,
    created = today(),
    completed = nil,
    parent_id = nil,
    description = '',
    log = {},
    labels = {},
    extra_fields = {},
    source = {},
    reference = {},
  }, spec or {}))

  if not todo.id then
    todo.id = generate_todo_id(store)
  end

  ensure_todo_source(todo)

  store.todos[#store.todos + 1] = todo
  return todo
end

local function update_todo_by_id(todo_id, mutator)
  local result = with_todo_store(function(store, index)
    local idx = index[todo_id]
    if not idx then
      return false
    end

    local before = vim.deepcopy(idx.todo)
    local mutated = mutator(vim.deepcopy(idx.todo))
    if type(mutated) ~= 'table' then
      return false
    end

    local after = normalize_todo(mutated)
    if not after.id then
      after.id = before.id
    end

    ensure_todo_source(after)

    store.todos[idx.idx] = after
    if before.title ~= after.title then
      update_reference_line_for_todo(after, store)
    end

    return {
      changed = not vim.deep_equal(before, after),
      item = build_item_from_todo(after),
    }
  end)

  if not result then
    return false, nil
  end

  return result.changed == true, result.item
end

local function relationship_would_create_cycle(index, child_id, new_parent_id)
  if not child_id or not new_parent_id then
    return false
  end
  if child_id == new_parent_id then
    return true
  end

  local seen = {}
  local current_id = new_parent_id
  while current_id and current_id ~= '' do
    if current_id == child_id then
      return true
    end
    if seen[current_id] then
      return true
    end
    seen[current_id] = true

    local bucket = index[current_id]
    if not bucket or not bucket.todo then
      break
    end
    current_id = bucket.todo.parent_id
  end

  return false
end

local function set_todo_parent_relationship(child_id, parent_id)
  if not child_id or child_id == '' then
    return false, 'Source todo not found'
  end

  local store = load_store()
  local index = get_todo_index(store)
  local child_bucket = index[child_id]
  if not child_bucket then
    return false, 'Source todo not found'
  end

  local normalized_parent_id = (parent_id and parent_id ~= '') and parent_id or nil
  if normalized_parent_id then
    if not index[normalized_parent_id] then
      return false, 'Selected related todo was not found'
    end
    if relationship_would_create_cycle(index, child_id, normalized_parent_id) then
      return false, 'Relationship blocked: this would create a parent/child cycle'
    end
  end

  local child_todo = child_bucket.todo
  if child_todo.parent_id == normalized_parent_id then
    return true, nil
  end

  child_todo.parent_id = normalized_parent_id
  if not write_store(store) then
    return false, 'Could not save relationship update'
  end

  return true, nil
end

local function unlink_relationship_between(first_id, second_id)
  if not first_id or first_id == '' or not second_id or second_id == '' then
    return false, 'Could not resolve relationship pair', nil
  end

  local store = load_store()
  local index = get_todo_index(store)
  local first_bucket = index[first_id]
  local second_bucket = index[second_id]
  if not first_bucket or not second_bucket then
    return false, 'Selected related todo was not found', nil
  end

  local changed_child_id
  if first_bucket.todo.parent_id == second_id then
    first_bucket.todo.parent_id = nil
    changed_child_id = first_id
  elseif second_bucket.todo.parent_id == first_id then
    second_bucket.todo.parent_id = nil
    changed_child_id = second_id
  else
    return false, 'No direct parent/child relationship exists between selected todos', nil
  end

  if not write_store(store) then
    return false, 'Could not save relationship update', nil
  end

  return true, nil, changed_child_id
end

local function create_reference_at_line(bufnr, lnum, line_text, insert_only)
  if insert_only then
    vim.api.nvim_buf_set_lines(bufnr, lnum - 1, lnum - 1, false, { line_text })
    return lnum
  end
  vim.api.nvim_buf_set_lines(bufnr, lnum - 1, lnum, false, { line_text })
  return lnum
end

local function get_line(bufnr, lnum)
  return vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1] or ''
end

local function is_blank_line(line)
  return line:match('^%s*$') ~= nil
end

local function is_quote_line(line)
  return line:match('^%s*>') ~= nil
end

local function find_next_non_quote_line(bufnr, lnum)
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  local idx = lnum
  while idx <= line_count and is_quote_line(get_line(bufnr, idx)) do
    idx = idx + 1
  end
  return idx
end

local function open_new_todo_draft(picker, picker_context, draft)
  open_todo_detail(picker, nil, {
    start_zone = 'title',
    start_insert = true,
    create_mode = true,
    picker_context = picker_context,
    draft = draft,
  })
end

local function build_item_for_cursor_reference(bufnr, lnum)
  local line = get_line(bufnr, lnum)
  local parsed_ref = parse_reference_line(line)
  if not parsed_ref then
    local title, todo_id = line:match('TODO:%s*(.-)%s*%(%#([-%w_]+)%)')
    if title and todo_id then
      parsed_ref = {
        title = vim.trim(title),
        todo_id = todo_id,
      }
    end
  end
  if not parsed_ref then
    return nil
  end

  local store = load_store()
  local idx = find_todo_bucket(store, parsed_ref.todo_id)
  if not idx then
    return nil
  end

  idx.todo.reference = idx.todo.reference or {}
  idx.todo.reference.file = vim.api.nvim_buf_get_name(bufnr)
  idx.todo.reference.lnum = lnum
  write_store(store)

  return build_item_from_todo(idx.todo)
end

-- Hierarchy and filter shaping for picker presentation.
local function collect_direct_subtasks(store, parent_id)
  local subtasks = {}
  if not parent_id or parent_id == '' then
    return subtasks
  end
  for _, todo in ipairs(store.todos or {}) do
    if todo.parent_id == parent_id then
      subtasks[#subtasks + 1] = todo
    end
  end
  table.sort(subtasks, function(a, b)
    local a_status = STATUS_SORT[a.status] or 9
    local b_status = STATUS_SORT[b.status] or 9
    if a_status ~= b_status then
      return a_status < b_status
    end

    local a_completed_sort = parse_date_to_sortkey(a.completed)
    local b_completed_sort = parse_date_to_sortkey(b.completed)
    local a_completed_rank = 99999999
    local b_completed_rank = 99999999
    if a_status == (STATUS_SORT[STATUS_DONE] or 2) and a_completed_sort >= 0 then
      a_completed_rank = 99999999 - a_completed_sort
    end
    if b_status == (STATUS_SORT[STATUS_DONE] or 2) and b_completed_sort >= 0 then
      b_completed_rank = 99999999 - b_completed_sort
    end
    if a_completed_rank ~= b_completed_rank then
      return a_completed_rank < b_completed_rank
    end

    local a_priority = PRIORITY_SORT[a.priority] or 9
    local b_priority = PRIORITY_SORT[b.priority] or 9
    if a_priority ~= b_priority then
      return a_priority < b_priority
    end

    local ar = parse_date_to_sortkey(a.created)
    local br = parse_date_to_sortkey(b.created)
    local a_created_rank = ar >= 0 and ar or 99999999
    local b_created_rank = br >= 0 and br or 99999999
    if a_created_rank ~= b_created_rank then
      return a_created_rank < b_created_rank
    end
    return (a.id or '') < (b.id or '')
  end)
  return subtasks
end

local function compare_todo_entries_for_group(a, b)
  if a.status_rank ~= b.status_rank then
    return a.status_rank < b.status_rank
  end
  if a.completed_rank ~= b.completed_rank then
    return a.completed_rank < b.completed_rank
  end
  if a.priority_rank ~= b.priority_rank then
    return a.priority_rank < b.priority_rank
  end
  if a.created_rank ~= b.created_rank then
    return a.created_rank < b.created_rank
  end
  return (a.id or '') < (b.id or '')
end

local function get_todo_hierarchy_index(store)
  local index = {
    parent_to_child_count = {},
    id_to_parent = {},
    depth_by_todo_id = {},
    order_by_key = {},
    direct_done_by_todo_id = {},
    direct_total_by_todo_id = {},
  }

  local entries = {}
  local entries_by_id = {}
  local children_by_parent = {}

  -- Precompute sortable ranks once so the picker can group and redraw without
  -- repeating date/status logic in multiple places.
  for _, todo in ipairs(store.todos or {}) do
    local status_rank = STATUS_SORT[todo.status] or 9
    local priority_rank = PRIORITY_SORT[todo.priority] or 9
    local created_sort = parse_date_to_sortkey(todo.created)
    local created_rank = created_sort >= 0 and created_sort or 99999999
    local completed_sort = parse_date_to_sortkey(todo.completed)
    local completed_rank = 99999999
    if status_rank == (STATUS_SORT[STATUS_DONE] or 2) and completed_sort >= 0 then
      completed_rank = 99999999 - completed_sort
    end

    local entry = {
      id = todo.id,
      parent_id = todo.parent_id,
      status = todo.status,
      status_rank = status_rank,
      priority_rank = priority_rank,
      created_rank = created_rank,
      completed_rank = completed_rank,
    }
    entries[#entries + 1] = entry
    entries_by_id[todo.id] = entry
    index.id_to_parent[todo.id] = todo.parent_id

    if todo.parent_id then
      children_by_parent[todo.parent_id] = children_by_parent[todo.parent_id] or {}
      children_by_parent[todo.parent_id][#children_by_parent[todo.parent_id] + 1] = entry
      index.parent_to_child_count[todo.parent_id] = (index.parent_to_child_count[todo.parent_id] or 0) + 1
    end
  end

  local roots = {}
  for _, entry in ipairs(entries) do
    if not entry.parent_id or not entries_by_id[entry.parent_id] then
      roots[#roots + 1] = entry
    end
  end
  table.sort(roots, compare_todo_entries_for_group)

  for _, siblings in pairs(children_by_parent) do
    table.sort(siblings, compare_todo_entries_for_group)
  end

  local assigned = {}
  local order_counter = 0

  local function assign_tree_order(entry, depth, visiting, root_status_rank)
    if not entry or not entry.id or assigned[entry.id] or visiting[entry.id] then
      return
    end
    -- Children inherit the root status bucket so an entire subtree stays
    -- visually grouped under the same top-level status section.
    if root_status_rank == nil then
      root_status_rank = entry.status_rank or 9
    end

    visiting[entry.id] = true
    assigned[entry.id] = true
    order_counter = order_counter + 1

    index.order_by_key[entry.id] = root_status_rank * 10000000000 + order_counter
    index.depth_by_todo_id[entry.id] = depth

    for _, child in ipairs(children_by_parent[entry.id] or {}) do
      assign_tree_order(child, depth + 1, visiting, root_status_rank)
    end

    visiting[entry.id] = nil
  end

  for _, entry in ipairs(roots) do
    assign_tree_order(entry, 0, {}, nil)
  end

  for _, entry in ipairs(entries) do
    if not assigned[entry.id] then
      assign_tree_order(entry, 0, {}, nil)
    end
  end

  for parent_id, children in pairs(children_by_parent) do
    local done_count = 0
    for _, child in ipairs(children) do
      if child.status == STATUS_DONE then
        done_count = done_count + 1
      end
    end
    index.direct_done_by_todo_id[parent_id] = done_count
    index.direct_total_by_todo_id[parent_id] = #children
  end

  return index
end

local function is_hidden_by_collapse(parent_id, hierarchy_state, hierarchy_index)
  if not parent_id then
    return false
  end
  if hierarchy_state and hierarchy_state.collapse_all then
    return true
  end

  local collapsed_by_id = hierarchy_state and hierarchy_state.collapsed_by_id or {}
  local id_to_parent = hierarchy_index and hierarchy_index.id_to_parent or {}
  local visited = {}
  local current = parent_id

  while current and current ~= '' and not visited[current] do
    if collapsed_by_id[current] then
      return true
    end
    visited[current] = true
    current = id_to_parent[current]
  end

  return false
end

local function matches_filters(fields, labels, filters)
  if not filters or #filters == 0 then
    return true
  end

  local label_lookup = {}
  for _, label in ipairs(labels or {}) do
    label_lookup[tostring(label):lower()] = true
  end

  for _, filter in ipairs(filters) do
    if filter.kind == 'label' then
      if not label_lookup[tostring(filter.value or ''):lower()] then
        return false
      end
    else
      local actual = fields[filter.field]
      if actual == nil then
        return false
      end
      if tostring(actual):lower() ~= tostring(filter.value):lower() then
        return false
      end
    end
  end

  return true
end

local function parse_filter_args(raw)
  local filters = {}
  for token in (raw or ''):gmatch('[^,%s]+') do
    local label = token:match('^#(.+)$')
    if label and vim.trim(label) ~= '' then
      filters[#filters + 1] = {
        kind = 'label',
        value = vim.trim(label):lower(),
      }
    else
      local field, value = token:match('^@?([%w_]+)%s*[:=]%s*(.+)$')
      if field and value and value ~= '' then
        filters[#filters + 1] = {
          kind = 'field',
          field = field:lower(),
          value = vim.trim(value),
        }
      end
    end
  end
  return filters
end

local function build_filter_title(filters)
  if not filters or #filters == 0 then
    return 'FILTERED TODOs'
  end

  local parts = {}
  for _, f in ipairs(filters) do
    if f.kind == 'label' then
      parts[#parts + 1] = '#' .. tostring(f.value or '')
    else
      parts[#parts + 1] = f.field .. '=' .. f.value
    end
  end

  return 'FILTERED TODOs (' .. table.concat(parts, ', ') .. ')'
end

local function format_filter_args(filters)
  if not filters or #filters == 0 then
    return ''
  end
  local parts = {}
  for _, filter in ipairs(filters) do
    if filter.kind == 'label' then
      parts[#parts + 1] = '#' .. tostring(filter.value or '')
    else
      parts[#parts + 1] = filter.field .. '=' .. tostring(filter.value or '')
    end
  end
  return table.concat(parts, ', ')
end

local function should_keep_done_item(item, apply_done_retention)
  -- Completed items without a parseable completion date are treated as stale so
  -- the "done" views do not quietly accumulate broken records.
  local completed_date = item.todo_completed_date
  if completed_date == '' then
    return false
  end

  local completed_time = parse_date_to_time(completed_date)
  if not completed_time then
    return false
  end

  if not apply_done_retention then
    return true
  end

  local age_days = math.floor((os.time() - completed_time) / 86400)
  return age_days <= Config.done_retention_days
end

local function is_flat_order_enabled(opts)
  return opts and opts.flat_order == true
end

local function get_done_visibility_mode(opts)
  opts = opts or {}

  local mode = opts.done_visibility
  if mode == 'hide' or mode == 'recent' or mode == 'all' then
    return mode
  end

  -- Backward compatibility for older picker options.
  if opts.include_done == false then
    return 'hide'
  end
  if opts.apply_done_retention == false then
    return 'all'
  end
  return 'recent'
end

local function build_quick_create_picker_item()
  local message = 'New TODO'
  return {
    file = get_todo_store_path(),
    pos = { 1, 1 },
    text = message,
    todo_text = message,
    todo_is_empty_state = true,
    -- Keep the quick-create row pinned above all todos regardless of sorting
    -- mode so Enter always gives a fast path for a fresh task.
    todo_grouped_order = -1,
    todo_status = -1,
    todo_completed_sort_effective = -1,
    todo_priority_sort_effective = -1,
    todo_created_sort = -1,
    score = 999999999999,
  }
end

local function collect_picker_items(opts)
  opts = opts or {}
  local store = load_store()
  local hierarchy_index = get_todo_hierarchy_index(store)
  local hierarchy_state = picker_hierarchy_ui_state
  local flat_order = is_flat_order_enabled(opts)
  local only_done = opts.only_done == true
  local done_visibility = get_done_visibility_mode(opts)
  if only_done then
    done_visibility = 'all'
  end
  local filters = opts.filters or {}

  local title_by_id = {}
  for _, todo in ipairs(store.todos or {}) do
    if todo.id then
      title_by_id[todo.id] = todo.title
    end
  end

  local items = {}
  for _, todo in ipairs(store.todos or {}) do
    -- Build a single picker-facing record that already contains hierarchy,
    -- display, and sort metadata. The UI layer should not need to understand
    -- store shape or recompute these derived values.
    local item = build_item_from_todo(todo)

    local status = STATUS_SORT[todo.status] or -1
    item.todo_status = status
    item.todo_status_value = todo.status
    item.todo_priority = todo.priority
    item.todo_priority_sort = PRIORITY_SORT[todo.priority] or 9
    item.todo_created_date = todo.created or ''
    item.todo_completed_date = todo.completed or ''
    item.todo_created_sort = parse_date_to_sortkey(todo.created)
    item.todo_completed_sort = parse_date_to_sortkey(todo.completed)
    item.todo_display_date = item.todo_completed_date ~= '' and item.todo_completed_date or item.todo_created_date
    item.todo_text = todo.title
    item.todo_id = todo.id
    item.todo_parent_id = todo.parent_id
    item.todo_parent_title = todo.parent_id and title_by_id[todo.parent_id] or nil
    item.todo_flat_order = flat_order
    item.todo_grouped_order = flat_order and 0 or (hierarchy_index.order_by_key[todo.id] or 900000000)
    item.todo_depth = flat_order and 0 or (hierarchy_index.depth_by_todo_id[todo.id] or ((todo.parent_id and todo.parent_id ~= '') and 1 or 0))
    item.todo_child_count = hierarchy_index.parent_to_child_count[todo.id] or 0
    item.todo_has_children = not flat_order and item.todo_child_count > 0
    item.todo_collapsed = item.todo_has_children and hierarchy_state.collapsed_by_id[todo.id] == true or false
    item.todo_direct_done_count = hierarchy_index.direct_done_by_todo_id[todo.id] or 0
    item.todo_direct_total_count = hierarchy_index.direct_total_by_todo_id[todo.id] or 0
    if item.todo_has_children and item.todo_direct_total_count > 0 then
      item.todo_progress_badge = string.format(' [%d/%d]', item.todo_direct_done_count, item.todo_direct_total_count)
    else
      item.todo_progress_badge = ''
    end

    item.todo_fields = build_todo_fields(todo, item.todo_parent_title)
    item.todo_extra_fields = todo.extra_fields or {}
    item.todo_labels = todo.labels or {}
    item.todo_description = todo.description or ''
    item.todo_log = todo.log or todo.details or {}
    item.todo_details = item.todo_log
    item.text = todo.title
    local status_search = string.lower(tostring(todo.status or ''))
    if status_search ~= '' then
      item.text = item.text .. ' ' .. status_search
    end
    if #item.todo_labels > 0 then
      item.text = item.text .. ' ' .. table.concat(item.todo_labels, ' ')
    end
    if item.todo_parent_title and item.todo_parent_title ~= '' then
      item.text = item.text .. ' ' .. item.todo_parent_title
    end

    -- In flat mode, hide parent tasks that own children so the view is focused
    -- on actionable leaf items; child rows keep parent context as a suffix.
    local is_parent_with_children = flat_order and item.todo_child_count > 0
    if not is_parent_with_children then
        if (done_visibility ~= 'hide' or status ~= STATUS_SORT[STATUS_DONE])
          and matches_filters(item.todo_fields, item.todo_labels, filters)
          and (not only_done or status == STATUS_SORT[STATUS_DONE])
          and (flat_order or not is_hidden_by_collapse(item.todo_parent_id, hierarchy_state, hierarchy_index)) then
        local is_done = status == STATUS_SORT[STATUS_DONE]
        item.todo_priority_sort_effective = item.todo_priority_sort
        if is_done and item.todo_completed_sort >= 0 then
          item.todo_completed_sort_effective = 99999999 - item.todo_completed_sort
        else
          item.todo_completed_sort_effective = 99999999
        end

        local keep = true
        if status == STATUS_SORT[STATUS_DONE] then
          if done_visibility == 'recent' then
            keep = should_keep_done_item(item, true)
          elseif done_visibility == 'all' then
            keep = true
          else
            keep = false
          end
        end

        if keep then
          local created_rank = item.todo_created_sort >= 0 and item.todo_created_sort or 99999999
          local status_rank = status >= 0 and status or 9
          item.score = 999999999999 - (status_rank * 10000000000 + item.todo_priority_sort_effective * 100000000 + created_rank)
          items[#items + 1] = item
        end
      end
    end
  end

  items[#items + 1] = build_quick_create_picker_item()

  return items
end

-- Picker focus, mutation, and command actions.
get_focus_key_for_item = function(item)
  if not item then
    return nil
  end
  if item.todo_id and item.todo_id ~= '' then
    return 'id:' .. item.todo_id
  end
  local file = item.file or ''
  local lnum = item.pos and item.pos[1]
  if file ~= '' and lnum then
    return 'loc:' .. file .. ':' .. tostring(lnum)
  end
  return nil
end

item_matches_focus_key = function(item, focus_key)
  if not item or not focus_key or focus_key == '' then
    return false
  end
  if focus_key:sub(1, 3) == 'id:' then
    return (item.todo_id and ('id:' .. item.todo_id) or '') == focus_key
  end
  if focus_key:sub(1, 4) == 'loc:' then
    local file = item.file or ''
    local lnum = item.pos and item.pos[1]
    return ('loc:' .. file .. ':' .. tostring(lnum or '')) == focus_key
  end
  return false
end

restore_picker_focus = function(picker, focus_key)
  if not picker or not focus_key or focus_key == '' or not picker.iter or not picker.list or not picker.list.view then
    return
  end
  for candidate, idx in picker:iter() do
    if item_matches_focus_key(candidate, focus_key) then
      picker.list:view(idx)
      return
    end
  end
end

refresh_picker_items = function(picker, opts)
  if not picker then
    return
  end
  opts = opts or {}
  local focus_key = opts.focus_key

  if picker.finder then
    picker.finder.items = collect_picker_items((picker.opts and picker.opts._todo_format_opts) or {})
  end

  if picker.matcher and picker.matcher.run then
    picker.matcher:run(picker)
  end

  if picker.update then
    picker:update({ force = true })
  elseif picker.refresh then
    picker:refresh()
  end

  vim.schedule(function()
    restore_picker_focus(picker, focus_key)
  end)
end

local function get_picker_hierarchy_state(picker)
  if picker and picker.opts then
    picker.opts._todo_hierarchy_state = picker_hierarchy_ui_state
    local format_opts = picker.opts._todo_format_opts
    if type(format_opts) == 'table' then
      format_opts._todo_hierarchy_state = picker_hierarchy_ui_state
    end
  end
  return picker_hierarchy_ui_state
end

toggle_todo_status_line = function(todo)
  if type(todo) ~= 'table' then
    return nil
  end
  local next_status = STATUS_NEXT[todo.status] or STATUS_TODO
  local today_date = today()
  todo.status = next_status
  todo.created = next_status == STATUS_TODO and today_date or (todo.created or today_date)
  todo.completed = next_status == STATUS_DONE and today_date or nil
  return todo
end

local function toggle_todo_priority_line(todo)
  if type(todo) ~= 'table' then
    return nil
  end
  todo.priority = PRIORITY_NEXT[todo.priority] or PRIORITY_LOW
  return todo
end

local function picker_current_item(picker, item)
  if picker and picker.current then
    return picker:current({ resolve = false }) or item
  end
  return item
end

local function picker_selected_items(picker, item)
  if picker and picker.selected then
    return picker:selected({ fallback = true }) or {}
  end
  return item and { item } or {}
end

local function apply_to_selected_todos(picker, item, mutator)
  local changed = false
  local selected = picker_selected_items(picker, item)
  if #selected == 0 then
    local current_item = picker_current_item(picker, item)
    if current_item and current_item.todo_id then
      selected = { current_item }
    else
      return
    end
  end

  local current_item = picker_current_item(picker, item)
  local focus_key = get_focus_key_for_item(current_item) or get_focus_key_for_item(item)

  local seen = {}
  for _, it in ipairs(selected) do
    if it.todo_id and not seen[it.todo_id] then
      seen[it.todo_id] = true
      changed = update_todo_by_id(it.todo_id, mutator) or changed
    end
  end

  if changed then
    vim.schedule(function()
      refresh_picker_items(picker, { focus_key = focus_key })
    end)
  end
end

local function delete_todo_by_id(todo_id)
  local store = load_store()
  local bucket = find_todo_bucket(store, todo_id)
  if not bucket then
    return false
  end

  local todo = bucket.todo
  local ref_file, ref_lnum = resolve_reference(todo, store)

  if ref_file and ref_lnum then
    local bufnr = get_loaded_bufnr(ref_file)
    if bufnr then
      local line = vim.api.nvim_buf_get_lines(bufnr, ref_lnum - 1, ref_lnum, false)[1] or ''
      local parsed = parse_reference_line(line)
      if parsed and parsed.todo_id == todo_id then
        vim.api.nvim_buf_set_lines(bufnr, ref_lnum - 1, ref_lnum, false, {})
        maybe_write_buffer(bufnr)
      end
    end

    adjust_reference_lines_after_insert(store, ref_file, (ref_lnum or 0) + 1, -1, todo_id)
  end

  table.remove(store.todos, bucket.idx)
  return write_store(store)
end

local function confirm_delete_todos(items)
  if not items or #items == 0 then
    return false
  end

  local names = {}
  for _, item in ipairs(items) do
    names[#names + 1] = item.todo_text or item.todo_fields and item.todo_fields.item or item.text or 'Untitled task'
  end

  local prompt
  if #names == 1 then
    prompt = 'Delete this todo?\n\n' .. names[1]
  else
    prompt = string.format('Delete %d todos?', #names)
  end

  return vim.fn.confirm(prompt, '&Yes\n&No', 2) == 1
end

local function picker_delete_todos(picker, item)
  local unique_items = {}
  local seen = {}
  for _, it in ipairs(picker_selected_items(picker, item)) do
    if it and it.todo_id and not seen[it.todo_id] then
      seen[it.todo_id] = true
      unique_items[#unique_items + 1] = it
    end
  end

  if #unique_items == 0 then
    return
  end

  if not confirm_delete_todos(unique_items) then
    return
  end

  local changed = false
  for _, it in ipairs(unique_items) do
    if delete_todo_by_id(it.todo_id) then
      changed = true
    end
  end

  if changed then
    refresh_picker_items(picker, { focus_key = nil })
  end
end

local function picker_open_source(picker, item)
  local selected = picker_selected_items(picker, item)
  local target = selected[1] or item
  if not target or not target.todo_id then
    return
  end

  local store = load_store()
  local idx = find_todo_bucket(store, target.todo_id)
  if not idx then
    return
  end
  ensure_todo_source(idx.todo)
  local file, lnum = resolve_source(idx.todo)
  if not file then
    notify_todo('Source not found for this todo', vim.log.levels.WARN)
    return
  end

  if picker and picker.close then
    picker:close()
  end
  open_source_at(file, lnum or 1)
end

local function picker_open_reference(picker, item)
  local selected = picker_selected_items(picker, item)
  local target = selected[1] or item
  if not target or not target.todo_id then
    return
  end

  local store = load_store()
  local idx = find_todo_bucket(store, target.todo_id)
  if not idx then
    return
  end

  local file, lnum = resolve_reference(idx.todo, store)
  if not file or not lnum then
    notify_todo('Reference not found for this todo', vim.log.levels.WARN)
    return
  end

  if picker and picker.close then
    picker:close()
  end
  open_source_at(file, lnum)
end

local function picker_open_parent_detail(picker, item)
  local target = picker_current_item(picker, item)
  if not target then
    return
  end

  local parent_id = target.todo_parent_id
  if not parent_id or parent_id == '' then
    notify_todo('This todo has no parent', vim.log.levels.WARN)
    return
  end

  local parent_item = get_todo_item_by_id(parent_id)
  if not parent_item then
    notify_todo('Parent todo not found', vim.log.levels.WARN)
    return
  end

  open_todo_detail(picker, parent_item, {
    start_zone = 'log',
    start_insert = false,
    picker_context = capture_picker_reopen_context(picker, target),
  })
end

local function picker_create_task_below(picker, item)
  local target = picker_current_item(picker, item)
  if not target or target.todo_is_empty_state then
    open_new_todo_draft(picker, capture_picker_reopen_context(picker, target), {
      title = '',
      parent_id = nil,
      create_reference = false,
    })
    return
  end

  local inherited_labels = vim.deepcopy(target.todo_labels or {})
  local inherited_extra_fields = vim.deepcopy(target.todo_extra_fields or {})

  open_new_todo_draft(picker, capture_picker_reopen_context(picker, target), {
    title = '',
    parent_id = target.todo_parent_id,
    create_reference = false,
    labels = inherited_labels,
    extra_fields = inherited_extra_fields,
  })
end

local function picker_create_subtask(picker, item)
  local target = picker_current_item(picker, item)
  if not target or target.todo_is_empty_state or not target.todo_id then
    open_new_todo_draft(picker, capture_picker_reopen_context(picker, target), {
      title = '',
      parent_id = nil,
      create_reference = false,
    })
    return
  end

  local inherited_labels = vim.deepcopy(target.todo_labels or {})
  local inherited_extra_fields = vim.deepcopy(target.todo_extra_fields or {})

  open_new_todo_draft(picker, capture_picker_reopen_context(picker, target), {
    title = '',
    parent_id = target.todo_id,
    create_reference = false,
    labels = inherited_labels,
    extra_fields = inherited_extra_fields,
  })
end

local function picker_prompt_relationship(picker, item, mode)
  local source = picker_current_item(picker, item)
  if not source or not source.todo_id then
    return
  end

  local source_id = source.todo_id
  local source_title = source.todo_text or source.text or 'Untitled task'
  local return_context = capture_picker_reopen_context(picker, source)

  if picker and not picker.closed and picker.close then
    picker:close()
  end

  local relation_picker_opts = get_todo_picker_opts {
    title = string.format('Relationship: %s -> pick second todo', source_title),
    apply_done_retention = false,
  }

  relation_picker_opts.win = relation_picker_opts.win or {}
  relation_picker_opts.win.input = relation_picker_opts.win.input or {}
  relation_picker_opts.win.input.keys = relation_picker_opts.win.input.keys or {}
  relation_picker_opts.win.list = relation_picker_opts.win.list or {}
  relation_picker_opts.win.list.keys = relation_picker_opts.win.list.keys or {}

  -- In relationship target mode, `r` should select the 2nd ticket (confirm),
  -- not recurse into another relationship flow.
  relation_picker_opts.win.input.keys['r'] = { 'confirm', mode = { 'n' }, desc = 'select second todo' }
  relation_picker_opts.win.list.keys['r'] = { 'confirm', mode = { 'n' }, desc = 'select second todo' }

  relation_picker_opts.confirm = function(rel_picker, candidate)
    local target = (rel_picker and rel_picker.current and rel_picker:current({ resolve = false })) or candidate
    if not target or not target.todo_id then
      return
    end

    local target_id = target.todo_id
    local target_title = target.todo_text or target.text or 'Untitled task'
    if target_id == source_id then
      notify_todo('Pick a different todo to define a relationship', vim.log.levels.WARN)
      return
    end

    if rel_picker and not rel_picker.closed and rel_picker.close then
      rel_picker:close()
    end

    local function apply_choice(choice)
      if not choice then
        reopen_picker_from_context(return_context)
        return
      end

      local ok, err, changed_child_id
      if choice.kind == 'unlink_pair' then
        ok, err, changed_child_id = unlink_relationship_between(source_id, target_id)
      else
        ok, err = set_todo_parent_relationship(choice.child_id, choice.parent_id)
      end
      if not ok then
        notify_todo(err or 'Could not update relationship', vim.log.levels.WARN)
      else
        notify_todo('Relationship updated')
        return_context.focus_key = 'id:' .. (changed_child_id or choice.child_id or source_id)
      end

      reopen_picker_from_context(return_context)
    end

    if mode == 'source_child' then
      apply_choice({
        label = string.format('Make "%s" a child of "%s"', source_title, target_title),
        child_id = source_id,
        parent_id = target_id,
      })
      return
    end

    if mode == 'source_parent' then
      apply_choice({
        label = string.format('Make "%s" a child of "%s"', target_title, source_title),
        child_id = target_id,
        parent_id = source_id,
      })
      return
    end

    local choices = {
      {
        label = string.format('Make "%s" a child of "%s"', source_title, target_title),
        child_id = source_id,
        parent_id = target_id,
      },
      {
        label = string.format('Make "%s" a child of "%s"', target_title, source_title),
        child_id = target_id,
        parent_id = source_id,
      },
      {
        label = string.format('Unlink relationship between "%s" and "%s"', source_title, target_title),
        kind = 'unlink_pair',
      },
    }

    vim.ui.select(choices, {
      prompt = 'Choose relationship direction:',
      format_item = function(choice)
        return choice.label
      end,
    }, apply_choice)
  end

  local relation_picker = Snacks.picker(relation_picker_opts)
  if relation_picker then
    vim.schedule(function()
      restore_picker_focus(relation_picker, 'id:' .. source_id)
    end)
  end
end

local function picker_toggle_subtasks(picker, item)
  if is_flat_order_enabled(picker and picker.opts and picker.opts._todo_format_opts) then
    return
  end

  local state = get_picker_hierarchy_state(picker)
  if not state or not item then
    return
  end
  local target_id = item.todo_id
  if not target_id and item.todo_parent_id then
    target_id = item.todo_parent_id
  end
  if not target_id then
    return
  end
  local store = load_store()
  local index = get_todo_hierarchy_index(store)
  if (index.parent_to_child_count[target_id] or 0) == 0 then
    return
  end
  local current_item = picker_current_item(picker, item)
  state.collapsed_by_id[target_id] = not state.collapsed_by_id[target_id]
  local focus_key = get_focus_key_for_item(current_item)
  if state.collapsed_by_id[target_id] then
    focus_key = 'id:' .. target_id
  end
  refresh_picker_items(picker, { focus_key = focus_key })
end

local function picker_toggle_all_subtasks(picker)
  if is_flat_order_enabled(picker and picker.opts and picker.opts._todo_format_opts) then
    return
  end

  local state = get_picker_hierarchy_state(picker)
  if not state then
    return
  end
  local current_item = picker_current_item(picker, nil)
  state.collapse_all = not state.collapse_all
  local focus_key = get_focus_key_for_item(current_item)
  if state.collapse_all and current_item and current_item.todo_parent_id and current_item.todo_parent_id ~= '' then
    focus_key = 'id:' .. current_item.todo_parent_id
  end
  refresh_picker_items(picker, { focus_key = focus_key })
end

local function picker_prompt_filter(picker, item)
  if not picker then
    return
  end

  local reopen_opts = vim.deepcopy((picker.opts and picker.opts._todo_format_opts) or {})
  local current_item = picker_current_item(picker, item)
  local focus_key = get_focus_key_for_item(current_item)
  local hierarchy_state = vim.deepcopy(get_picker_hierarchy_state(picker) or {
    collapsed_by_id = {},
    collapse_all = false,
  })

  vim.ui.input({
    prompt = 'Todo filter (#label or field=value, comma-separated): ',
    default = format_filter_args(reopen_opts.filters),
  }, function(input)
    if input == nil then
      return
    end

    local raw = vim.trim(input)
    if raw == '' then
      reopen_opts.filters = nil
      if reopen_opts.title and reopen_opts.title:match('^FILTERED TODOs') then
        reopen_opts.title = nil
      end
    else
      local filters = parse_filter_args(raw)
      if #filters == 0 then
        notify_todo('Usage: #label or field=value (comma-separated)', vim.log.levels.WARN)
        return
      end
      reopen_opts.filters = filters
      reopen_opts.apply_done_retention = false
      reopen_opts.title = build_filter_title(filters)
    end

    reopen_opts._todo_hierarchy_state = hierarchy_state

    if picker and not picker.closed and picker.close then
      picker:close()
    end

    local new_picker = open_todo_picker(reopen_opts)
    if focus_key and new_picker then
      vim.schedule(function()
        restore_picker_focus(new_picker, focus_key)
      end)
    end
  end)
end

local function picker_toggle_order_mode(picker, item)
  if not picker or not picker.opts then
    return
  end

  local format_opts = picker.opts._todo_format_opts or {}
  format_opts.flat_order = not (format_opts.flat_order == true)
  picker.opts._todo_format_opts = format_opts

  local current_item = picker_current_item(picker, item)
  local focus_key = get_focus_key_for_item(current_item) or get_focus_key_for_item(item)
  refresh_picker_items(picker, { focus_key = focus_key })
end

local function picker_toggle_done_visibility(picker, item)
  if not picker or not picker.opts then
    return
  end

  local format_opts = picker.opts._todo_format_opts or {}
  if format_opts.only_done == true then
    return
  end

  local mode = get_done_visibility_mode(format_opts)
  if mode == 'recent' then
    mode = 'hide'
  elseif mode == 'hide' then
    mode = 'all'
  else
    mode = 'recent'
  end

  format_opts.done_visibility = mode
  format_opts.include_done = nil
  format_opts.apply_done_retention = nil
  picker.opts._todo_format_opts = format_opts

  local current_item = picker_current_item(picker, item)
  local focus_key = get_focus_key_for_item(current_item) or get_focus_key_for_item(item)
  refresh_picker_items(picker, { focus_key = focus_key })
end

capture_picker_reopen_context = function(picker, fallback_item)
  if not picker then
    return nil
  end
  local current_item = picker.current and picker:current({ resolve = false }) or fallback_item
  local focus_key = get_focus_key_for_item(current_item) or get_focus_key_for_item(fallback_item)
  return {
    picker = picker,
    focus_key = focus_key,
    reopen_opts = vim.deepcopy((picker.opts and picker.opts._todo_format_opts) or {}),
    hierarchy_state = vim.deepcopy(picker_hierarchy_ui_state or {
      collapsed_by_id = {},
      collapse_all = false,
    }),
  }
end

open_todo_picker = function(opts)
  return Snacks.picker(get_todo_picker_opts(opts or {}))
end

reopen_picker_from_context = function(context)
  if not context then
    return
  end

  local picker = context.picker
  if picker and not picker.closed and picker.close then
    picker:close()
  end

  local reopen_opts = vim.deepcopy(context.reopen_opts or {})
  if context.hierarchy_state then
    reopen_opts._todo_hierarchy_state = vim.deepcopy(context.hierarchy_state)
  end

  local new_picker = open_todo_picker(reopen_opts)
  if context.focus_key and new_picker then
    vim.schedule(function()
      restore_picker_focus(new_picker, context.focus_key)
    end)
  end
end

-- Detail panel editing and navigation.
open_todo_detail = function(picker, item, opts)
  opts = opts or {}
  if item and item.todo_is_empty_state then
    open_new_todo_draft(picker, capture_picker_reopen_context(picker, item), {
      title = '',
      parent_id = nil,
      create_reference = false,
    })
    return
  end

  local draft = opts.draft
  local is_create_mode = opts.create_mode == true
  local is_draft = is_create_mode and type(draft) == 'table'
  local store = load_store()
  local todo
  local source_file
  local source_lnum
  local reference_file
  local reference_lnum

  if is_draft then
    todo = normalize_todo {
      title = draft.title or '',
      status = draft.status or STATUS_TODO,
      priority = draft.priority or PRIORITY_LOW,
      created = draft.created or today(),
      completed = draft.completed,
      parent_id = draft.parent_id,
      description = draft.description or '',
      log = draft.log or draft.details or {},
      labels = draft.labels or {},
      extra_fields = draft.extra_fields or {},
      source = {
        file = draft.source and draft.source.file,
        lnum = draft.source and draft.source.lnum,
        todo_id = draft.source and draft.source.todo_id,
      },
      reference = {
        file = draft.reference and draft.reference.file,
        lnum = draft.reference and draft.reference.lnum,
      },
    }
    source_file = todo.source and todo.source.file
    source_lnum = todo.source and todo.source.lnum
    reference_file = todo.reference and todo.reference.file
    reference_lnum = todo.reference and todo.reference.lnum
  else
    if not item or not item.todo_id then
      return
    end

    local idx = find_todo_bucket(store, item.todo_id)
    if not idx then
      notify_todo('Todo not found in store', vim.log.levels.WARN)
      return
    end
    todo = idx.todo
    ensure_todo_source(todo)
    source_file = todo.source and todo.source.file or get_todo_store_path()
    source_lnum = todo.source and todo.source.lnum
    reference_file, reference_lnum = resolve_reference(todo, store)
  end

  local status = todo.status
  local priority = todo.priority
  local created_date = todo.created
  local completed_date = todo.completed or ''
  local msg = todo.title
  local description = todo.description or ''
  local log_entries = vim.deepcopy(todo.log or todo.details or {})
  local labels = vim.deepcopy(todo.labels or {})
  local extra_fields = vim.deepcopy(todo.extra_fields or {})
  local direct_subtasks = is_draft and {} or collect_direct_subtasks(store, todo.id)
  local picker_context = opts.picker_context or capture_picker_reopen_context(picker, item)
  local panel_context = {
    picker = picker,
    picker_context = picker_context,
    todo_id = todo.id,
  }

  local lines = {}
  local hls = {}
  local span_hls = {}
  local function push(text, hl)
    lines[#lines + 1] = text
    if hl then hls[#hls + 1] = { #lines - 1, hl } end
  end

  local function push_segments(parts)
    local text = ''
    local col = 0
    for _, part in ipairs(parts) do
      local segment = tostring(part[1] or '')
      local hl = part[2]
      text = text .. segment
      local next_col = col + #segment
      if hl and segment ~= '' then
        span_hls[#span_hls + 1] = { #lines, col, next_col, hl }
      end
      col = next_col
    end
    lines[#lines + 1] = text
  end

  local inner_width = math.max(UI.panel.inner_width_min,
    math.min(UI.panel.inner_width_max, math.floor(vim.o.columns * UI.panel.inner_width_ratio)))
  local sep = UI.panel.indent .. string.rep(UI.panel.section_sep_char, inner_width)
  local reference_rel = vim.fn.fnamemodify(reference_file or '', ':~:.')
  local reference_value = ''
  if reference_rel ~= '' and reference_lnum then
    reference_value = reference_rel .. ':' .. tostring(reference_lnum)
  end
  local meta_label_width = UI.panel.meta_label_width
  local current_status = status
  local current_priority = priority
  local current_created_date = created_date
  local current_completed_date = completed_date

  local function status_value(s)
    return STATUS_LABEL[s] or s or ''
  end
  local function priority_value(p)
    return p or ''
  end
  local function meta_row(label, value)
    return string.format('%s%-' .. meta_label_width .. 's%s', UI.panel.indent, label .. ':', value)
  end
  local function section(title)
    push(UI.panel.indent .. title, 'SnacksPickerKeymapLhs')
    push(sep, 'Comment')
  end

  push(UI.panel.indent .. msg, 'SnacksPickerKeymapLhs')
  local title_line_num = #lines
  push('')
  push('')
  section('Description')
  local description_first_line
  local description_last_line
  local description_input_line
  local has_description_content = vim.trim(description) ~= ''
  local description_lines = vim.split(description, '\n', { plain = true, trimempty = false })
  if #description_lines == 0 then
    description_lines = { '' }
  end
  for _, desc_line in ipairs(description_lines) do
    push(UI.panel.details_indent .. desc_line, 'Normal')
    if not description_first_line then
      description_first_line = #lines
    end
    description_last_line = #lines
  end
  if not description_first_line then
    push(UI.panel.indent, 'Normal')
    description_first_line = #lines
    description_last_line = #lines
  end
  if has_description_content then
    push(UI.panel.indent, 'Normal')
    description_input_line = #lines
    description_last_line = #lines
  else
    description_input_line = description_last_line
  end

  push('')
  section('Log')
  local log_first_line
  local log_last_line
  local log_input_line
  if #log_entries > 0 then
    for _, entry in ipairs(log_entries) do
      push(UI.panel.details_indent .. entry, 'Normal')
      if not log_first_line then
        log_first_line = #lines
      end
      log_last_line = #lines
    end
    push(UI.panel.indent, 'Normal')
    log_input_line = #lines
    log_last_line = #lines
  else
    push(UI.panel.indent, 'Normal')
    log_first_line = #lines
    log_last_line = #lines
    log_input_line = #lines
  end

  push('')
  section('Tags')
  local tags_first_line
  local tags_last_line
  local tags_input_line
  for _, label in ipairs(labels) do
    push(UI.panel.indent .. label, 'Normal')
    if not tags_first_line then
      tags_first_line = #lines
    end
    tags_last_line = #lines
  end
  if #extra_fields > 0 then
    for _, field in ipairs(extra_fields) do
      push(meta_row(field.name, field.value or ''), 'Normal')
      if not tags_first_line then
        tags_first_line = #lines
      end
      tags_last_line = #lines
    end
    push(UI.panel.indent, 'Normal')
    tags_input_line = #lines
    tags_last_line = #lines
  else
    push(UI.panel.indent, 'Normal')
    tags_first_line = #lines
    tags_input_line = #lines
    tags_last_line = #lines
  end

  push('')
  section('Meta')
  push(meta_row('Status', status_value(status)), 'Normal')
  local status_row_line = #lines
  push(meta_row('Priority', priority_value(priority)), 'Normal')
  local priority_row_line = #lines
  push(meta_row('Created', created_date), 'Normal')
  local created_row_line = #lines
  push(meta_row('Completed', completed_date), 'Normal')
  local completed_row_line = #lines
  push(meta_row('Reference', reference_value), 'Normal')

  local help_line = #lines + 1

  local subtask_line_to_id = {}
  local subtasks_first_line
  local subtasks_last_line

  if #direct_subtasks > 0 then
    push('')
    section('Subtasks')
    for _, subtask in ipairs(direct_subtasks) do
      local sub_status = subtask.status or STATUS_TODO
      local sub_priority = subtask.priority or PRIORITY_LOW
      local status_hl = STATUS_COLOR[STATUS_SORT[sub_status] or -1] or 'Normal'
      local title_hl = title_highlight_for_status(sub_status, status_hl)
      local priority_badge = PRIORITY_BADGE[sub_priority] or Config.picker_badges.low

      push_segments {
        { ' ', 'Normal' },
        { priority_badge, PRIORITY_HL[sub_priority] or 'NonText' },
        { UI.picker.row_gap, 'Normal' },
        { subtask.title or '', title_hl },
      }
      if not subtasks_first_line then
        subtasks_first_line = #lines
      end
      subtasks_last_line = #lines
      subtask_line_to_id[#lines] = subtask.id
    end
  end

  local w = math.min(inner_width + 4, math.floor(vim.o.columns * UI.panel.float_width_ratio))
  local max_h = math.max(UI.panel.min_height, math.floor(vim.o.lines * UI.panel.float_height_ratio))
  local h = math.min(#lines, max_h)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = true
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.b[buf].completion = false
  vim.bo[buf].omnifunc = ''
  vim.bo[buf].completefunc = ''

  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = w,
    height = h,
    row = math.floor((vim.o.lines - h) / 2),
    col = math.floor((vim.o.columns - w) / 2),
    style = 'minimal',
    border = UI.panel.border,
    zindex = 200,
  })

  if vim.fn.mode():sub(1, 1) == 'i' then
    vim.cmd.stopinsert()
  end
  vim.wo[win].cursorline = false
  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true
  vim.wo[win].virtualedit = 'onemore'
  vim.wo[win].breakindent = true
  vim.wo[win].breakindentopt = UI.panel.breakindentopt
  vim.wo[win].showbreak = '  '
  vim.wo[win].winhighlight = 'Normal:NormalFloat,FloatBorder:FloatBorder,FloatTitle:Title'

  local ns = vim.api.nvim_create_namespace('snacks_todo_detail')
  for _, hl in ipairs(hls) do
    vim.api.nvim_buf_add_highlight(buf, ns, hl[2], hl[1], 0, -1)
  end
  for _, span in ipairs(span_hls) do
    vim.api.nvim_buf_add_highlight(buf, ns, span[4], span[1], span[2], span[3])
  end

  local help_win
  local function close_help()
    if help_win and vim.api.nvim_win_is_valid(help_win) then
      vim.api.nvim_win_close(help_win, true)
    end
    help_win = nil
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_set_current_win(win)
    end
  end

  local function toggle_help()
    if help_win and vim.api.nvim_win_is_valid(help_win) then
      close_help()
      return
    end

    local help_lines = {
      '  Detail Panel Keys',
      '',
      '  <CR>  Save and close',
      '  w     Save edits',
      '  q     Close panel',
      '  S     Cycle status',
      '  P     Cycle priority',
      '  D     Delete todo',
      '  r     Set relationship (choose direction + unlink)',
      '  p     Open parent details',
      '  c     Open selected child details',
      '  a     Add subtask',
      '  e     Open source (todo.json)',
      '  m     Open markdown reference',
      '  Tab   Next section',
      '  S-Tab Previous section',
      '  ?     Toggle this help',
    }

    local max_len = 0
    for _, line in ipairs(help_lines) do
      max_len = math.max(max_len, vim.fn.strdisplaywidth(line))
    end

    local hh = #help_lines
    local hw = math.max(40, math.min(max_len + 2, math.floor(vim.o.columns * 0.5)))

    local hbuf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(hbuf, 0, -1, false, help_lines)
    vim.bo[hbuf].modifiable = false
    vim.bo[hbuf].bufhidden = 'wipe'
    vim.bo[hbuf].buftype = 'nofile'

    help_win = vim.api.nvim_open_win(hbuf, true, {
      relative = 'editor',
      width = hw,
      height = hh,
      row = math.floor((vim.o.lines - hh) / 2),
      col = math.floor((vim.o.columns - hw) / 2),
      style = 'minimal',
      border = UI.panel.border,
      title = ' Detail Help ',
      title_pos = 'center',
      zindex = 210,
    })

    vim.keymap.set('n', 'q', close_help, { buffer = hbuf, nowait = true, silent = true })
    vim.keymap.set('n', '<Esc>', close_help, { buffer = hbuf, nowait = true, silent = true })
    vim.keymap.set('n', '?', close_help, { buffer = hbuf, nowait = true, silent = true })
  end

  local function parse_editor_block(editor_lines)
    local description_idx, log_idx, tags_idx, meta_idx
    for i, line in ipairs(editor_lines) do
      local t = vim.trim(line)
      if t == 'Description' then
        description_idx = i
      elseif t == 'Log' then
        log_idx = i
      elseif t == 'Tags' then
        tags_idx = i
      elseif t == 'Meta' then
        meta_idx = i
      end
    end

    if not description_idx or not log_idx or not tags_idx or not meta_idx then
      return nil, nil, nil, nil, nil
    end
    if not (description_idx < log_idx and log_idx < tags_idx and tags_idx < meta_idx) then
      return nil, nil, nil, nil, nil
    end

    local task_text = vim.trim(editor_lines[title_line_num] or '')

    local function is_separator_line(text)
      local compact = text:gsub('%s+', '')
      return compact ~= '' and compact:gsub('─', '') == ''
    end

    local description_lines_out = {}
    for i = description_idx + 1, log_idx - 1 do
      local raw = editor_lines[i] or ''
      if not is_separator_line(raw) then
        local value = raw:gsub('^%s+', '')
        description_lines_out[#description_lines_out + 1] = value
      end
    end
    while #description_lines_out > 0 and vim.trim(description_lines_out[1]) == '' do
      table.remove(description_lines_out, 1)
    end
    while #description_lines_out > 0 and vim.trim(description_lines_out[#description_lines_out]) == '' do
      table.remove(description_lines_out)
    end
    local description_text = table.concat(description_lines_out, '\n')

    local log_items = {}
    for i = log_idx + 1, tags_idx - 1 do
      local t = vim.trim(editor_lines[i] or '')
      if t ~= '' and not is_separator_line(t) then
        log_items[#log_items + 1] = t
      end
    end

    -- Tag lines support two forms:
    -- - plain value      -> label
    -- - field=value/name:value -> field tag
    local tags = {}
    local labels_out = {}
    for i = tags_idx + 1, meta_idx - 1 do
      local t = vim.trim(editor_lines[i] or '')
      if t ~= '' and not is_separator_line(t) then
        local payload = vim.trim(t:match('^[-*+]%s*(.*)$') or t)
        local label = payload:match('^#(.+)$')
        if label and vim.trim(label) ~= '' then
          labels_out[#labels_out + 1] = vim.trim(label)
        else
          local name, value = payload:match('^([%w_]+)%s*[:=]%s*(.+)$')
          if name and value and value ~= '' and not CORE_FIELDS[name:lower()] then
            local normalized_value = vim.trim(value)
            if normalized_value ~= 'value' then
              tags[#tags + 1] = { name = name:lower(), value = normalized_value }
            end
          else
            labels_out[#labels_out + 1] = payload
          end
        end
      end
    end

    return task_text, description_text, log_items, tags, labels_out
  end

  local function render_meta_rows()
    local rows = {
      { status_row_line, 'Status', STATUS_LABEL[current_status] or current_status or '' },
      { priority_row_line, 'Priority', current_priority or '' },
      { created_row_line, 'Created', current_created_date or '' },
      { completed_row_line, 'Completed', current_completed_date or '' },
    }
    for _, row in ipairs(rows) do
      vim.api.nvim_buf_set_lines(buf, row[1] - 1, row[1], false,
        { string.format('%s%-' .. meta_label_width .. 's%s', UI.panel.indent, row[2] .. ':', row[3]) })
    end
  end

  local function cycle_card_status()
    local today_date = today()
    current_status = STATUS_NEXT[current_status] or STATUS_TODO
    if current_status == STATUS_DONE then
      current_completed_date = today_date
    elseif current_status == STATUS_TODO then
      current_created_date = today_date
      current_completed_date = ''
    else
      current_completed_date = ''
    end
    render_meta_rows()
  end

  local function cycle_card_priority()
    current_priority = PRIORITY_NEXT[current_priority] or PRIORITY_LOW
    render_meta_rows()
  end

  local save_edits
  local close_float

  local function delete_from_detail()
    if is_draft or not todo.id then
      notify_todo('This todo is not saved yet', vim.log.levels.WARN)
      return
    end

    if not confirm_delete_todos({ build_item_from_todo(todo) }) then
      return
    end

    if not delete_todo_by_id(todo.id) then
      notify_todo('Could not delete todo', vim.log.levels.WARN)
      return
    end

    close_float()
    refresh_picker_items(picker, { focus_key = nil })
    if reopen_previous_detail_panel() then
      return
    end
    transition_to_picker()
  end

  save_edits = function()
    local editor_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local task_text, description_text, log_items, tags, labels_out = parse_editor_block(editor_lines)
    if task_text == nil then
      notify_todo('Could not parse Description/Log/Tags sections', vim.log.levels.WARN)
      return false
    end

    local task = vim.trim(task_text)
    if task == '' then
      task = msg or ''
    end
    if task == '' then
      notify_todo('Title cannot be empty', vim.log.levels.WARN)
      return false
    end

    -- `save_edits` has to support two flows with the same editor buffer:
    -- creating a brand-new todo from a draft, or mutating an existing record in
    -- place.
    local wrote
    local updated_item

    if is_draft then
      local create_store = load_store()
      -- Draft saves create the canonical JSON record first, then optionally add
      -- the markdown reference line if this draft originated from a source file.
      local created_todo = create_todo_record(create_store, {
        title = task,
        status = current_status,
        priority = current_priority,
        created = current_created_date,
        completed = current_completed_date ~= '' and current_completed_date or nil,
        parent_id = draft.parent_id,
        description = description_text or '',
        log = normalize_log_entries(log_items or {}, today()),
        labels = normalize_labels(labels_out or {}),
        extra_fields = tags or {},
      })

      local should_create_reference = draft.create_reference == true
      if should_create_reference then
        local ref_file = draft.reference and draft.reference.file
        local ref_lnum = draft.reference and draft.reference.lnum
        local ref_insert_only = draft.reference and draft.reference.insert_only == true
        if not ref_file or not ref_lnum then
          notify_todo('Missing markdown reference location for new todo', vim.log.levels.ERROR)
          return false
        end

        local ref_buf = get_loaded_bufnr(ref_file)
        if not ref_buf then
          notify_todo('Could not open markdown buffer for todo reference', vim.log.levels.ERROR)
          return false
        end

        -- Reference insertion can shift later stored line numbers in the same
        -- file, so repair them immediately before persisting the store.
        local line_text = build_reference_line(task, created_todo.id)
        local inserted_lnum = create_reference_at_line(ref_buf, ref_lnum, line_text, ref_insert_only)
        created_todo.reference = {
          file = ref_file,
          lnum = inserted_lnum,
        }

        adjust_reference_lines_after_insert(
          create_store,
          ref_file,
          inserted_lnum + (ref_insert_only and 1 or 0),
          ref_insert_only and 1 or 0,
          created_todo.id
        )
        maybe_write_buffer(ref_buf)
      end

      if not write_store(create_store) then
        return false
      end

      wrote = true
      updated_item = build_item_from_todo(created_todo)
    else
      -- Existing todos round-trip back through normalization and reference sync
      -- inside `update_todo_by_id`, so the panel only needs to provide the new
      -- field values.
      wrote, updated_item = update_todo_by_id(todo.id, function(current)
        current.title = task
        current.status = current_status
        current.priority = current_priority
        current.created = current_created_date
        current.completed = current_completed_date ~= '' and current_completed_date or nil
        current.description = description_text or ''
        current.log = normalize_log_entries(log_items or {}, today())
        current.labels = normalize_labels(labels_out or {})
        current.extra_fields = tags or {}
        return current
      end)
    end

    if not wrote and not updated_item then
      return false
    end

    -- Keep the in-memory picker item coherent with what was just persisted so
    -- follow-up actions in this UI session operate on fresh data.
    if updated_item and item then
      item.todo_text = updated_item.todo_text
      item.todo_fields = updated_item.todo_fields
      item.todo_extra_fields = updated_item.todo_extra_fields
      item.todo_labels = updated_item.todo_labels
      item.todo_description = updated_item.todo_description
      item.todo_log = updated_item.todo_log
      item.todo_details = updated_item.todo_details
      item.todo_reference = updated_item.todo_reference
      item.todo_source = updated_item.todo_source
    end

    refresh_picker_items(picker, { focus_key = get_focus_key_for_item(updated_item or item) })
    return true
  end

  close_float = function()
    close_help()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end

  local function edit_relationship_from_detail(mode)
    if is_draft or not todo.id then
      notify_todo('Save this task before setting relationships', vim.log.levels.WARN)
      return
    end

    if vim.fn.mode():sub(1, 1) == 'i' then
      vim.cmd.stopinsert()
    end

    if not save_edits() then
      return
    end

    local source_item = get_todo_item_by_id(todo.id)
    if not source_item then
      notify_todo('Todo not found in store', vim.log.levels.WARN)
      return
    end

    close_float()

    local relation_picker_opts = get_todo_picker_opts {
      title = string.format('Relationship: %s -> pick second todo', source_item.todo_text or source_item.text or 'todo'),
      apply_done_retention = false,
    }

    relation_picker_opts.win = relation_picker_opts.win or {}
    relation_picker_opts.win.input = relation_picker_opts.win.input or {}
    relation_picker_opts.win.input.keys = relation_picker_opts.win.input.keys or {}
    relation_picker_opts.win.list = relation_picker_opts.win.list or {}
    relation_picker_opts.win.list.keys = relation_picker_opts.win.list.keys or {}

    -- In relationship target mode, `r` confirms the selected 2nd ticket.
    relation_picker_opts.win.input.keys['r'] = { 'confirm', mode = { 'n' }, desc = 'select second todo' }
    relation_picker_opts.win.list.keys['r'] = { 'confirm', mode = { 'n' }, desc = 'select second todo' }

    relation_picker_opts.confirm = function(rel_picker, candidate)
      local target = (rel_picker and rel_picker.current and rel_picker:current({ resolve = false })) or candidate
      if not target or not target.todo_id then
        return
      end

      if target.todo_id == source_item.todo_id then
        notify_todo('Pick a different todo to define a relationship', vim.log.levels.WARN)
        return
      end

      if rel_picker and not rel_picker.closed and rel_picker.close then
        rel_picker:close()
      end

      local source_title = source_item.todo_text or source_item.text or 'Untitled task'
      local target_title = target.todo_text or target.text or 'Untitled task'
      local function finish_choice(choice)
        if choice then
          local ok, err
          if choice.kind == 'unlink_pair' then
            ok, err = unlink_relationship_between(source_item.todo_id, target.todo_id)
          else
            ok, err = set_todo_parent_relationship(choice.child_id, choice.parent_id)
          end
          if not ok then
            notify_todo(err or 'Could not update relationship', vim.log.levels.WARN)
          else
            notify_todo('Relationship updated')
          end
        end

        local refreshed_item = get_todo_item_by_id(todo.id)
        if refreshed_item then
          open_todo_detail(picker, refreshed_item, {
            start_zone = 'log',
            start_insert = false,
            picker_context = panel_context.picker_context,
          })
        elseif reopen_previous_detail_panel() then
          -- previous panel reopened
        else
          transition_to_picker()
        end

        refresh_picker_items(picker, { focus_key = 'id:' .. source_item.todo_id })
      end

      if mode == 'source_child' then
        finish_choice({
          label = string.format('Make "%s" a child of "%s"', source_title, target_title),
          child_id = source_item.todo_id,
          parent_id = target.todo_id,
        })
        return
      end

      if mode == 'source_parent' then
        finish_choice({
          label = string.format('Make "%s" a child of "%s"', target_title, source_title),
          child_id = target.todo_id,
          parent_id = source_item.todo_id,
        })
        return
      end

      local choices = {
        {
          label = string.format('Make "%s" a child of "%s"', source_title, target_title),
          child_id = source_item.todo_id,
          parent_id = target.todo_id,
        },
        {
          label = string.format('Make "%s" a child of "%s"', target_title, source_title),
          child_id = target.todo_id,
          parent_id = source_item.todo_id,
        },
        {
          label = string.format('Unlink relationship between "%s" and "%s"', source_title, target_title),
          kind = 'unlink_pair',
        },
      }

      vim.ui.select(choices, {
        prompt = 'Choose relationship direction:',
        format_item = function(choice)
          return choice.label
        end,
      }, finish_choice)
    end

    local relation_picker = Snacks.picker(relation_picker_opts)
    if relation_picker then
      vim.schedule(function()
        restore_picker_focus(relation_picker, 'id:' .. source_item.todo_id)
      end)
    end
  end

  local function jump()
    close_float()
    if picker and picker.close then
      picker:close()
    end
    if is_draft then
      if draft.create_reference and draft.reference and draft.reference.file and draft.reference.lnum then
        open_source_at(draft.reference.file, draft.reference.lnum)
      end
      return
    end

    local fresh_store = load_store()
    local fresh_idx = find_todo_bucket(fresh_store, todo.id)
    if not fresh_idx then
      return
    end
    ensure_todo_source(fresh_idx.todo)
    local target_file, target_lnum = resolve_source(fresh_idx.todo)
    if target_file then
      open_source_at(target_file, target_lnum or 1)
    else
      notify_todo('Source not found for this todo', vim.log.levels.WARN)
    end
  end

  local function jump_reference()
    close_float()
    if picker and picker.close then
      picker:close()
    end

    if is_draft then
      if draft.reference and draft.reference.file and draft.reference.lnum then
        open_source_at(draft.reference.file, draft.reference.lnum)
      else
        notify_todo('Reference not found for this todo', vim.log.levels.WARN)
      end
      return
    end

    local fresh_store = load_store()
    local fresh_idx = find_todo_bucket(fresh_store, todo.id)
    if not fresh_idx then
      return
    end

    local target_file, target_lnum = resolve_reference(fresh_idx.todo, fresh_store)
    if target_file and target_lnum then
      open_source_at(target_file, target_lnum)
    else
      notify_todo('Reference not found for this todo', vim.log.levels.WARN)
    end
  end

  local function add_subtask_from_detail()
    if not todo.id then
      notify_todo('Save this task before adding subtasks', vim.log.levels.WARN)
      return
    end

    detail_panel_stack[#detail_panel_stack + 1] = {
      picker = picker,
      picker_context = panel_context.picker_context,
      todo_id = todo.id,
    }

    close_float()
    open_new_todo_draft(picker, panel_context.picker_context, {
      title = '',
      parent_id = todo.id,
      create_reference = false,
      labels = vim.deepcopy(todo.labels or {}),
      extra_fields = vim.deepcopy(todo.extra_fields or {}),
    })
  end

  local function open_parent_from_detail()
    local parent_id = todo.parent_id or (draft and draft.parent_id)
    if not parent_id or parent_id == '' then
      notify_todo('This todo has no parent', vim.log.levels.WARN)
      return
    end

    local parent_item = get_todo_item_by_id(parent_id)
    if not parent_item then
      notify_todo('Parent todo not found', vim.log.levels.WARN)
      return
    end

    detail_panel_stack[#detail_panel_stack + 1] = {
      picker = picker,
      picker_context = panel_context.picker_context,
      todo_id = todo.id,
    }

    close_float()
    open_todo_detail(picker, parent_item, {
      start_zone = 'log',
      start_insert = false,
      picker_context = panel_context.picker_context,
    })
  end

  local function open_child_from_detail()
    if not subtasks_first_line then
      notify_todo('This todo has no child tasks', vim.log.levels.WARN)
      return
    end

    local cursor_line = vim.api.nvim_win_get_cursor(win)[1]
    local child_id = subtask_line_to_id[cursor_line]
    if not child_id then
      notify_todo('Move cursor onto a subtask line first', vim.log.levels.WARN)
      return
    end

    local child_item = get_todo_item_by_id(child_id)
    if not child_item then
      notify_todo('Child todo not found', vim.log.levels.WARN)
      return
    end

    detail_panel_stack[#detail_panel_stack + 1] = {
      picker = picker,
      picker_context = panel_context.picker_context,
      todo_id = todo.id,
    }

    close_float()
    open_todo_detail(picker, child_item, {
      start_zone = 'log',
      start_insert = false,
      picker_context = panel_context.picker_context,
    })
  end

  local function reopen_previous_detail_panel()
    local previous = table.remove(detail_panel_stack)
    if not previous then
      return false
    end
    -- Nested detail flows (for example "add subtask" from a parent panel) push
    -- the parent panel onto a stack so closing the child can restore context.
    local store_now = load_store()
    local prev_idx = find_todo_bucket(store_now, previous.todo_id)
    if not prev_idx then
      reopen_picker_from_context(previous.picker_context)
      return true
    end
    local prev_item = build_item_from_todo(prev_idx.todo)
    vim.schedule(function()
      open_todo_detail(previous.picker, prev_item, {
        start_zone = 'log',
        start_insert = false,
        picker_context = previous.picker_context,
      })
    end)
    return true
  end

  local function transition_to_picker()
    if panel_context.picker_context then
      reopen_picker_from_context(panel_context.picker_context)
    end
  end

  local function dismiss()
    close_float()
    if reopen_previous_detail_panel() then
      return
    end
    transition_to_picker()
    if picker and not picker.closed and picker.focus then
      picker:focus('list')
    end
    if vim.fn.mode():sub(1, 1) == 'i' then
      vim.cmd.stopinsert()
    end
  end

  local function save_and_close()
    if vim.fn.mode():sub(1, 1) == 'i' then
      vim.cmd.stopinsert()
    end
    if save_edits() then
      -- Close first, then reopen the parent detail panel or picker context so
      -- the persisted state is what gets redisplayed.
      close_float()
      if reopen_previous_detail_panel() then
        return
      end
      transition_to_picker()
    end
  end

  local title_line = title_line_num or 1
  local title_col = 2
  local description_line = description_input_line or description_first_line or (title_line + 1)
  local description_col = 2
  local log_line = log_input_line or log_first_line or (description_line + 1)
  local log_col = 4
  local tags_line = tags_input_line or tags_first_line or (title_line + 1)
  local tags_col = 2
  local zones = {
    { name = 'title', line = title_line, col = title_col },
    { name = 'description', line = description_line, col = description_col },
    { name = 'log', line = log_line, col = log_col },
    { name = 'tags', line = tags_line, col = tags_col },
  }
  if subtasks_first_line then
    zones[#zones + 1] = { name = 'subtasks', line = subtasks_first_line, col = 2 }
  end

  local function focus_zone(index, enter_insert)
    local zone = zones[index]
    if not zone then
      return
    end

    local target_line = zone.line
    local target_col = zone.col
    local line_text = vim.api.nvim_buf_get_lines(buf, target_line - 1, target_line, false)[1] or ''
    local end_col = vim.str_byteindex(line_text, vim.fn.strchars(line_text))

    if zone.name == 'description' then
      target_col = math.max(description_col, end_col)
    elseif zone.name == 'log' then
      target_col = math.max(log_col, end_col)
    elseif zone.name == 'tags' then
      target_col = tags_col
    elseif zone.name == 'title' then
      target_col = math.max(title_col, end_col + 1)
    end

    vim.api.nvim_win_set_cursor(win, { target_line, target_col })
    if enter_insert then
      vim.cmd 'startinsert!'
    end
  end

  local function is_blank_editor_line(line_nr)
    local line_text = vim.api.nvim_buf_get_lines(buf, line_nr - 1, line_nr, false)[1] or ''
    return vim.trim(line_text) == ''
  end

  local function shift_subtask_lines(delta)
    if delta == 0 or not subtasks_first_line then
      return
    end

    subtasks_first_line = subtasks_first_line + delta
    subtasks_last_line = subtasks_last_line + delta

    local shifted = {}
    for line_nr, subtask_id in pairs(subtask_line_to_id) do
      shifted[line_nr + delta] = subtask_id
    end
    subtask_line_to_id = shifted
  end

  local function shift_meta_rows(delta)
    status_row_line = status_row_line + delta
    priority_row_line = priority_row_line + delta
    created_row_line = created_row_line + delta
    completed_row_line = completed_row_line + delta
    help_line = help_line + delta
    shift_subtask_lines(delta)
  end

  local function focus_description_input_row(create_if_needed)
    if not description_input_line then
      description_input_line = description_last_line or description_first_line or description_line
    end

    if create_if_needed and not is_blank_editor_line(description_input_line) then
      local insert_after = description_input_line
      vim.api.nvim_buf_set_lines(buf, insert_after, insert_after, false, { '  ' })
      description_input_line = insert_after + 1
      description_last_line = description_last_line + 1
      log_first_line = log_first_line + 1
      log_last_line = log_last_line + 1
      log_input_line = log_input_line + 1
      tags_first_line = tags_first_line + 1
      tags_last_line = tags_last_line + 1
      tags_input_line = tags_input_line + 1
      zones[2].line = description_input_line
      zones[3].line = log_input_line
      zones[4].line = tags_input_line
      shift_meta_rows(1)
    end

    vim.api.nvim_win_set_cursor(win, { description_input_line, description_col })
    vim.cmd 'startinsert!'
  end

  local function focus_log_input_row(create_if_needed)
    if not log_input_line then
      log_input_line = log_last_line or log_first_line or log_line
    end

    if create_if_needed and not is_blank_editor_line(log_input_line) then
      local insert_after = log_input_line
      vim.api.nvim_buf_set_lines(buf, insert_after, insert_after, false, { '  ' })
      log_last_line = log_last_line + 1
      log_input_line = insert_after + 1
      tags_first_line = tags_first_line + 1
      tags_last_line = tags_last_line + 1
      tags_input_line = tags_input_line + 1
      zones[3].line = log_input_line
      zones[4].line = tags_input_line
      shift_meta_rows(1)
    end

    local line_text = vim.api.nvim_buf_get_lines(buf, log_input_line - 1, log_input_line, false)[1] or ''
    local end_col = vim.str_byteindex(line_text, vim.fn.strchars(line_text))
    vim.api.nvim_win_set_cursor(win, { log_input_line, math.max(log_col, end_col) })
    vim.cmd 'startinsert!'
  end

  local function focus_tags_input_row(create_if_needed)
    if not tags_input_line then
      tags_input_line = tags_last_line or tags_first_line or tags_line
    end

    if create_if_needed and not is_blank_editor_line(tags_input_line) then
      local insert_after = tags_last_line or tags_input_line
      vim.api.nvim_buf_set_lines(buf, insert_after, insert_after, false, { '  ' })
      tags_last_line = insert_after + 1
      tags_input_line = insert_after + 1
      zones[4].line = tags_input_line
      shift_meta_rows(1)
    end

    vim.api.nvim_win_set_cursor(win, { tags_input_line, tags_col })
    vim.cmd 'startinsert!'
  end

  local function focus_subtask_line(use_last)
    if not subtasks_first_line then
      return
    end

    if vim.fn.mode():sub(1, 1) == 'i' then
      vim.cmd.stopinsert()
    end

    local cursor_line = vim.api.nvim_win_get_cursor(win)[1]
    local target = cursor_line
    if target < subtasks_first_line or target > subtasks_last_line then
      target = use_last and subtasks_last_line or subtasks_first_line
    end

    vim.api.nvim_win_set_cursor(win, { target, 2 })
  end

  local function step_subtask_line(forward)
    if not subtasks_first_line then
      return false
    end

    if vim.fn.mode():sub(1, 1) == 'i' then
      vim.cmd.stopinsert()
    end

    local cursor_line = vim.api.nvim_win_get_cursor(win)[1]
    if cursor_line < subtasks_first_line or cursor_line > subtasks_last_line then
      return false
    end

    if forward then
      if cursor_line < subtasks_last_line then
        vim.api.nvim_win_set_cursor(win, { cursor_line + 1, 2 })
        return true
      end
      return false
    end

    if cursor_line > subtasks_first_line then
      vim.api.nvim_win_set_cursor(win, { cursor_line - 1, 2 })
      return true
    end
    return false
  end

  local function is_in_tags_zone(line_nr)
    return line_nr >= (tags_first_line or 0) and line_nr <= (tags_last_line or -1)
  end

  local function is_in_log_zone(line_nr)
    return line_nr >= (log_first_line or 0) and line_nr <= (log_last_line or -1)
  end

  local function handle_tab(forward)
    local cursor_line = vim.api.nvim_win_get_cursor(win)[1]
    local zone_name = zones[1].name
    for i, zone in ipairs(zones) do
      if cursor_line >= zone.line then
        zone_name = zone.name
      end
    end

    if forward then
      if zone_name == 'title' then
        focus_description_input_row(true)
        return
      end
      if zone_name == 'description' then
        focus_log_input_row(true)
        return
      end
      if zone_name == 'log' then
        focus_tags_input_row(true)
        return
      end
      if zone_name == 'tags' and subtasks_first_line then
        focus_subtask_line(false)
        return
      end
      if zone_name == 'subtasks' then
        if step_subtask_line(true) then
          return
        end
        focus_zone(1, true)
        return
      end
      focus_zone(1, true)
      return
    end

    if zone_name == 'subtasks' then
      if step_subtask_line(false) then
        return
      end
      focus_tags_input_row(false)
      return
    end
    if zone_name == 'tags' then
      focus_log_input_row(false)
      return
    end
    if zone_name == 'log' then
      focus_description_input_row(false)
      return
    end
    if zone_name == 'description' then
      focus_zone(1, true)
      return
    end
    if zone_name == 'title' then
      if subtasks_first_line then
        focus_subtask_line(true)
      else
        focus_tags_input_row(false)
      end
      return
    end
    focus_zone(1, true)
  end

  local function add_tag_row_below()
    local cursor = vim.api.nvim_win_get_cursor(win)
    local line_nr = cursor[1]
    if not is_in_tags_zone(line_nr) then
      return false
    end
    vim.api.nvim_buf_set_lines(buf, line_nr, line_nr, false, { '  ' })
    tags_last_line = tags_last_line + 1
    tags_input_line = line_nr + 1
    zones[4].line = tags_input_line
    shift_meta_rows(1)
    vim.api.nvim_win_set_cursor(win, { line_nr + 1, tags_col })
    vim.cmd 'startinsert'
    return true
  end

  local function add_log_row_below()
    local cursor = vim.api.nvim_win_get_cursor(win)
    local line_nr = cursor[1]
    if not is_in_log_zone(line_nr) then
      return false
    end
    vim.api.nvim_buf_set_lines(buf, line_nr, line_nr, false, { '  ' })
    log_last_line = log_last_line + 1
    log_input_line = line_nr + 1
    tags_first_line = tags_first_line + 1
    tags_last_line = tags_last_line + 1
    tags_input_line = tags_input_line + 1
    zones[3].line = log_input_line
    zones[4].line = tags_input_line
    shift_meta_rows(1)
    vim.api.nvim_win_set_cursor(win, { line_nr + 1, log_col })
    vim.cmd 'startinsert'
    return true
  end

  vim.keymap.set('n', 'q', dismiss, { buffer = buf, nowait = true, silent = true })
  vim.keymap.set('n', '?', toggle_help, { buffer = buf, nowait = true, silent = true, desc = 'show detail help' })
  vim.keymap.set('n', '<Esc>', dismiss, { buffer = buf, nowait = true, silent = true })
  vim.keymap.set('n', '<CR>', save_and_close, { buffer = buf, nowait = true, silent = true })
  vim.keymap.set('n', 'e', jump, { buffer = buf, nowait = true, silent = true })
  vim.keymap.set('n', 'm', jump_reference, { buffer = buf, nowait = true, silent = true })
  vim.keymap.set('n', 'a', add_subtask_from_detail, { buffer = buf, nowait = true, silent = true, desc = 'add subtask' })
  vim.keymap.set('n', 'S', cycle_card_status,
    { buffer = buf, nowait = true, silent = true, desc = 'cycle todo status' })
  vim.keymap.set('n', 'D', delete_from_detail,
    { buffer = buf, nowait = true, silent = true, desc = 'delete todo' })
  vim.keymap.set('n', 'r', function() edit_relationship_from_detail(nil) end,
    { buffer = buf, nowait = true, silent = true, desc = 'set parent/child relationship' })
  vim.keymap.set('n', 'p', open_parent_from_detail,
    { buffer = buf, nowait = true, silent = true, desc = 'open parent todo' })
  vim.keymap.set('n', 'c', open_child_from_detail,
    { buffer = buf, nowait = true, silent = true, desc = 'open child todo under cursor' })
  vim.keymap.set('n', 'P', cycle_card_priority,
    { buffer = buf, nowait = true, silent = true, desc = 'cycle todo priority' })
  vim.keymap.set({ 'n', 'i' }, '<Tab>', function() handle_tab(true) end,
    { buffer = buf, nowait = true, silent = true, desc = 'next todo card zone' })
  vim.keymap.set({ 'n', 'i' }, '<S-Tab>', function() handle_tab(false) end,
    { buffer = buf, nowait = true, silent = true, desc = 'previous todo card zone' })
  vim.keymap.set('n', 'w', save_edits, { buffer = buf, nowait = true, silent = true, desc = 'save todo edits' })
  vim.keymap.set('i', '<CR>', function()
    if add_tag_row_below() then
      return
    end
    if add_log_row_below() then
      return
    end
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<CR>', true, false, true), 'n', false)
  end, { buffer = buf, nowait = true, silent = true, desc = 'new tag/log row or newline' })

  vim.schedule(function()
    if vim.api.nvim_win_is_valid(win) then
      local should_start_insert = opts.start_insert == true
      local zone = opts.start_zone
      if zone == 'description' then
        focus_zone(2, should_start_insert)
      elseif zone == 'log' or zone == 'details' then
        focus_zone(3, should_start_insert)
      elseif zone == 'tags' or zone == 'newfield' then
        focus_zone(4, should_start_insert)
      elseif zone == 'subtasks' and subtasks_first_line then
        focus_subtask_line(false)
      else
        focus_zone(1, should_start_insert)
      end
    end
  end)
end

-- Buffer-local markdown integration.
local function open_markdown_todo_draft(bufnr, lnum, insert_only)
  local file = vim.api.nvim_buf_get_name(bufnr)
  if file == '' then
    notify_todo('Buffer has no associated file', vim.log.levels.ERROR)
    return
  end

  open_new_todo_draft(nil, nil, {
    title = '',
    parent_id = nil,
    create_reference = true,
    reference = {
      file = file,
      lnum = lnum,
      insert_only = insert_only == true,
    },
  })
end

local function open_markdown_todo_draft_at_cursor(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  local current_line = get_line(bufnr, lnum)

  if is_quote_line(current_line) then
    local target = find_next_non_quote_line(bufnr, lnum)
    local line_count = vim.api.nvim_buf_line_count(bufnr)
    if target > line_count then
      open_markdown_todo_draft(bufnr, target, true)
      return
    end
    if is_blank_line(get_line(bufnr, target)) then
      open_markdown_todo_draft(bufnr, target, false)
    else
      open_markdown_todo_draft(bufnr, target, true)
    end
    return
  end

  if is_blank_line(current_line) then
    open_markdown_todo_draft(bufnr, lnum, false)
    return
  end

  local target = lnum + 1
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  if target > line_count then
    open_markdown_todo_draft(bufnr, target, true)
  elseif is_blank_line(get_line(bufnr, target)) then
    open_markdown_todo_draft(bufnr, target, false)
  else
    open_markdown_todo_draft(bufnr, target, true)
  end
end

local function setup_todo_keymaps()
  local bufnr = 0

  vim.keymap.set('n', '<leader>mt', function()
    vim.cmd 'TodoReference'
  end, { buffer = bufnr, desc = 'todo reference / new todo' })

end

-- Reuse the same cursor-to-item resolution for commands that operate on a
-- markdown TODO reference under the cursor.
local function get_cursor_reference_item()
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor_lnum = vim.api.nvim_win_get_cursor(0)[1]
  return build_item_for_cursor_reference(bufnr, cursor_lnum)
end

local function insert_todo_reference_at_cursor(todo_id, todo_title)
  local bufnr = vim.api.nvim_get_current_buf()
  local file = vim.api.nvim_buf_get_name(bufnr)
  if file == '' then
    notify_todo('Buffer has no associated file', vim.log.levels.ERROR)
    return false
  end

  local store = load_store()
  local idx = find_todo_bucket(store, todo_id)
  if not idx then
    notify_todo('Todo not found in store', vim.log.levels.WARN)
    return false
  end

  local existing_ref_file, existing_ref_lnum = resolve_reference(idx.todo, store)
  if existing_ref_file and existing_ref_lnum then
    local rel = vim.fn.fnamemodify(existing_ref_file, ':~:.')
    local display = (rel ~= '' and rel or existing_ref_file) .. ':' .. tostring(existing_ref_lnum)
    local confirmed = vim.fn.confirm(
      'This todo already has a reference at\n\n' .. display .. '\n\nMove it to the current cursor location?',
      '&Yes\n&No',
      2
    ) == 1
    if not confirmed then
      return false
    end
  end

  local cursor_lnum = vim.api.nvim_win_get_cursor(0)[1]

  if existing_ref_file and existing_ref_lnum then
    local ref_buf = get_loaded_bufnr(existing_ref_file)
    if not ref_buf then
      notify_todo('Could not open existing reference buffer', vim.log.levels.WARN)
      return false
    end

    local line = vim.api.nvim_buf_get_lines(ref_buf, existing_ref_lnum - 1, existing_ref_lnum, false)[1] or ''
    local parsed = parse_reference_line(line)
    if not parsed or parsed.todo_id ~= todo_id then
      notify_todo('Could not verify existing reference line', vim.log.levels.WARN)
      return false
    end

    vim.api.nvim_buf_set_lines(ref_buf, existing_ref_lnum - 1, existing_ref_lnum, false, {})
    maybe_write_buffer(ref_buf)
    adjust_reference_lines_after_insert(store, existing_ref_file, existing_ref_lnum + 1, -1, todo_id)

    if existing_ref_file == file and existing_ref_lnum < cursor_lnum then
      cursor_lnum = math.max(1, cursor_lnum - 1)
    end
  end
  local cursor_line = get_line(bufnr, cursor_lnum)
  local insert_only = not is_blank_line(cursor_line)
  local target_lnum = insert_only and (cursor_lnum + 1) or cursor_lnum
  local line_text = build_reference_line(todo_title or idx.todo.title or '', todo_id)
  local inserted_lnum = create_reference_at_line(bufnr, target_lnum, line_text, insert_only)

  idx.todo.reference = idx.todo.reference or {}
  idx.todo.reference.file = file
  idx.todo.reference.lnum = inserted_lnum
  ensure_todo_source(idx.todo)

  adjust_reference_lines_after_insert(
    store,
    file,
    inserted_lnum + (insert_only and 1 or 0),
    insert_only and 1 or 0,
    todo_id
  )
  maybe_write_buffer(bufnr)

  if not write_store(store) then
    return false
  end

  return true
end

get_todo_picker_opts = function(opts)
  opts = opts or {}
  picker_hierarchy_ui_state = vim.deepcopy(opts._todo_hierarchy_state or {
    collapsed_by_id = {},
    collapse_all = false,
  })

  local message_indent = UI.picker.message_indent
  local items = collect_picker_items(opts)
  local flat_order = is_flat_order_enabled(opts)

  return {
    title = opts.title or 'TODOs',
    _todo_format_opts = opts,
    items = items,
    focus = 'list',
    confirm = open_todo_detail,
    actions = {
      todo_toggle_status = function(picker, item)
        apply_to_selected_todos(picker, item, toggle_todo_status_line)
      end,
      todo_toggle_priority = function(picker, item)
        apply_to_selected_todos(picker, item, toggle_todo_priority_line)
      end,
      todo_delete = function(picker, item)
        picker_delete_todos(picker, item)
      end,
      todo_open_source = function(picker, item)
        picker_open_source(picker, item)
      end,
      todo_open_reference = function(picker, item)
        picker_open_reference(picker, item)
      end,
      todo_open_parent = function(picker, item)
        picker_open_parent_detail(picker, item)
      end,
      todo_create_task = function(picker, item)
        picker_create_task_below(picker, item)
      end,
      todo_create_subtask = function(picker, item)
        picker_create_subtask(picker, item)
      end,
      todo_relationship = function(picker, item)
        picker_prompt_relationship(picker, item, nil)
      end,
      todo_toggle_subtasks = function(picker, item)
        picker_toggle_subtasks(picker, item)
      end,
      todo_toggle_all_subtasks = function(picker)
        picker_toggle_all_subtasks(picker)
      end,
      todo_toggle_help = function(picker)
        toggle_picker_help(picker)
      end,
      todo_prompt_filter = function(picker, item)
        picker_prompt_filter(picker, item)
      end,
      todo_toggle_order_mode = function(picker, item)
        picker_toggle_order_mode(picker, item)
      end,
      todo_toggle_done_visibility = function(picker, item)
        picker_toggle_done_visibility(picker, item)
      end,
      todo_input_escape_to_list = function(picker)
        if vim.fn.mode():sub(1, 1) == 'i' then
          vim.cmd.stopinsert()
        end
        if picker and picker.focus then
          picker:focus('list')
        end
      end,
    },
    format = function(item)
      if item.todo_is_empty_state then
        return {
          { PRIORITY_BADGE[PRIORITY_LOW] or '  ', 'NonText' },
          { UI.picker.row_gap, 'Normal' },
          { UI.picker.tree.base, 'Comment' },
          { '+ New TODO', 'SnacksPickerKeymapLhs' },
        }
      end

      local status = item.todo_status or -1
      local status_color = STATUS_COLOR[status] or 'Normal'
      local title_hl = title_highlight_for_status(item.todo_status_value, status_color)
      local priority = item.todo_priority or PRIORITY_LOW
      local priority_badge = PRIORITY_BADGE[priority] or Config.picker_badges.low
      local priority_hl = PRIORITY_HL[priority] or 'NonText'
      local depth = item.todo_depth or 0
      local is_child = depth > 0
      local has_children = item.todo_has_children == true
      local is_collapsed = item.todo_collapsed == true
      local tree_prefix = UI.picker.tree.base

      if has_children then
        local depth_indent = string.rep(UI.picker.tree.indent_step, is_child and depth or 0)
        tree_prefix = depth_indent .. (is_collapsed and UI.picker.tree.closed or UI.picker.tree.open)
      elseif is_child then
        local depth_indent = string.rep(UI.picker.tree.indent_step, depth)
        tree_prefix = depth_indent .. UI.picker.tree.leaf
      end

      local progress_badge = item.todo_progress_badge or ''
      if progress_badge ~= '' then
        progress_badge = UI.picker.progress_sep .. progress_badge
      end

      local parent_hint = ''
      if item.todo_flat_order and item.todo_parent_title and item.todo_parent_title ~= '' then
        parent_hint = ' [' .. item.todo_parent_title .. ']'
      end

      local tags_hint = ''
      if item.todo_labels and #item.todo_labels > 0 then
        local label_tokens = {}
        for _, label in ipairs(item.todo_labels) do
          label_tokens[#label_tokens + 1] = '#' .. tostring(label)
        end
        tags_hint = ' ' .. table.concat(label_tokens, ' ')
      end

      return {
        { priority_badge, priority_hl },
        { UI.picker.row_gap, 'Normal' },
        { tree_prefix, 'Comment' },
        { item.todo_text or '', title_hl },
        { parent_hint, PARENT_HINT_HL },
        { tags_hint, PARENT_HINT_HL },
        { progress_badge, 'Comment' },
      }
    end,
    live = false,
    on_close = function(picker)
      close_picker_help(picker)
    end,
    layout = vim.deepcopy(UI.picker.layout),
    win = {
      input = {
        keys = {
          ['<Esc>'] = { 'todo_input_escape_to_list', mode = { 'i' }, desc = 'leave input and focus todo list' },
          ['?'] = { 'todo_toggle_help', mode = { 'n' }, desc = 'show picker help' },
          ['/'] = { 'toggle_focus', mode = { 'n' }, desc = 'toggle input/list focus' },
          ['D'] = { 'todo_delete', mode = { 'n' }, desc = 'delete todo' },
          ['<Tab>'] = { 'list_down', mode = { 'n' }, desc = 'next todo' },
          ['<S-Tab>'] = { 'list_up', mode = { 'n' }, desc = 'previous todo' },
          ['S'] = { 'todo_toggle_status', mode = { 'n' }, desc = 'toggle todo status' },
          ['P'] = { 'todo_toggle_priority', mode = { 'n' }, desc = 'toggle todo priority' },
          ['p'] = { 'todo_open_parent', mode = { 'n' }, desc = 'open parent todo details' },
          ['g'] = { 'todo_toggle_order_mode', mode = { 'n' }, desc = 'toggle grouped/global order' },
          ['x'] = { 'todo_toggle_done_visibility', mode = { 'n' }, desc = 'cycle done visibility (hide/recent/all)' },
          ['f'] = { 'todo_prompt_filter', mode = { 'n' }, desc = 'filter todos' },
          ['r'] = { 'todo_relationship', mode = { 'n' }, desc = 'set parent/child relationship' },
          ['z'] = { 'todo_toggle_subtasks', mode = { 'n' }, desc = 'toggle subtasks' },
          ['Z'] = { 'todo_toggle_all_subtasks', mode = { 'n' }, desc = 'toggle all subtasks' },
        },
      },
      list = {
        keys = {
          ['?'] = { 'todo_toggle_help', mode = { 'n' }, desc = 'show picker help' },
          ['/'] = { 'toggle_focus', mode = { 'n' }, desc = 'focus search input' },
          ['i'] = { 'focus_input', mode = { 'n' }, desc = 'focus search input' },
          ['D'] = { 'todo_delete', mode = { 'n' }, desc = 'delete todo' },
          ['<Tab>'] = { 'list_down', mode = { 'n' }, desc = 'next todo' },
          ['<S-Tab>'] = { 'list_up', mode = { 'n' }, desc = 'previous todo' },
          ['S'] = { 'todo_toggle_status', mode = { 'n' }, desc = 'toggle todo status' },
          ['p'] = { 'todo_open_parent', mode = { 'n' }, desc = 'open parent todo details' },
          ['P'] = { 'todo_toggle_priority', mode = { 'n' }, desc = 'toggle todo priority' },
          ['g'] = { 'todo_toggle_order_mode', mode = { 'n' }, desc = 'toggle grouped/global order' },
          ['x'] = { 'todo_toggle_done_visibility', mode = { 'n' }, desc = 'cycle done visibility (hide/recent/all)' },
          ['f'] = { 'todo_prompt_filter', mode = { 'n' }, desc = 'filter todos' },
          ['r'] = { 'todo_relationship', mode = { 'n' }, desc = 'set parent/child relationship' },
          ['t'] = { 'todo_create_task', mode = { 'n' }, desc = 'create task below current' },
          ['a'] = { 'todo_create_subtask', mode = { 'n' }, desc = 'create subtask for current' },
          ['e'] = { 'todo_open_source', mode = { 'n' }, desc = 'open todo source' },
          ['m'] = { 'todo_open_reference', mode = { 'n' }, desc = 'open markdown reference' },
          ['z'] = { 'todo_toggle_subtasks', mode = { 'n' }, desc = 'toggle subtasks' },
          ['Z'] = { 'todo_toggle_all_subtasks', mode = { 'n' }, desc = 'toggle all subtasks' },
        },
        wo = {
          wrap = true,
          linebreak = true,
          breakindent = true,
          breakindentopt = string.format('shift:%d,min:%d', message_indent, message_indent),
          showbreak = ' ',
        },
      },
    },
    matcher = { sort_empty = true },
    sort = {
      fields = {
        'todo_grouped_order:asc',
        'todo_status:asc',
        'todo_completed_sort_effective:asc',
        'todo_priority_sort_effective:asc',
        'todo_created_sort:asc',
        'score:desc',
        'idx',
      },
    },
  }
end

-- Keep command registration factored out so the plugin spec stays readable and
-- future command edits stay in one place.
local function register_todo_user_commands()
  vim.api.nvim_create_user_command('TodoFilter', function(cmd)
    local filters = parse_filter_args(cmd.args)
    if #filters == 0 then
      notify_todo('Usage: :TodoFilter #label[,field=value,...]', vim.log.levels.WARN)
      return
    end
    open_todo_picker {
      filters = filters,
      apply_done_retention = false,
      title = build_filter_title(filters),
    }
  end, {
    nargs = '*',
    desc = 'Show TODOs filtered by metadata fields or labels',
  })

  vim.api.nvim_create_user_command('TodoGoTo', function()
    local item = get_cursor_reference_item()
    if not item then
      notify_todo('Cursor is not on a TODO reference line', vim.log.levels.WARN)
      return
    end
    open_todo_detail(nil, item, { start_zone = 'log', start_insert = false })
  end, { desc = 'Open details for the TODO under cursor' })

  local function run_todo_reference_picker()
    if vim.bo.filetype ~= 'markdown' then
      notify_todo('TodoReference works in markdown buffers', vim.log.levels.WARN)
      return
    end

    local opts = get_todo_picker_opts {
      title = 'Select TODO To Reference',
      apply_done_retention = false,
    }

    opts.confirm = function(picker, item)
      local target = picker_current_item(picker, item) or item
      if not target then
        return
      end

      if picker and picker.close then
        picker:close()
      end

      if target.todo_is_empty_state then
        open_markdown_todo_draft_at_cursor(vim.api.nvim_get_current_buf())
        return
      end

      if not target.todo_id then
        return
      end

      local ok = insert_todo_reference_at_cursor(target.todo_id, target.todo_text or target.text)
      if ok then
        notify_todo('Inserted TODO reference')
      end
    end

    Snacks.picker(opts)
  end

  vim.api.nvim_create_user_command('TodoReference', run_todo_reference_picker,
    { desc = 'Insert a TODO reference in markdown via picker selection' })
end

local function register_todo_autocmds()
  vim.api.nvim_create_autocmd('FileType', {
    pattern = Config.filetypes,
    callback = setup_todo_keymaps,
  })

  vim.api.nvim_create_autocmd('ColorScheme', {
    callback = apply_todo_status_highlights,
  })
end

return {
  {
    'folke/snacks.nvim',
    init = function()
      apply_todo_status_highlights()
      register_todo_user_commands()
      register_todo_autocmds()
    end,
    keys = {
      {
        '<leader>ft',
        function()
          open_todo_picker()
        end,
        desc = 'all todos',
      },
    },
  },
}
