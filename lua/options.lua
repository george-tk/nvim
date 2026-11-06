-- options.lua

-- Aliases for Neovim options
local o = vim.opt
local g = vim.g

---
-- General UI & Editor Basics
-------------------------------------------------------------------------------
o.termguicolors = true -- True colors
o.number = true -- Line numbers
o.relativenumber = true -- Relative line numbers
o.mouse = 'a' -- Mouse support
o.showmode = false -- Hide mode messages
o.cmdheight = 0 -- Command line height
o.pumheight = 10 -- Completion menu height
o.clipboard = 'unnamedplus' -- Allow for copy and pasting
o.updatetime = 250 -- Faster completion & CursorHold trigger (default 4000ms)
o.timeout = true
o.timeoutlen = 500 -- Reliable key chord timeout for WSL (which-key still opens in 0ms via delay = 0)
o.ttimeoutlen = 10 -- Fast terminal escape sequence resolution (<Esc>)

-- WSL Bidirectional Clipboard Integration (Zero-lag async copy + clean CRLF-stripped paste)
local is_wsl = vim.fn.has 'wsl' == 1 or os.getenv 'WSL_DISTRO_NAME' ~= nil
if is_wsl then
  local has_win32yank = vim.fn.executable 'win32yank.exe' == 1
  local has_wl = os.getenv 'WAYLAND_DISPLAY' ~= nil and vim.fn.executable 'wl-paste' == 1 and vim.fn.executable 'wl-copy' == 1
  local has_clip = vim.fn.executable 'clip.exe' == 1
  local has_pwsh = vim.fn.executable 'powershell.exe' == 1

  local clip_cache = {
    lines = nil,
    regtype = 'v',
    internal_ts = 0,
    external_dirty = true,
  }

  local function split_clean_lines(raw)
    if not raw then
      return { '' }
    end
    local cleaned = raw:gsub('\r\n', '\n'):gsub('\r', '\n')
    cleaned = cleaned:gsub('\n$', '')
    return vim.split(cleaned, '\n', { plain = true })
  end

  local function get_paste_cmd()
    if has_win32yank then
      return { 'win32yank.exe', '-o', '--lf' }
    elseif has_wl then
      return { 'wl-paste', '--no-newline' }
    elseif has_pwsh then
      return {
        'powershell.exe',
        '-NoProfile',
        '-NoLogo',
        '-NonInteractive',
        '-Command',
        '[Console]::OutputEncoding=[System.Text.Encoding]::UTF8; Get-Clipboard -Raw',
      }
    end
    return nil
  end

  local function async_prefetch_windows_clipboard()
    local cmd = get_paste_cmd()
    if not cmd or not vim.system then
      return
    end
    pcall(vim.system, cmd, { text = true }, function(out)
      if out and out.code == 0 and out.stdout then
        clip_cache.lines = split_clean_lines(out.stdout)
        clip_cache.regtype = 'v'
        clip_cache.external_dirty = false
      end
    end)
  end

  local wsl_augroup = vim.api.nvim_create_augroup('UserWslClipboard', { clear = true })
  vim.api.nvim_create_autocmd('FocusLost', {
    group = wsl_augroup,
    callback = function()
      clip_cache.external_dirty = true
    end,
  })
  vim.api.nvim_create_autocmd('FocusGained', {
    group = wsl_augroup,
    callback = function()
      clip_cache.external_dirty = true
      async_prefetch_windows_clipboard()
    end,
  })

  local function wsl_copy(lines, regtype)
    clip_cache.lines = vim.deepcopy(lines)
    clip_cache.regtype = regtype or 'v'
    clip_cache.internal_ts = (vim.uv or vim.loop).now()
    clip_cache.external_dirty = false

    -- 1. Emit OSC 52 escape sequence to terminal immediately (0ms latency in Windows Terminal / WezTerm / Alacritty / VS Code)
    pcall(function()
      require('vim.ui.clipboard.osc52').copy '+'(lines, regtype)
    end)

    -- 2. Asynchronously sync to native Windows clipboard so y/d/c/x NEVER block Neovim's UI thread
    if vim.system then
      local text = table.concat(lines, '\n')
      if has_win32yank then
        pcall(vim.system, { 'win32yank.exe', '-i', '--crlf' }, { stdin = text })
      elseif has_wl then
        pcall(vim.system, { 'wl-copy' }, { stdin = text })
      elseif has_clip then
        pcall(vim.system, { 'clip.exe' }, { stdin = text:gsub('\n', '\r\n') })
      end
    end
  end

  local function wsl_paste()
    local now = (vim.uv or vim.loop).now()
    -- If yanked/deleted inside Neovim recently (< 2s) and terminal focus wasn't lost, return cached lines in 0ms
    if not clip_cache.external_dirty and clip_cache.lines and (now - clip_cache.internal_ts) < 2000 then
      return { clip_cache.lines, clip_cache.regtype or 'v' }
    end

    local cmd = get_paste_cmd()
    if cmd and vim.system then
      local ok, proc = pcall(vim.system, cmd, { text = true })
      if ok and proc then
        local res = proc:wait(1500)
        if res and res.code == 0 and res.stdout then
          local lines = split_clean_lines(res.stdout)
          clip_cache.lines = lines
          clip_cache.external_dirty = false
          return { lines, 'v' }
        end
      end
    end

    if clip_cache.lines then
      return { clip_cache.lines, clip_cache.regtype or 'v' }
    end
    return { { '' }, 'v' }
  end

  g.clipboard = {
    name = 'WslClipboardZeroLag',
    copy = {
      ['+'] = wsl_copy,
      ['*'] = wsl_copy,
    },
    paste = {
      ['+'] = wsl_paste,
      ['*'] = wsl_paste,
    },
    cache_enabled = 0,
  }
end
---
-- Indentation
-------------------------------------------------------------------------------
o.expandtab = true -- Spaces for tabs
o.tabstop = 2 -- Tab width
o.shiftwidth = 2 -- Indent width
o.softtabstop = 2 -- Tab key behavior
o.autoindent = true -- Auto-indent

---
-- Editing Enhancements
-------------------------------------------------------------------------------
o.breakindent = true -- Wrapped line indent
o.ignorecase = true -- Case-insensitive search
o.smartcase = true -- Smart case search
o.inccommand = 'split' -- Live substitution preview
o.cursorline = true -- Highlight current line
o.confirm = true -- Confirm unsaved close

---
-- File Handling & History
-------------------------------------------------------------------------------
o.undofile = true -- Save undo history
o.swapfile = false -- Disable swap files (no crash recovery)
o.sessionoptions = { -- Clean session restore (NEVER save blank or terminal splits)
  'buffers',
  'curdir',
  'tabpages',
  'winsize',
  'help',
  'skiprtp',
}

---
-- Visual Layout
-------------------------------------------------------------------------------
o.numberwidth = 2 -- Minimum width for line numbers (default 4)
o.signcolumn = 'yes' -- Always show signcolumn
o.splitright = true -- Vertical splits right
o.splitbelow = true -- Horizontal splits below
o.equalalways = false -- Don't auto-resize splits to equal size on open/close
o.splitkeep = 'screen' -- Keep cursor and screen position on split
o.scrolloff = 8 -- Scroll context lines
-- o.list = true -- Show invisible chars
-- o.listchars = { -- Invisible char display
--   tab = '» ',
--   trail = '·',
--   nbsp = '␣',
-- }

---
-- Spelling
-------------------------------------------------------------------------------
o.spell = false -- Scoped to prose/notes (markdown, text, gitcommit); toggle anywhere with <leader>st
o.spelllang = { 'en_gb' } -- British English

---
-- Folding (Tree-sitter based)
-------------------------------------------------------------------------------
o.foldcolumn = '0' -- Disable separate fold column (folds shown in statuscolumn)
o.foldmethod = 'expr' -- Expression folding
o.foldexpr = 'v:lua.vim.treesitter.foldexpr()' -- Treesitter folding
o.foldlevel = 99 -- All folds open
o.foldenable = true -- Enable folding
o.foldtext = '' -- Empty fold text
o.foldopen = 'mark,percent,quickfix,search,tag,undo' -- Auto-open folds (except horizontal movement)
o.fillchars = { -- Split and fold fill characters
  horiz = '━',
  horizup = '┻',
  horizdown = '┳',
  vert = '┃',
  vertleft = '┫',
  vertright = '┣',
  verthoriz = '╋',
  foldopen = '',
  foldclose = '',
  fold = ' ',
  foldsep = ' ',
  diff = ' ',
  eob = ' ',
}

---
-- Global Flags & Minor Optimizations
-------------------------------------------------------------------------------
g.have_nerd_font = true -- Nerd Font flag
g.markdown_recommended_style = 0 -- prevents rewrite of markdown style

---
-- Custom Window Title
-------------------------------------------------------------------------------
o.title = true -- Enable window title setting
o.titlestring = "%{expand('%:t') == '' ? '[No Name]' : expand('%:p:h:t') . ': ' . expand('%:t')}"
