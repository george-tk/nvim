local function has_real_buffers()
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(b) and vim.bo[b].buflisted and vim.bo[b].buftype == '' then
      local name = vim.api.nvim_buf_get_name(b)
      if name ~= '' and not name:match '^%[' and not name:find '/sqmeow/' and not name:find '/db_ui/' then
        return true
      end
    end
  end
  return false
end

local function list_recent_sessions(opts)
  opts = opts or {}
  local uv = vim.uv or vim.loop
  local ok_pc, pc = pcall(require, 'persistence.config')
  local session_dir = (ok_pc and pc and pc.options and pc.options.dir) or (vim.fn.stdpath 'state' .. '/sessions/')
  if session_dir:sub(-1) ~= '/' then
    session_dir = session_dir .. '/'
  end

  local files = vim.fn.glob(session_dir .. '*.vim', true, true)
  local entries = {}
  for _, sfile in ipairs(files) do
    local st = uv.fs_stat(sfile)
    if st and st.mtime then
      table.insert(entries, { file = sfile, mtime = st.mtime.sec })
    end
  end
  table.sort(entries, function(a, b)
    return a.mtime > b.mtime
  end)

  local config_dir = vim.fs.normalize(vim.fn.stdpath 'config')
  local seen = {}
  local result = {}
  for _, entry in ipairs(entries) do
    local raw = entry.file:sub(#session_dir + 1, -5)
    local dir_part = vim.split(raw, '%%', { plain = true })[1]
    if dir_part and dir_part ~= '' then
      local dir = dir_part:gsub('%%', '/')
      if jit and jit.os and jit.os:find 'Windows' then
        dir = dir:gsub('^(%w)/', '%1:/')
      end
      dir = vim.fs.normalize(dir)
      local excluded = opts.exclude_config and dir == config_dir
      if
        not excluded
        and not seen[dir]
        and not dir:find '/sqmeow/'
        and not dir:find '/db_ui/'
        and not dir:find 'nvim/assets'
        and vim.fn.isdirectory(dir) == 1
      then
        seen[dir] = true
        table.insert(result, { dir = dir, mtime = entry.mtime })
        if opts.limit and #result >= opts.limit then
          break
        end
      end
    end
  end
  return result
end

local function open_project_clean(dir, target_file)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buflisted and vim.bo[buf].modified then
      vim.notify('Save or discard modified buffers before opening another project', vim.log.levels.WARN, { title = 'Project' })
      return
    end
  end

  if not dir and target_file then
    dir = Snacks.git.get_root(target_file) or vim.fs.dirname(target_file)
  end
  if not dir then
    return
  end
  dir = vim.fs.normalize(dir)

  -- Clean up docked right/bottom panels before saving outgoing session (matches <leader>d behavior)
  local ok_layout, layout = pcall(require, 'utils.layout')
  if ok_layout and layout.cleanup_panels_before_save then
    layout.cleanup_panels_before_save()
  end

  local ok_p, persistence = pcall(require, 'persistence')
  if ok_p and has_real_buffers() then
    pcall(function()
      persistence.save()
    end)
  end

  if Snacks and Snacks.bufdelete then
    Snacks.bufdelete.all()
  else
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buflisted then
        pcall(vim.api.nvim_buf_delete, buf, {})
      end
    end
  end

  pcall(vim.cmd, 'only')
  vim.cmd.cd(vim.fn.fnameescape(dir))

  pcall(function()
    require('snacks.explorer.git').update(dir, { untracked = true })
  end)

  local session_loaded = false
  if ok_p then
    local session_file = persistence.current()
    if vim.fn.filereadable(session_file) == 1 then
      persistence.load()
      session_loaded = true
    else
      local fallback_file = persistence.current { branch = false }
      if fallback_file and vim.fn.filereadable(fallback_file) == 1 then
        persistence.load { branch = false }
        session_loaded = true
      end
    end
  end

  if target_file then
    vim.cmd.edit(vim.fn.fnameescape(target_file))
  elseif not session_loaded then
    Snacks.picker.files { cwd = dir }
  end
end

local function format_age(mtime)
  local diff = math.max(0, os.time() - (mtime or 0))
  if diff < 60 then
    return 'just now'
  elseif diff < 3600 then
    return math.floor(diff / 60) .. 'm ago'
  elseif diff < 86400 then
    return math.floor(diff / 3600) .. 'h ago'
  else
    return math.floor(diff / 86400) .. 'd ago'
  end
end

local function pick_project_session()
  local sessions = list_recent_sessions { exclude_config = false }
  if #sessions == 0 then
    vim.notify('No saved project sessions found', vim.log.levels.INFO, { title = 'Projects' })
    return
  end

  -- 1-9, then a-z (skipping i/j/k/q so list navigation, insert/search, and quit stay intact)
  local hotkey_chars = {
    '1', '2', '3', '4', '5', '6', '7', '8', '9',
    'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'l', 'm', 'n', 'o', 'p', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z',
  }

  local cur_cwd = vim.fs.normalize(vim.fn.getcwd())
  local items = {}
  local actions = {}
  local list_keys = {
    ['/'] = { 'focus_input', mode = 'n' },
    ['i'] = { 'focus_input', mode = 'n' },
  }
  local input_keys = {}

  for i, s in ipairs(sessions) do
    local display = vim.fn.fnamemodify(s.dir, ':~')
    local hk = hotkey_chars[i]
    table.insert(items, {
      idx = i,
      hotkey = hk,
      text = display,
      dir = s.dir,
      age = format_age(s.mtime),
      is_current = (s.dir == cur_cwd and vim.bo.filetype ~= 'snacks_dashboard'),
    })
    if hk then
      local action_name = 'open_project_' .. i
      local target_dir = s.dir
      actions[action_name] = function(picker)
        picker:close()
        open_project_clean(target_dir)
      end
      list_keys[hk] = { action_name, mode = 'n' }
      input_keys[hk] = { action_name, mode = 'n' }
    end
  end

  Snacks.picker.pick {
    title = 'Projects (1-9/a-z jump, / search)',
    items = items,
    focus = 'list',
    layout = {
      preset = 'vscode',
      hidden = { 'preview' },
    },
    actions = actions,
    win = {
      list = { keys = list_keys },
      input = { keys = input_keys },
    },
    format = function(item)
      local badge = item.hotkey and (item.hotkey .. '  ') or '   '
      local ret = {
        { badge, 'Number' },
        { '󰉋 ', item.is_current and 'DiagnosticOk' or 'Directory' },
        { item.text, item.is_current and 'Title' or 'Normal' },
        { '  ' .. item.age, 'Comment' },
      }
      if item.is_current then
        table.insert(ret, { '  (current)', 'DiagnosticOk' })
      end
      return ret
    end,
    confirm = function(picker, item)
      picker:close()
      if item and item.dir then
        open_project_clean(item.dir)
      end
    end,
  }
end

_G.OpenProjectClean = open_project_clean
_G.PickProjectSession = pick_project_session

-- Handle `nvim <dir>` like opening a project: cd into it, restore its persistence session
-- if one exists, or leave a clean empty buffer (no dashboard / no explorer) if none exists.
vim.api.nvim_create_autocmd('VimEnter', {
  group = vim.api.nvim_create_augroup('UserOpenDirectoryAsProject', { clear = true }),
  nested = true,
  callback = function()
    if vim.fn.argc() ~= 1 then
      return
    end
    local arg = vim.fn.argv(0)
    if not arg or arg == '' or vim.fn.isdirectory(arg) ~= 1 then
      return
    end

    local dir = vim.fs.normalize(vim.fn.fnamemodify(arg, ':p'))
    if #dir > 1 then
      dir = dir:gsub('/+$', '')
    end

    local dir_buf = vim.api.nvim_get_current_buf()
    vim.cmd.cd(vim.fn.fnameescape(dir))

    -- Replace the directory buffer with a clean empty buffer
    vim.cmd 'enew'
    if vim.api.nvim_buf_is_valid(dir_buf) and dir_buf ~= vim.api.nvim_get_current_buf() then
      pcall(vim.api.nvim_buf_delete, dir_buf, { force = true })
    end

    pcall(function()
      require('snacks.explorer.git').update(dir, { untracked = true })
    end)

    pcall(function()
      require('lazy').load { plugins = { 'persistence.nvim' } }
    end)
    local ok_p, persistence = pcall(require, 'persistence')
    if ok_p then
      local session_file = persistence.current()
      if vim.fn.filereadable(session_file) == 1 then
        persistence.load()
      else
        local fallback_file = persistence.current { branch = false }
        if fallback_file and vim.fn.filereadable(fallback_file) == 1 then
          persistence.load { branch = false }
        end
      end
    end
  end,
})

local function get_last_session_label()
  local sessions = list_recent_sessions { exclude_config = false, limit = 1 }
  if sessions[1] and sessions[1].dir then
    return vim.fn.fnamemodify(sessions[1].dir, ':~')
  end
  return nil
end

local function restore_last_clean()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buflisted and vim.bo[buf].modified then
      vim.notify('Save or discard modified buffers before restoring session', vim.log.levels.WARN, { title = 'Session' })
      return
    end
  end

  local ok, p = pcall(require, 'persistence')
  if not ok then
    return
  end
  local last = p.last()
  if not last or vim.fn.filereadable(last) == 0 then
    vim.notify('No previous session found to restore', vim.log.levels.WARN, { title = 'Session' })
    return
  end

  if Snacks and Snacks.bufdelete then
    Snacks.bufdelete.all()
  else
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buflisted then
        pcall(vim.api.nvim_buf_delete, buf, {})
      end
    end
  end

  p.load { last = true }

  pcall(function()
    require('snacks.explorer.git').update(vim.fn.getcwd(), { untracked = true })
  end)
end

return {
  'folke/snacks.nvim',
  lazy = false,
  priority = 1000,
  opts = {
    bigfile = { enabled = true },
    dashboard = {
      enabled = true,
      preset = {
        header = [[
===================================
========-:          :==============
=====:                  :==========
===:                      :========
====-:                      =======
==============-:..           :=====
==========+*=======================
========    +#%#%%=================
========  -.##@%=*#================
=====-:..%* .:==...@===============
====     .  -@=.   :@@=============
===.      :  :- :#@@@#@+===========
===         %@@@%#@@: :============
==-               .=#. :+==========
==-               :-*@+..:=========
===         .     .=*@==#+%@=======
===          :-*+*##%%@+*@@%@@%====
==-          ==**#%%%%@@@@**#*@@@*=
===:        :-=***#*%%%%@%+-:-#@@@=
====        -====*###%%%%%#-.-@@@%=
====:      .=+==+*++*%%%%%%%#@@@@+=
=====      =+*+=+*==++=****#@@@@+==
=====      =***++*==++==::%@@@@@===
====      :*****+++====-=@@@@@@*===
===.      :+#*****=-===*@@@@@*=====
==-   :   -+*****+-:=*%=%==========
==:   =   =+#**===+%%@@..==========
==   -=   =:-:*=#*#%@@=+ :*========
=.   =-   -==****#%@@+===::========
=         *%%%@@%#%*=====*=========
===================================]],
        -- stylua: ignore
        -- keys = {
        --   { icon = '󰱼 ', key = 'f', desc = 'File', action = function() Snacks.picker.files() end },
        --   { icon = '󰺮 ', key = 'w', desc = 'Word', action = function() Snacks.picker.grep_word() end },
        --   { icon = ' ', key = 'r', desc = 'Restore', action = function() require('persistence').load { last = true } end },
        --   { icon = '󰦖 ', key = 'l', desc = 'Load', action = function() require('persistence').select() end },
        -- },
        keys = {},
      },
      sections = {
        {
          pane = 1,
          { padding = 3 },
          {
            icon = ' ',
            title = 'Projects',
            section = 'projects',
            indent = 2,
            padding = 2,
            limit = 9,
            dirs = function()
              local sessions = list_recent_sessions { exclude_config = true, limit = 9 }
              return vim.tbl_map(function(s)
                return s.dir
              end, sessions)
            end,
            action = open_project_clean,
          },
          function()
            local last_label = get_last_session_label()
            local restore_desc = last_label and ('Restore Session (' .. last_label .. ')') or 'Restore Session'
            return {
              {
                icon = ' ',
                key = 'c',
                desc = 'Config',
                action = function()
                  open_project_clean(vim.fn.stdpath 'config')
                end,
                padding = 1,
              },
              {
                icon = ' ',
                key = 'r',
                desc = restore_desc,
                action = restore_last_clean,
                padding = 1,
              },
              {
                icon = ' ',
                key = 'q',
                desc = 'Quit',
                action = ':qa',
              },
            }
          end,
        },
        {
          pane = 2,
          { padding = 1 },
          { section = 'header', indent = 11 },
        },
      },
    },
  },
}
