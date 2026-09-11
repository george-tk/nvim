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
                action = function()
                  local ok, p = pcall(require, "persistence")
                  if not ok then return end
                  local last = p.last()
                  if not last or vim.fn.filereadable(last) == 0 then
                    vim.notify("No previous session found to restore", vim.log.levels.WARN, { title = "Session" })
                    return
                  end
                  p.load({ last = true })
                end,
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
            filter = function(dir)
              return dir and not dir:find('db_ui') and not dir:find('nvim/assets')
            end,
          },
          {
            icon = ' ',
            title = 'Recent Files',
            section = 'recent_files',
            indent = 2,
            padding = 2,
            filter = function(file)
              if not file then return false end
              if file:find('/db_ui/') or file:match('%.sqlite%d?$') or file:match('%.db$') then
                return false
              end
              return true
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
