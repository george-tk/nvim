return {
  'Exafunction/windsurf.nvim',
  event = 'VeryLazy',
  dependencies = {
    'nvim-lua/plenary.nvim',
  },
  config = function()
    -- Patch codeium.io before setup():
    -- 1. Route retired https://api.codeium.com/register_user/ (404) to live server.codeium.com JSON endpoint.
    -- 2. Pass --inference_api_server_url to language_server (default inference.codeium.com has no DNS).
    local ok_io, codeium_io = pcall(require, 'codeium.io')
    if ok_io and codeium_io then
      if codeium_io.post and not codeium_io._register_user_patched then
        codeium_io._register_user_patched = true
        local orig_post = codeium_io.post
        codeium_io.post = function(url, opts)
          if type(url) == 'string' and url:find 'api%.codeium%.com/register_user' then
            url = 'https://server.codeium.com/exa.seat_management_pb.SeatManagementService/RegisterUser'
          end
          return orig_post(url, opts)
        end
      end

      if codeium_io.job and not codeium_io._inference_job_patched then
        codeium_io._inference_job_patched = true
        local orig_job = codeium_io.job
        codeium_io.job = function(job_args)
          if type(job_args) == 'table' and tostring(job_args[1] or ''):find 'language_server' then
            local has_inference = false
            local api_url = 'https://server.codeium.com:443'
            for i, arg in ipairs(job_args) do
              if arg == '--inference_api_server_url' then
                has_inference = true
              elseif arg == '--api_server_url' and job_args[i + 1] then
                api_url = job_args[i + 1]
              end
            end
            if not has_inference then
              table.insert(job_args, '--inference_api_server_url')
              table.insert(job_args, api_url)
            end
          end
          return orig_job(job_args)
        end
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

    vim.api.nvim_set_hl(0, 'CodeiumSuggestion', { fg = '#7f849c', ctermfg = 244, default = false })

    vim.keymap.set('n', '<leader>aU', '<cmd>Codeium Auth<CR>', { desc = 'AI Auth / Status' })
  end,
}
