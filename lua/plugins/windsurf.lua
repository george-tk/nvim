return {
  'Exafunction/windsurf.nvim',
  event = 'VeryLazy',
  dependencies = {
    'nvim-lua/plenary.nvim',
  },
  config = function()
    -- Ensure Windsurf/Codeium language server routes inference through server.codeium.com
    -- (default inference.codeium.com / server.windsurf.com can time out on some ISP/WSL networks)
    local function wrap_spawn_with_inference_url(orig_spawn)
      return function(path, spawn_opts, on_exit)
        if spawn_opts and type(spawn_opts.args) == 'table' and tostring(path):find 'language_server' then
          local has_inference = false
          for _, arg in ipairs(spawn_opts.args) do
            if arg == '--inference_api_server_url' then
              has_inference = true
              break
            end
          end
          if not has_inference then
            local api_url = 'https://server.codeium.com'
            for i, arg in ipairs(spawn_opts.args) do
              if arg == '--api_server_url' and spawn_opts.args[i + 1] then
                api_url = spawn_opts.args[i + 1]
                break
              end
            end
            table.insert(spawn_opts.args, '--inference_api_server_url')
            table.insert(spawn_opts.args, api_url)
          end
        end
        return orig_spawn(path, spawn_opts, on_exit)
      end
    end

    local orig_uv_spawn = vim.uv.spawn
    vim.uv.spawn = wrap_spawn_with_inference_url(orig_uv_spawn)

    -- Codeium retired https://api.codeium.com/register_user/ (returns 404 plain text, breaking json_decode).
    -- Route RegisterUser auth POSTs to the live server.codeium.com JSON endpoint instead.
    local ok_io, codeium_io = pcall(require, 'codeium.io')
    if ok_io and codeium_io and codeium_io.post and not codeium_io._register_user_patched then
      codeium_io._register_user_patched = true
      local orig_post = codeium_io.post
      codeium_io.post = function(url, opts)
        if type(url) == 'string' and url:find('api%.codeium%.com/register_user') then
          url = 'https://server.codeium.com/exa.seat_management_pb.SeatManagementService/RegisterUser'
        end
        return orig_post(url, opts)
      end
    end

    require('codeium').setup {
      -- Reuse ~/.codeium/config.json (shared with neocodeium so existing auth carries over automatically)
      config_path = vim.fn.expand '~/.codeium/config.json',
      enable_cmp_source = false,
      virtual_text = {
        enabled = true,
        manual = false,
        idle_delay = 75,
        virtual_text_priority = 65535,
        map_keys = true,
        default_filetype_enabled = true,
        filetypes = {
          help = false,
          gitcommit = false,
          gitrebase = false,
          opencode_ask = false,
          markdown = false,
          dbui = false,
          dbout = false,
          ['sqmeow-drawer'] = false,
          ['sqmeow-result'] = false,
          snacks_picker_input = false,
          snacks_dashboard = false,
          snacks_terminal = false,
          ['.'] = false,
        },
        key_bindings = {
          accept = '<M-a>',
          accept_word = '<M-w>',
          accept_line = '<M-e>',
          next = '<M-n>',
          prev = '<M-p>',
          clear = '<M-c>',
        },
      },
    }

    vim.uv.spawn = orig_uv_spawn

    vim.api.nvim_set_hl(0, 'CodeiumSuggestion', { fg = '#7f849c', ctermfg = 244, default = false })

    vim.keymap.set('n', '<leader>aU', '<cmd>Codeium Auth<CR>', { desc = 'AI Auth / Status' })
  end,
}
