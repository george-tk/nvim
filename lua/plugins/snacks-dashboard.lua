local function has_real_buffers()
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(b) and vim.bo[b].buflisted and vim.bo[b].buftype == '' then
      local name = vim.api.nvim_buf_get_name(b)
      if name ~= '' and not name:match('^%[') and not name:find('/sqmeow/') and not name:find('/db_ui/') then
        return true
      end
    end
  end
  return false
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
  if not dir then return end

  local ok_p, persistence = pcall(require, 'persistence')
  if ok_p and has_real_buffers() then
    pcall(function() persistence.save() end)
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
      local fallback_file = persistence.current({ branch = false })
      if fallback_file and vim.fn.filereadable(fallback_file) == 1 then
        persistence.load({ branch = false })
        session_loaded = true
      end
    end
  end

  if target_file then
    vim.cmd.edit(vim.fn.fnameescape(target_file))
  elseif not session_loaded then
    Snacks.picker.files({ cwd = dir })
  end
end

local function restore_last_clean()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buflisted and vim.bo[buf].modified then
      vim.notify('Save or discard modified buffers before restoring session', vim.log.levels.WARN, { title = 'Session' })
      return
    end
  end

  local ok, p = pcall(require, 'persistence')
  if not ok then return end
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

  p.load({ last = true })

  pcall(function()
    require('snacks.explorer.git').update(vim.fn.getcwd(), { untracked = true })
  end)
end

return {
  'folke/snacks.nvim',
  lazy = false,
  priority = 1000,
  opts = {
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
        keys = {
              { icon = " ", key = "f", desc = "Find File", action = ":lua Snacks.dashboard.pick('files')" },
              { icon = " ", key = "n", desc = "New File", action = ":lua local name = vim.fn.input('File name: '); if name ~= '' then vim.cmd('e ' .. name) end" },
              { icon = " ", key = "t", desc = "Find Text", action = ":lua Snacks.dashboard.pick('live_grep')" },
              { icon = " ", key = "c", desc = "Config", action = ":lua Snacks.dashboard.pick('files', {cwd = vim.fn.stdpath('config')})" },
              {
                icon = " ",
                key = "r",
                desc = "Restore Session",
                action = restore_last_clean,
              },
         --     { icon = "󰒲 ", key = "l", desc = "Lazy", action = ":Lazy", enabled = package.loaded.lazy ~= nil },
              { icon = " ", key = "q", desc = "Quit", action = ":qa" },
            },
      },
      sections = {
        {
          pane = 1,
          { padding = 4 },
          { section = 'keys', gap = 1, padding = 2 },
          {
            icon = ' ',
            title = 'Projects',
            section = 'projects',
            indent = 2,
            padding = 2,
            limit = 5,
            action = open_project_clean,
            filter = function(dir)
              return dir and not dir:find('/sqmeow/') and not dir:find('/db_ui/') and not dir:find('nvim/assets')
            end,
          },
          {
            icon = ' ',
            title = 'Recent Files',
            indent = 2,
            padding = 2,
            function()
              local gen = Snacks.dashboard.sections.recent_files({
                limit = 5,
                filter = function(file)
                  if not file then return false end
                  if file:find('/sqmeow/') or file:find('/db_ui/') or file:match('%.sqlite%d?$') or file:match('%.db$') then
                    return false
                  end
                  return true
                end,
              })
              local items = gen()
              for _, item in ipairs(items or {}) do
                local target = item.file
                item.action = function()
                  open_project_clean(nil, target)
                end
              end
              return items
            end,
          },
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
