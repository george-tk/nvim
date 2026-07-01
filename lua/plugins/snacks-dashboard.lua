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
              { icon = " ", key = "r", desc = "Restore Session", section = "session" },
         --     { icon = "󰒲 ", key = "l", desc = "Lazy", action = ":Lazy", enabled = package.loaded.lazy ~= nil },
              { icon = " ", key = "q", desc = "Quit", action = ":qa" },
            },
      },
      sections = {
        { padding = 1 },
        {
          section = 'header',
        },
        {
          pane = 2,
          { padding = 4 },
          { section = 'keys', gap = 1, padding = 2 },
          { icon = ' ', title = 'Projects', section = 'projects', indent = 2, padding = 2 },
          { icon = ' ', title = 'Recent Files', section = 'recent_files', indent = 2, padding = 2 },
        },
      },
    },
  },
}
