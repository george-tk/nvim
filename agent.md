# Neovim Configuration Maintenance & Plugin Audit Guide (`agent.md`)

This document serves as the single source of truth for auditing, updating, and maintaining all Neovim plugins in [`/home/georgek/.config/nvim`](file:///home/georgek/.config/nvim). Modeled after [`database_agent.md`](file:///home/georgek/.config/nvim/database_agent.md), future AI pairing sessions and maintainers should use this playbook to audit upstream plugin changes, detect redundant user code, track breaking changes, and evaluate modern plugin alternatives.

---

## 0. Git Commit & Push Policy (MANDATORY RULE)

> [!CAUTION]
> **Personal Neovim Config & Dotfiles (`~/.config/nvim` / dotfiles)**:
> **NEVER execute `git commit` or `git push`** unless the user specifically and explicitly asks you to after reviewing and being completely satisfied with the changes. Keep changes local and unstaged until an explicit user request is received.
>
> **External Repositories (e.g. `sqmeow.nvim` / open source forks)**:
> This restriction does NOT apply to external repositories where you are managing issues, creating branches, running test suites, and submitting PRs. You retain full Git control over those repositories.

---

## 1. Upstream Baseline Reference & Inventory

The table below catalogs all **36 installed plugins** managed by `lazy.nvim` as of **November 7, 2026**.
- **Historical Audit Scope**: Covers updates from **July 1, 2026** to **November 7, 2026**.
- **Future Audit Rule**: Any future session running an audit must **only** inspect commits introduced **after** the pinned baseline commit hash recorded in this table.

```bash
# Standard protocol for future sessions to inspect updates on any plugin:
git -C ~/.local/share/nvim/lazy/<plugin_dir> fetch origin
git -C ~/.local/share/nvim/lazy/<plugin_dir> log <BASELINE_COMMIT>..origin/HEAD --oneline
```

### Master Plugin Inventory

| Plugin Name | Repository Slug | Baseline Commit | Commit Date | Active Config File | Audit Status (Nov 2026) |
|---|---|---|---|---|---|
| **snacks.nvim** | `folke/snacks.nvim` | `882c996` | 2026-05-25 | [`lua/plugins/snacks-*.lua`](file:///home/georgek/.config/nvim/lua/plugins/snacks-picker.lua) | ✓ Up to date on `main` (Right Panel Slot 1 `󰙅` Explorer) |
| **blink.cmp** | `saghen/blink.cmp` | `78336bc` (`v1.10.2`) | 2026-04-04 | [`lua/plugins/autocompletion.lua`](file:///home/georgek/.config/nvim/lua/plugins/autocompletion.lua) | ⚠️ Pinned to `v1.*`; 259 commits on `main` for v2 (no `v2.0.0` tag yet) |
| **blink-cmp-dictionary** | `Kaiser-Yang/blink-cmp-dictionary` | `898a958` | 2026-06-01 | [`lua/plugins/autocompletion.lua`](file:///home/georgek/.config/nvim/lua/plugins/autocompletion.lua#L44) | ✓ Up to date |
| **LuaSnip** | `L3MON4D3/LuaSnip` | `0abc8f3` | 2026-05-19 | [`lua/plugins/autocompletion.lua`](file:///home/georgek/.config/nvim/lua/plugins/autocompletion.lua#L10) | ✓ Unpinned from `v2.*` and updated to `master` (Neovim 0.12 API fixes) |
| **friendly-snippets** | `rafamadriz/friendly-snippets` | `b2ea5c4` | 2026-10-27 | [`lua/plugins/autocompletion.lua`](file:///home/georgek/.config/nvim/lua/plugins/autocompletion.lua#L18) | ✓ Up to date (Elixir function snippets #591) |
| **lspkind.nvim** | `onsails/lspkind.nvim` | `c7274c4` | 2026-01-29 | [`lua/plugins/autocompletion.lua`](file:///home/georgek/.config/nvim/lua/plugins/autocompletion.lua#L47) | ✓ Up to date |
| **lazydev.nvim** | `folke/lazydev.nvim` | `ff2cbcb` | 2026-03-14 | [`lua/plugins/lsp.lua`](file:///home/georgek/.config/nvim/lua/plugins/lsp.lua#L6) | ✓ Up to date |
| **nvim-lspconfig** | `neovim/nvim-lspconfig` | `d8d2fda` | 2026-10-31 | [`lua/plugins/lsp.lua`](file:///home/georgek/.config/nvim/lua/plugins/lsp.lua#L19) | ✓ Audited; Neovim 0.11+ `root_dir(bufnr, on_dir)` compatible |
| **mason.nvim** | `mason-org/mason.nvim` | `2a6940a` | 2026-06-11 | [`lua/plugins/lsp.lua`](file:///home/georgek/.config/nvim/lua/plugins/lsp.lua#L22) | ✓ Up to date |
| **mason-lspconfig.nvim** | `mason-org/mason-lspconfig.nvim` | `3a5cd6d` | 2026-11-02 | [`lua/plugins/lsp.lua`](file:///home/georgek/.config/nvim/lua/plugins/lsp.lua#L23) | ✓ Up to date (generated server mappings #709-#712) |
| **mason-tool-installer.nvim** | `WhoIsSethDaniel/mason-tool-installer.nvim` | `443f1ef` | 2026-01-22 | [`lua/plugins/lsp.lua`](file:///home/georgek/.config/nvim/lua/plugins/lsp.lua#L24) | ✓ Up to date |
| **fidget.nvim** | `j-hui/fidget.nvim` | `9e02016` | 2026-09-03 | [`lua/plugins/lsp.lua`](file:///home/georgek/.config/nvim/lua/plugins/lsp.lua#L27) | ✓ Up to date |
| **conform.nvim** | `stevearc/conform.nvim` | `016802d` | 2026-08-11 | [`lua/plugins/autoformat.lua`](file:///home/georgek/.config/nvim/lua/plugins/autoformat.lua) | ✓ Standardized on `<leader>cf` |
| **nvim-treesitter** | `nvim-treesitter/nvim-treesitter` | `0195cd6` | 2026-11-02 | [`lua/plugins/treesitter.lua`](file:///home/georgek/.config/nvim/lua/plugins/treesitter.lua#L3) | ✓ Modernized to `main` branch; updated sql/markdown/vimdoc/jinja queries |
| **nvim-treesitter-textobjects** | `nvim-treesitter/nvim-treesitter-textobjects` | `5c7b026` | 2026-09-03 | [`lua/plugins/treesitter.lua`](file:///home/georgek/.config/nvim/lua/plugins/treesitter.lua#L19) | ✓ Dedicated exclusively to jump motions |
| **mini.ai** | `echasnovski/mini.ai` | `a4f5648` | 2026-10-27 | [`lua/plugins/mini-ai.lua`](file:///home/georgek/.config/nvim/lua/plugins/mini-ai.lua) | ✓ Up to date (Neovim >=0.13 multicursor support) |
| **neocodeium** | `monkoose/neocodeium` | `ab8a3da` (`v1.19.1`) | 2026-06-22 | [`lua/plugins/neocodeium.lua`](file:///home/georgek/.config/nvim/lua/plugins/neocodeium.lua) | ✓ Monkey-patch active; SQL scratchpad & unnamed buffer ghost text enabled |
| **opencode.nvim** | `nickjvandyke/opencode.nvim` | `84eabfb` (`v1.0.2`) | 2026-09-14 | [`lua/plugins/opencode.lua`](file:///home/georgek/.config/nvim/lua/plugins/opencode.lua) | ⚠️ Pinned to `version = '*'` (`v1.0.2`); Right Panel Slot 3 `󰚩` (`38%` width) |
| **gitsigns.nvim** | `lewis6991/gitsigns.nvim` | `1e9d0fb` | 2026-10-29 | [`lua/plugins/gitsigns.lua`](file:///home/georgek/.config/nvim/lua/plugins/gitsigns.lua) | ✓ Up to date (linked worktree pathspecs, debounce recovery, EOF show_deleted) |
| **neogit** | `NeogitOrg/neogit` | `697ad3e` | 2026-10-27 | [`lua/plugins/neogit.lua`](file:///home/georgek/.config/nvim/lua/plugins/neogit.lua) | ✓ Docked in Right Panel Slot 4 `󰊢` (`48%` width, VS Code Source Control workflow) |
| **diffview.nvim** | `sindrets/diffview.nvim` | `4516612` | 2024-06-13 | [`lua/plugins/neogit.lua`](file:///home/georgek/.config/nvim/lua/plugins/neogit.lua#L5) | Stable; `<leader>gd` toggles cleanly |
| **dockyard.nvim** | `emrearmagan/dockyard.nvim` | `422ba43` | 2026-09-18 | [`lua/plugins/dockyard.lua`](file:///home/georgek/.config/nvim/lua/plugins/dockyard.lua) | ✓ Docked in Right Panel Slot 5 `󰡨` (`48%` width, sub-views/logs/files confined) |
| **grug-far.nvim** | `MagicDuck/grug-far.nvim` | `91b7e58` | 2026-10-21 | [`lua/plugins/grug-far.lua`](file:///home/georgek/.config/nvim/lua/plugins/grug-far.lua) | ✓ Docked in Right Panel Slot 6 `󰛔` (`45%` width, `<leader>fs` & `<leader>fW`) |
| **which-key.nvim** | `folke/which-key.nvim` | `3aab214` (`v3.*`) | 2025-10-28 | [`lua/plugins/which-key.lua`](file:///home/georgek/.config/nvim/lua/plugins/which-key.lua) | ✓ Modern v3 spec format verified |
| **lualine.nvim** | `nvim-lualine/lualine.nvim` | `221ce6b` | 2026-05-31 | [`lua/plugins/lualine.lua`](file:///home/georgek/.config/nvim/lua/plugins/lualine.lua) | ✓ Unified 3-zone component in `lualine_c` (4-slot Editor, Bottom Tracker, 6-slot Right Panel) |
| **catppuccin** | `catppuccin/nvim` | `edefef7` | 2026-08-09 | [`lua/plugins/colorscheme.lua`](file:///home/georgek/.config/nvim/lua/plugins/colorscheme.lua) | ✓ Auto-integrations for Snacks/Blink audited |
| **render-markdown.nvim** | `MeanderingProgrammer/render-markdown.nvim` | `8e87953` | 2026-10-10 | [`lua/plugins/markdown.lua`](file:///home/georgek/.config/nvim/lua/plugins/markdown.lua#L3) | ✓ Up to date |
| **mkdnflow.nvim** | `jakewvincent/mkdnflow.nvim` | `272148c` | 2026-07-03 | [`lua/plugins/markdown.lua`](file:///home/georgek/.config/nvim/lua/plugins/markdown.lua#L37) | Retained per user request |
| **nvim-origami** | `chrisgrieser/nvim-origami` | `a137d35` | 2026-08-03 | [`lua/plugins/fold-origami.lua`](file:///home/georgek/.config/nvim/lua/plugins/fold-origami.lua) | ✓ Up to date |
| **persistence.nvim** | `folke/persistence.nvim` | `b20b2a7` | 2025-10-28 | [`lua/plugins/session-manager.lua`](file:///home/georgek/.config/nvim/lua/plugins/session-manager.lua) | ✓ Project-linked sessions, multi-event auto-save (FocusLost, BufWritePost, DirChangedPre) |
| **todo-picker** | `george-tk/todo-picker` | `9e48dc0` | 2026-07-22 | [`lua/plugins/todo.lua`](file:///home/georgek/.config/nvim/lua/plugins/todo.lua) | User custom plugin; added `ToDoLog` & `ToDoBoard` |
| **sqmeow.nvim** | `2giosangmitom/sqmeow.nvim` | `d0bb4a7` | 2026-11-02 | [`lua/plugins/database.lua`](file:///home/georgek/.config/nvim/lua/plugins/database.lua) | ✓ Updated to `d0bb4a7` (Right Panel Slot 2 `󰆼` DBUI Drawer) |
| **lazy.nvim** | `folke/lazy.nvim` | `306a055` | 2025-12-17 | [`init.lua`](file:///home/georgek/.config/nvim/init.lua) | Core plugin manager |
| **plenary.nvim** | `nvim-lua/plenary.nvim` | `74b06c6` | 2026-04-10 | Dependency | Shared Lua library |
| **nui.nvim** | `MunifTanjim/nui.nvim` | `10fc361` | 2026-08-21 | Dependency | UI components for sqmeow & snacks |
| **nvim-web-devicons** | `nvim-tree/nvim-web-devicons` | `ec309a0` | 2026-10-13 | Dependency | Icon glyph definitions |

---

## 2. Configuration Architecture & Overlap Map

```mermaid
flowchart TD
    subgraph UI & Navigation Hub
        SNACKS["folke/snacks.nvim<br/>(Picker, Explorer, Dashboard, Notifier, Terminal, Zen)"]
        WK["folke/which-key.nvim (v3)"]
        LUALINE["nvim-lualine/lualine.nvim"]
        CATP["catppuccin/nvim (Mocha)"]
    end

    subgraph Intelligence & Autocompletion
        BLINK["saghen/blink.cmp (v1.10.2)"]
        LSP["neovim/nvim-lspconfig + Mason"]
        CONFORM["stevearc/conform.nvim"]
        LAZYDEV["folke/lazydev.nvim"]
        AI_COMPLETION["monkoose/neocodeium"]
        AI_PAIR["nickjvandyke/opencode.nvim"]
    end

    subgraph Syntax & Text Manipulation
        TS["nvim-treesitter"]
        TS_OBJ["nvim-treesitter-textobjects"]
        MINI_AI["echasnovski/mini.ai"]
        ORIGAMI["chrisgrieser/nvim-origami"]
    end

    subgraph Git, Docker, Search & Sessions
        NEOGIT["NeogitOrg/neogit<br/>(Right Panel Slot 4 󰊢)"]
        DIFFVIEW["sindrets/diffview.nvim"]
        GITSIGNS["lewis6991/gitsigns.nvim"]
        DOCKYARD["emrearmagan/dockyard.nvim<br/>(Right Panel Slot 5 󰡨)"]
        GRUGFAR["MagicDuck/grug-far.nvim<br/>(Right Panel Slot 6 󰛔)"]
        PERSIST["folke/persistence.nvim"]
    end

    subgraph Database Suite
        SQMEOW["2giosangmitom/sqmeow.nvim<br/>(Rust Engine, Drawer, UI)"]
        BLINK_SQMEOW["sqmeow.completion.blink<br/>(Tree-sitter SQL columns & schemas)"]
        SQL_KW["lua/utils/sql-keywords-blink.lua<br/>(SQL Boilerplate & Keywords)"]
    end

    SNACKS -.->|replaces Telescope/Fzf| BLINK
    TS_OBJ <-.->|overlap on af/if/ac/ic| MINI_AI
    LSP -.->|capabilities| BLINK
    AI_PAIR -.->|terminal embed| SNACKS
```

---

## 3. Detailed Audit Matrix & Redundancy Analysis

### 3.1. Tier 1: Core Daily Drivers

#### 1. `folke/snacks.nvim`
- **Baseline**: `882c996` (May 25, 2026).
- **Recent Upstream Features**:
  - `Snacks.bufdelete`: Added `Snacks.bufdelete.invisible()` to cleanly close buffers not visible in any window without layout jarring.
  - `Snacks.terminal`: Added `focus()` method for toggling and window switching.
  - `Snacks.words`: Built-in auto-highlighting for symbols under cursor (replaces manual `vim.lsp.buf.document_highlight` autocommands).
  - `Snacks.picker.git_diff` & `Snacks.picker.git_log`: Fully integrated with native diff previews.
- **Redundancy & Consolidation Assessment**:
  - **Terminal Integration**: [`lua/plugins/opencode.lua`](file:///home/georgek/.config/nvim/lua/plugins/opencode.lua) already uses `snacks.terminal` effectively to pair with `_G.RightPanel`.
  - **LSP Progress**: The configuration currently runs `j-hui/fidget.nvim`. `snacks.notifier` has built-in LSP progress rendering. If you wish to reduce plugin count, `fidget.nvim` can be retired in favor of `Snacks.notifier`.

#### 2. `saghen/blink.cmp`
- **Baseline**: `78336bc` (`v1.10.2`, April 4, 2026).
- **Upstream Development**: 240 commits ahead on `main` heading toward `v2.0` (with native C/Rust library migrations: `blink.lib.native`).
- **Notable Changes Upstream**:
  - `feat(snippets)!: rework LuaSnip source (#2238)`: Refactored how LuaSnip is integrated.
  - `feat: cmp.is_enabled() replaces config.enabled()`: Function rename for checking completion status.
  - Multi-line ghost text: Added `show_first_line_only` to prevent overlapping with code.
- **Action & Recommendation**:
  > [!IMPORTANT]
  > Keep `version = '1.*'` in [`lua/plugins/autocompletion.lua`](file:///home/georgek/.config/nvim/lua/plugins/autocompletion.lua#L4). Do NOT unpin to `main` until upstream officially tags `v2.0.0` and publishes matching prebuilt fuzzy binaries.

#### 3. `nvim-treesitter/nvim-treesitter`
- **Baseline**: `910fdf6` (`main` branch, September 30, 2026).
- **Architectural Rewrite for Neovim 0.12+**:
  - The plugin underwent a complete rewrite on `main`. The legacy `master` branch is frozen for Neovim 0.10/0.11 and crashes on Neovim 0.12 (`attempt to call method 'range' (a nil value)`) because Neovim 0.12 changed directive arguments to `table<integer, TSNode[]>`.
  - In [`lua/plugins/treesitter.lua`](file:///home/georgek/.config/nvim/lua/plugins/treesitter.lua), the legacy `opts` table and `nvim-treesitter.configs` modules are retired.
  - Highlighting and injections run natively through Neovim 0.12's core Treesitter engine (`vim.treesitter.start()`).
  - Parsers are compiled directly via `tree-sitter-cli` 0.26.9 into `~/.local/share/nvim/site/parser`.

#### 4. `nvim-treesitter-textobjects` vs `mini.ai`
- **Problem / Overlap Identified**:
  - [`lua/plugins/treesitter.lua`](file:///home/georgek/.config/nvim/lua/plugins/treesitter.lua#L36-L47) defines:
    - `af` / `if` (`@function.outer` / `@function.inner`)
    - `ac` / `ic` (`@class.outer` / `@class.inner`)
  - [`lua/plugins/mini-ai.lua`](file:///home/georgek/.config/nvim/lua/plugins/mini-ai.lua#L13-L14) **also** defines:
    - `f` (`ai.gen_spec.treesitter({ a = '@function.outer', i = '@function.inner' })`)
    - `c` (`ai.gen_spec.treesitter({ a = '@class.outer', i = '@class.inner' })`)
  - Both plugins compete for the exact same keystrokes (`vaf`, `dif`, `vac`, `cic`).
- **Action & Recommendation**:
  - `mini.ai` provides superior behavior for text objects (better dot-repeat, visual cursor boundary feedback, next/last motions `vanf`/`valf`).
  - **Recommended change**: Remove manual `select_maps` from [`treesitter.lua`](file:///home/georgek/.config/nvim/lua/plugins/treesitter.lua) and let `mini.ai` handle all text object selections. Keep `nvim-treesitter-textobjects` strictly for jumping/movement keymaps (`]f`, `[f`, `]c`, `[c`, `]a`, `[a`).

#### 5. `stevearc/conform.nvim`
- **Baseline**: `016802d` (August 11, 2026).
- **Configuration Bug Found**:
  - In [`lua/plugins/autoformat.lua`](file:///home/georgek/.config/nvim/lua/plugins/autoformat.lua#L19):
    ```lua
    formatters_by_ft = {
      lua = { 'stylua', 'lua-language-server' },
    }
    ```
  - `'lua-language-server'` is an LSP, not an external formatter recognized by Conform. Running `:ConformInfo` shows an error resolving this binary.
  - Conform already handles LSP formatting cleanly via `lsp_format = 'fallback'`.
- **Recommended Fix**:
  - Change `lua = { 'stylua', 'lua-language-server' }` to `lua = { 'stylua' }`.

#### 6. `nickjvandyke/opencode.nvim`
- **Baseline**: `84eabfb` (`v1.0.2`, September 14, 2026).
- **CLI Stable Version**: `1.19.4` (latest stable tag `v1.19.5` on Oct 28, 2026; `v2.0.x` remains on the beta/pre-release channel).
- **Agent Tracking Rule**:
  - OpenCode CLI v2 (`v2.0.x`) is currently on the pre-release/beta channel, while `nickjvandyke/opencode.nvim` `main` (`d512228`+) already requires `minimum_version = "2.0"` and removed v1 `/tui/*` endpoints.
  - The Neovim plugin in [`lua/plugins/opencode.lua`](file:///home/georgek/.config/nvim/lua/plugins/opencode.lua#L3) remains safely pinned to `version = '*'` (`v1.0.2`), matching stable CLI `1.19.x`.
  - Future audit sessions must check `curl -sL https://api.github.com/repos/anomalyco/opencode/releases/latest` and `opencode --version`: when `anomalyco/opencode` promotes `v2.x` to the official "Latest Stable" release, update the CLI (`opencode upgrade`), remove `version = '*'` in [`lua/plugins/opencode.lua`](file:///home/georgek/.config/nvim/lua/plugins/opencode.lua#L3), and fast-forward `opencode.nvim` to `main`.
- **Local Enhancements & Upstream Issues Filed (`nickjvandyke/opencode.nvim`)**:
  - **[Issue #342](https://github.com/nickjvandyke/opencode.nvim/issues/342)**: Visual selection preservation wrapper (`capture_editor_context` in [`lua/plugins/opencode.lua`](file:///home/georgek/.config/nvim/lua/plugins/opencode.lua#L55-L103)) so auto-starting the server on first use does not drop visual selections.
  - **[Issue #343](https://github.com/nickjvandyke/opencode.nvim/issues/343)** & **[Issue #346](https://github.com/nickjvandyke/opencode.nvim/issues/346)**: Wrapped `opencode.ui.ask.cmp` to advertise `triggerCharacters = { '@', '/' }`, scope `@` completions strictly to `@`-prefixed tokens with `textEdit` ranges, and provide recursive workspace file completions on `./` (`rg --files` / `git ls-files`).
  - **[Issue #344](https://github.com/nickjvandyke/opencode.nvim/issues/344)**: Trimmed trailing whitespace on interactive `ask()` submissions so pressing `<CR>` always submits.
  - **[Issue #345](https://github.com/nickjvandyke/opencode.nvim/issues/345)**: Added `<leader>au` (`Undo AI Prompt`) Snacks picker (`pick_undo_prompt`) to preview and revert `N` prompts back in the active session via `/session/{id}/message` and `/session/{id}/revert`.
  - **Keymap Layout**: `<leader>aa` (`Ask AI`), `<leader>ap` (`AI Panel`), `<leader>as` (`AI Prompts`), `<leader>au` (`Undo AI Prompt`), `<leader>an` (`New AI Session`), `<leader>ac` (`Compact AI Session`), `<leader>ax` (`Stop AI Generation`), `<leader>aU` (`NeoCodeium Auth`).

#### 7. `monkoose/neocodeium`
- **Baseline**: `ab8a3da` (`v1.19.1`, June 22, 2026).
- **Monkey-Patch Status**:
  - The custom patch in [`lua/plugins/neocodeium.lua`](file:///home/georgek/.config/nvim/lua/plugins/neocodeium.lua#L34-L55) (intercepting `neocodeium.doc.get` to construct virtual workspace URIs for scratchpads and DBUI buffers) is **still mandatory**. Upstream has not merged native handling for buffers outside `cwd`. Keep this patch in dotfiles.

---

### 3.2. Tier 2: Right Panel Tools, Search, Navigation & UI

#### 8. `MagicDuck/grug-far.nvim` (Right Panel Slot 6 `󰛔`)
- **Baseline**: `91b7e58` (October 21, 2026).
- **Architecture & Integration** ([`lua/plugins/grug-far.lua`](file:///home/georgek/.config/nvim/lua/plugins/grug-far.lua), [`lua/utils/layout.lua`](file:///home/georgek/.config/nvim/lua/utils/layout.lua#L767-L876)):
  - Docked in **Right Panel Slot 6 (`󰛔`)** at `45%` width (minimum `56` columns) via `instanceName = 'right_panel'` and `windowCreationCommand = 'botright vsplit | setlocal nowinfixbuf'`.
  - **Keybindings**: `<leader>fs` (Search & Replace; seeds visual selection in visual mode), `<leader>fW` (Replace Word Under Cursor), and `<C-6>` / `<C-^>` / `<M-6>` / `<leader>6`.
  - **Explorer-Style Navigation**: In the results list, `l` unfolds a collapsed file fold or previews/opens the match in the Left Code Editor while keeping focus in GrugFar; `h` collapses the file fold; `<CR>` jumps to the file in the Left Editor while keeping GrugFar open; `q` closes the Right Panel.
  - **Self-Healing Instance Lifecycle**: `RightPanel.open_grugfar()` verifies `inst._is_ready == true` and `line_count > 2` before reusing the `'right_panel'` instance, automatically recreating it if a previous open was interrupted mid-initialization.

#### 8b. `emrearmagan/dockyard.nvim` (Right Panel Slot 5 `󰡨`)
- **Baseline**: `422ba43` (September 18, 2026).
- **Architecture & Integration** ([`lua/plugins/dockyard.lua`](file:///home/georgek/.config/nvim/lua/plugins/dockyard.lua), [`lua/utils/layout.lua`](file:///home/georgek/.config/nvim/lua/utils/layout.lua#L715-L765)):
  - Docked in **Right Panel Slot 5 (`󰡨`)** at `48%` width (minimum `60` columns), triggered via `<leader>DD` / `<leader>Dd` or `<C-5>` / `<M-5>` / `<leader>5`.
  - **Confined Sub-Views**: All Dockyard sub-views stay strictly inside the Right Panel:
    - Detail Panel (`p` or `l` on leaf items), Hover Inspect (`K`), and `LogLens` (`L`) open as a bottom split inside the Right Panel column.
    - Log entry detail cards (`l` / `<CR>` / `K` inside `LogLens`) open as a bordered card anchored over the `LogLens` split (preventing 3-way vertical stacking) and return focus to `LogLens` on `q` / `h` / `<Esc>`.
    - Container Filesystem Browser (`f`) swaps in-place inside the Right Panel (`winfixbuf = false`), navigates directories with `l`/`h`, opens container files in the Left Code Editor (`RightPanel.get_editor_win()`), and returns to Containers on `q`.
    - Container Shell (`T`) opens via `Snacks.terminal` in the Bottom Panel.
  - **Async Cursor Guard**: Patched `dockyard.ui.navigation` (`first`, `last`, `down`, `up`) to target `ui_state.win_id` (instead of window `0`), verify `nvim_win_get_buf(win) == ui_state.buf_id`, and clamp line bounds.

#### 8c. `NeogitOrg/neogit` (Right Panel Slot 4 `󰊢`)
- **Baseline**: `697ad3e` (October 27, 2026).
- **Architecture & Integration** ([`lua/plugins/neogit.lua`](file:///home/georgek/.config/nvim/lua/plugins/neogit.lua), [`lua/utils/layout.lua`](file:///home/georgek/.config/nvim/lua/utils/layout.lua#L643-L713)):
  - Docked in **Right Panel Slot 4 (`󰊢`)** at `48%` width (minimum `60` columns) with soft wrapping (`wrap`, `linebreak`, `breakindent`).
  - **VS Code Source Control Workflow**:
    - Pressing `c` in `NeogitStatus` opens the `COMMIT_EDITMSG` editor directly at the **top** of the Right Panel above `NeogitStatus` (auto-prompting to stage all if nothing is staged), while `C` opens the full Commit Options popup.
    - Popups (`P`, `p`, `b`, `L`, `Z`, `C`) reflow their action groups into at most 2 columns and open at the **bottom** of the Right Panel below `NeogitStatus`.
    - Sub-views (`LogView`, `CommitView`, `RefsView`, `StashView`) open in-place (`kind = 'replace'`, `winfixbuf = false`) inside the Right Panel and close synchronously without `:b#` side effects.
    - `l` expands/toggles folds in `NeogitStatus` and opens commits in `LogView`/`RefsView`; `h` collapses folds (climbing to parent file/section if needed); `<CR>` opens files/hunks in the Left Code Editor while keeping Neogit open.

#### 9. `folke/which-key.nvim`
- **Baseline**: `3aab214` (v3 spec).
- **Status**: Perfectly configured in [`lua/plugins/which-key.lua`](file:///home/georgek/.config/nvim/lua/plugins/which-key.lua) using modern grouped specs. No deprecations found.

#### 10. `nvim-lualine/lualine.nvim`
- **Baseline**: `221ce6b` (May 31, 2026).
- **Status**: Integrated with fixed 4-slot buffer ring (`lua/utils/buffer-ring.lua`) and dynamic SQL database indicator. Vacant slots (`···`) are suppressed dynamically to save space on narrow windows, while active buffers display fixed slot badges (`1..4`) corresponding to `<leader>1`..`<leader>4` jump keys.

#### 11. `catppuccin/nvim`
- **Baseline**: `edefef7` (August 9, 2026).
- **Upstream Feature**: Added native `PmenuKind` / `PmenuKindSel` highlights.
- **Evaluation**: Custom highlights in [`lua/plugins/colorscheme.lua`](file:///home/georgek/.config/nvim/lua/plugins/colorscheme.lua) cleanly enforce transparency across Snacks and Blink.

#### 12. `chrisgrieser/nvim-origami`
- **Baseline**: `a137d35` (August 3, 2026).
- **Upstream Fix**: Fixed crash when `gitsignsCount` is evaluated without `mini.diff`. Our config disables foldtext anyway (`foldtext = { enabled = false }`), so it is completely stable.

---

### 3.3. Tier 3: Markdown & Note Taking

#### 13. `MeanderingProgrammer/render-markdown.nvim`
- **Baseline**: `245956d` (October 6, 2026).
- **Recent Upstream Features**:
  - `feat: multiline table cell rendering`: Multi-line markdown table cells now render beautifully with aligned borders.
  - `feat: add support for entirely replacing text with virtual lines`: Cleaner rendering of LaTeX and code blocks.
  - `fix: handle ordered icon tonumber returning nil`: Robust handling for ordered lists.
- **Recommendation**: Up to date and actively maintained.

#### 14. `jakewvincent/mkdnflow.nvim`
- **Baseline**: `272148c` (July 3, 2026).
- **Redundancy Analysis**:
  - In [`lua/plugins/markdown.lua`](file:///home/georgek/.config/nvim/lua/plugins/markdown.lua#L58-L72), **9 out of 11 modules are explicitly disabled** (`bib`, `buffers`, `conceal`, `cursor`, `folds`, `foldtext`, `links`, `paths`, `yaml`, `completion`).
  - Only `tables` and `lists` are active, primarily for `<leader>mt` (create table) and `<leader>mr`/`<leader>mc` (row/column insert).
- **Consolidation Candidate**:
  - Markdown table manipulation can be achieved with lightweight Treesitter-based snippets or simple Neovim table formatters (like `prettier` via Conform).
  - If you want fewer plugins, `mkdnflow.nvim` can be retired by extracting the 5 table manipulation keymaps into a 30-line helper script.

#### 15. `george-tk/todo-picker`
- **Baseline**: `9e48dc0` (July 22, 2026).
- **Recent Features**: Added `ToDoLog` and `ToDoBoard`.
- **Status**: Personal custom tool; keep permanently.

---

### 3.4. Tier 4: Database Suite (`sqmeow.nvim` & Dadbod)

- All database audit findings, upstream PR tracking (PR #49, PR #50, PR #51, PR #57), and cluster connection switching are maintained in [`database_agent.md`](file:///home/georgek/.config/nvim/database_agent.md).

---

## 4. Immediate Recommended Tweaks for User Config

The following micro-fixes have been applied to improve consistency:

### Tweak 1: Clean invalid formatter in `autoformat.lua` [RESOLVED]
In [`lua/plugins/autoformat.lua`](file:///home/georgek/.config/nvim/lua/plugins/autoformat.lua#L19), removed `'lua-language-server'` leaving `'stylua'` as the primary formatter with fallback to LSP.

### Tweak 2: Deduplicate Textobjects between `treesitter.lua` and `mini-ai.lua` [RESOLVED]
Removed redundant selection mappings (`af`, `if`, `ac`, `ic`, `aa`, `ia`) from [`lua/plugins/treesitter.lua`](file:///home/georgek/.config/nvim/lua/plugins/treesitter.lua). `mini.ai` now has exclusive, conflict-free ownership of textobject selections with full dot-repeat and visual range extensions, while `nvim-treesitter-textobjects` focuses purely on movement jumping (`]f`, `[f`, `]c`, `[c`, `]a`, `[a`).

### Tweak 3: Modernized `nvim-treesitter` to `main` Branch [RESOLVED]
Migrated `nvim-treesitter` in [`lua/plugins/treesitter.lua`](file:///home/georgek/.config/nvim/lua/plugins/treesitter.lua) to the upstream `main` branch rewrite designed for Neovim 0.12+. Resolves the Neovim 0.12 `attempt to call method 'range' (a nil value)` crash caused by legacy `master` branch query directives (`query_predicates.lua`). Uses Neovim's native Treesitter highlighter (`vim.treesitter.start()`), native indentexpr, and `tree-sitter-cli` 0.26 parser compilation.

### Tweak 4: Right-Panel Docked Neogit (VS Code Source Control Workflow) [RESOLVED]
Docked `Neogit` in Right Panel Slot 4 (`󰊢`, `48%` width, min 60 cols) in [`lua/plugins/neogit.lua`](file:///home/georgek/.config/nvim/lua/plugins/neogit.lua) and [`lua/utils/layout.lua`](file:///home/georgek/.config/nvim/lua/utils/layout.lua). Configured direct commit on `c` (top split of Right Panel), 2-column reflowed popups (bottom split of Right Panel), in-place `replace` sub-views (`LogView`, `CommitView`, `RefsView`, `StashView`), Explorer-style `l`/`h` fold navigation, and Left Editor file opening on `<CR>`.

### Tweak 5: Right-Panel Docked `dockyard.nvim` (Slot 5) & `grug-far.nvim` (Slot 6) [RESOLVED]
Installed and integrated `emrearmagan/dockyard.nvim` ([`lua/plugins/dockyard.lua`](file:///home/georgek/.config/nvim/lua/plugins/dockyard.lua), Slot 5 `󰡨`, `<leader>DD`/`<leader>Dd`) and `MagicDuck/grug-far.nvim` ([`lua/plugins/grug-far.lua`](file:///home/georgek/.config/nvim/lua/plugins/grug-far.lua), Slot 6 `󰛔`, `<leader>fs`/`<leader>fW`) into the Right Panel with Explorer-style `l`/`h`/`<CR>`/`q` navigation, while keeping `<leader>s` dedicated to Spelling (`<leader>st`, `<leader>ss`, `<leader>sn`, `<leader>sp`).

### Tweak 6: Suppress Vacant Slots in Lualine [RESOLVED]
Updated [`lua/utils/buffer-ring.lua`](file:///home/georgek/.config/nvim/lua/utils/buffer-ring.lua#L560-L565) to suppress vacant slot placeholders (`···`). Empty slots take up zero characters on narrow windows, while occupied slots retain their non-shifting fixed index numbers (`1..4`) for `<leader>1` through `<leader>4` jumps.

### Tweak 7: Layout Permanence Exemption for Floating Windows & Picker Diffs [RESOLVED]
In [`lua/key-mapping.lua`](file:///home/georgek/.config/nvim/lua/key-mapping.lua#L894-L935), updated the `UserLayoutLock` autocommand:
- Exempted `snacks_picker_preview` and `snacks_picker_input` so preview scratch buffers can be swapped freely without `E1513: Cannot switch buffer. 'winfixbuf' is enabled` errors.
- Guarded all floating windows (`cfg.relative ~= ''`) so `winfixbuf`, `winfixwidth`, and `winfixheight` only apply to tiled splits (docked explorers and bottom panes).
- Enabled fully functioning syntax-highlighted diff rendering in `Snacks.picker.undo()`.

### Tweak 8: Curated Lean `<leader>f` Find Suite [RESOLVED]
Streamlined the `<leader>f` keybinding map in [`lua/plugins/snacks-picker.lua`](file:///home/georgek/.config/nvim/lua/plugins/snacks-picker.lua) and [`lua/plugins/which-key.lua`](file:///home/georgek/.config/nvim/lua/plugins/which-key.lua) from 15 binds down to 8 high-utility, 1-letter mnemonic shortcuts:
- `<leader>ff`: `Snacks.picker.files()` (Find Files)
- `<leader>fw`: `Snacks.picker.grep()` (Find Word in Workspace; live prompt in normal mode, auto-seeds visual selection in visual mode)
- `<leader>fu`: `Snacks.picker.undo()` (Visual diff time-travel with `<C-y>`/`<C-S-y>` yanking)
- `<leader>fr`: `Snacks.picker.resume()` (Resume Last Picker)
- `<leader>fp`: `Snacks.picker.pickers()` (All Pickers meta escape hatch)
- `<leader>fn`: `Snacks.picker.notifications()` (Notifications)
- `<leader>fh`: `Snacks.picker.help()` (Help Tags)
- `<leader>fk`: `Snacks.picker.keymaps()` (Keymaps)
- Dropped redundant/colliding binds: `<leader>fc` (config), `<leader>fs` (sessions; removed from `session-manager.lua`), `<leader>fi` (images; removed from `snacks-image.lua` in favor of `<leader>mi`), `<leader>fb` (buffers), `<leader>fl` (lines), `<leader>fg` (workspace grep - unified into `<leader>fw`), `<leader>fd` (diagnostics - handled by `<leader>cD`), and old `<leader>fa` (migrated to `<leader>fp`).

### Tweak 9: Project-Linked Session Persistence & Buffer Parity [RESOLVED]
- Restored last cursor position on file open from ShaDa mark `"` in [`lua/auto-commands.lua`](file:///home/georgek/.config/nvim/lua/auto-commands.lua).
- Enhanced [`lua/plugins/session-manager.lua`](file:///home/georgek/.config/nvim/lua/plugins/session-manager.lua) with comprehensive debounced auto-save on `BufDelete`, `BufWipeout`, `BufReadPost`, `BufWritePost`, `FocusLost`, and `DirChangedPre`.
- Added automatic isolation and cleanup of database preview buffers (`[Preview: ...]`), preventing phantom buffers from ever being written into session files.
- Added `PersistenceLoadPost` autocommand to automatically wipe empty unnamed placeholder buffers left behind after session load.
- Aligned dashboard `r` (Restore Session) and Project selection in [`lua/plugins/snacks-dashboard.lua`](file:///home/georgek/.config/nvim/lua/plugins/snacks-dashboard.lua) and `<leader>d` in [`lua/key-mapping.lua`](file:///home/georgek/.config/nvim/lua/key-mapping.lua) to cleanly evict existing buffers before restoring, guaranteeing 100% identical buffer states regardless of whether entering via `r` or Project selection.

### Tweak 10: Strict 3-Zone Docking Layout & Collapse Prevention [RESOLVED]
Hardened the layout engine in [`lua/key-mapping.lua`](file:///home/georgek/.config/nvim/lua/key-mapping.lua):
- **Center Editor Zone**: Guaranteed never to collapse. Closing the last editor window (`<leader>wq`) safely deletes the buffer via `smart_close` (`enew`), and `WinClosed` prevents sidebars/terminals from ever expanding to 100% full screen.
- **Unified Bottom Zone**: Terminals set to `relative = 'editor'` with `winfixheight = true`. Terminals and SQL query results share a single bottom floor (never stack vertically). Support side-by-side vertical splits in the bottom panel via `BottomPanel.split_terminal()` and `<leader>wv`.
- **Right Panel Zone**: Sidebars dock on the right edge (`wincmd L`).
- **Spatial Navigation**: Context-aware `<C-l>`, `<C-h>`, `<C-j>`, `<C-k>` route seamlessly between vertical editor splits, bottom panel splits, and sidebars without jumping prematurely.

### Tweak 11: OpenCode AI Width Locking & Resizing Permanence [RESOLVED]
- Fixed root cause of OpenCode shrinking to 35 columns on navigation: OpenCode (`snacks_terminal`) was being caught by `ft:match('^snacks_')` in `ensure_right_sidebar_precedence()` and `reset_window_layout()`.
- Differentiated OpenCode from general sidebars; OpenCode now defaults to 38% width (`math.max(45, math.floor(vim.o.columns * 0.38))`) and standard sidebars to 35 columns.
- Added persistent tracking for manual split adjustments made via `<M-h>` / `<M-l>` (`RightPanel.custom_widths`), preventing navigation `<C-h>` or layout recalculations from overriding the user's custom width.

### Tweak 12: Split Width Equalization Across Sidebar Lifecycles [RESOLVED]
- Solved asymmetry where closing the right sidebar caused the rightmost window (Terminal 2 or rightmost editor split) to absorb all freed columns while the leftmost split remained small.
- Implemented `equalize_splits()` in [`lua/key-mapping.lua`](file:///home/georgek/.config/nvim/lua/key-mapping.lua): calculates available width (`vim.o.columns` minus sidebar width) and distributes it equally across all vertical splits in both the editor and bottom zones.
- Bound to `ensure_right_sidebar_precedence()`, `RightPanel.close_all()`, `WinClosed`, and `VimResized` autocommands, ensuring splits stay equally wide when sidebars open, close, or resize.
- Added custom split ratio tracking in `smart_resize_width`: if the user explicitly alters split widths with `<M-h>` / `<M-l>`, their custom proportion is preserved across sidebar toggles; otherwise, splits remain strictly equal.
- Standardized `<C-w>=` to clear custom ratios and restore equal geometry without executing destructive global `wincmd =` calls that corrupt Snacks picker layout boxes.

### Tweak 13: Universal Slot Navigation via Leader & Alt Numbers [RESOLVED]
- Mapped `<leader>1` through `<leader>4` and `<M-1>` through `<M-4>` directly to `smart_goto_slot(i)` in [`lua/key-mapping.lua`](file:///home/georgek/.config/nvim/lua/key-mapping.lua).
- Retired legacy `buffer-ring.jump(i)` from [`lua/plugins/lualine.lua`](file:///home/georgek/.config/nvim/lua/plugins/lualine.lua), guaranteeing `<leader>1`..`<leader>4` uses full context routing (jumps or creates filetype buffers in editor, switches/creates terminal instances in terminal, returns from sidebars).
- Added `<M-1>` through `<M-4>` (`Alt+1`..`Alt+4`) across all modes (`{'n', 't', 'i'}`) to allow direct 1-touch switching in terminal insert mode and WSL environments where Windows Terminal intercepts or does not encode Ctrl+Number.
- Guarded `smart_close()` to dismiss floating windows cleanly on `<C-q>` and `<leader>q`.

### Tweak 14: Unified 3-Zone Lualine Component & Macro Recording Indicator [RESOLVED]
- Unified `lualine_c` in [`lua/plugins/lualine.lua`](file:///home/georgek/.config/nvim/lua/plugins/lualine.lua) into a single focus-aware component (`get_focused_zone()`) and emptied `lualine_x`:
  - **Editor (`zone == 'editor'`)**: 4-slot Buffer Ring ([`lua/utils/buffer-ring.lua`](file:///home/georgek/.config/nvim/lua/utils/buffer-ring.lua)) with per-buffer filetype icons (`nvim-web-devicons` / `󰆼` for SQL) and schema-stripped preview/alter/routine labels (`order_items`).
  - **Bottom Panel (`zone == 'bottom'`)**: Bottom Panel Tracker ([`lua/utils/terminal-tracker.lua`](file:///home/georgek/.config/nvim/lua/utils/terminal-tracker.lua)) displaying Terminals (` `), explicitly opened SQL Results (`󰆼 <table_name>`), and Quickfix (`󰁨 <source> (<count>)`) in visual left-to-right opening order, with `/proc/<pid>/stat` foreground job detection (``, `TerminalTrackerRunning`) and `<C-1..4>` / `<M-1..4>` / `<leader>1..4` slot switching.
  - **Right Sidebar (`zone == 'right'`)**: Persistent 6-icon Right Panel Dock ([`lua/utils/layout.lua`](file:///home/georgek/.config/nvim/lua/utils/layout.lua)) showing ` 󰙅  |  󰆼  |  󰚩  |  󰊢  |  󰡨  |  󰛔 ` in fixed slots `1..6` (every segment is 5 visual cells wide with the icon centered at cell 3).
- Added 0ms-latency macro recording indicator (`● @<reg>` in bold Catppuccin Red `#f38ba9`) in `lualine_y` via `RecordingEnter`/`RecordingLeave`, taking priority over database connection and filetype.
- Enabled `sqmeow.nvim` native `opts.ui.winbar = false` and `winfixbuf` locking (`7a6d1fd`), retiring ~45 lines of custom winbar-stripping and window-locking workarounds from [`lua/plugins/database.lua`](file:///home/georgek/.config/nvim/lua/plugins/database.lua) and [`lua/utils/database.lua`](file:///home/georgek/.config/nvim/lua/utils/database.lua).

### Tweak 15: 6-Slot Right Panel Architecture & Layout Stability Hardening [RESOLVED]
- Expanded the Right Panel in [`lua/utils/layout.lua`](file:///home/georgek/.config/nvim/lua/utils/layout.lua) and [`lua/key-mapping.lua`](file:///home/georgek/.config/nvim/lua/key-mapping.lua) to 6 slots (`<C-1..6>`, `<M-1..6>`, `<leader>1..6`, plus `<C-@>` and `<C-^>` terminal fallbacks; `<C-5>`/`<C-6>` open Slots 5/6 directly from the Editor while `1..4` manage the 4-slot Buffer Ring in the Editor).
- **Zero `E1513: 'winfixbuf' is enabled` Guarantee**: Enforced `winfixbuf = false`, `winfixwidth = false`, and `winfixheight = false` on all Editor windows (`info.is_editor`) across `WinEnter`, `BufWinEnter`, `FileType`, and `WinClosed`, and disabled `winfixbuf` on `Neogit`, `Dockyard`, and `GrugFar` windows so in-place buffer swaps (`NeogitLogView`, `dockyard-files`, `grug-far`) never fail.
- **Stacked Right Panel Precedence**: Preserved vertical stacks inside the Right Panel (`Neogit` + `Commit Editor`/`Popup`, `Dockyard` + `LogLens`/`Detail Panel`) during `ensure_right_sidebar_precedence()`, `reset_window_layout()`, and `BottomPanel.open_qf()` (`belowright copen` relative to the Left Editor).
- **Mode & Async Safety**: Synchronous Neogit window closing (avoiding delayed `safe_win_close` `:b#` corruption), clamped `ui_state.win_id` cursor updates in Dockyard, self-healing GrugFar instance re-creation, and automatic `stopinsert` when switching slots or navigating from Insert/Terminal mode.

---

## 5. Future Maintenance Runbook (Next Sessions)

When launching future audit sessions:
1. Open this file (`agent.md`) and [`database_agent.md`](file:///home/georgek/.config/nvim/database_agent.md).
2. Run the update check script against the pinned commits:
   ```bash
   python3 -c "
   import json, os, subprocess
   with open('/home/georgek/.config/nvim/lazy-lock.json') as f: lock = json.load(f)
   base = os.path.expanduser('~/.local/share/nvim/lazy')
   for name, info in lock.items():
       p = os.path.join(base, name)
       if os.path.isdir(p):
           subprocess.run(['git', '-C', p, 'fetch', '--quiet', 'origin'])
           behind = subprocess.check_output(['git', '-C', p, 'rev-list', '--count', f\"{info['commit']}..origin/{info.get('branch','main')}\"], text=True).strip()
           if int(behind) > 0:
               print(f'⚡ {name}: {behind} new commits since last baseline')
   "
   ```
3. Read the git log (`git -C ~/.local/share/nvim/lazy/<plugin> log <BASELINE>..origin/<branch> --oneline`) and inspect diffs for any plugin reporting new commits since its logged baseline.
4. **Mandatory Pin / Unpin Evaluation (Run on Every Audit)**:
   - List all currently pinned plugins in the config:
     ```bash
     grep -rn "version\s*=" /home/georgek/.config/nvim/lua/plugins/
     ```
   - **When to UNPIN or advance a pinned plugin**:
     - **`saghen/blink.cmp` (`version = '1.*'`)**: Check `git -C ~/.local/share/nvim/lazy/blink.cmp tag --sort=-v:refname | head -n 5` and `origin/main:README.md`. Unpin or bump to `version = '2.*'` only when upstream tags a stable `v2.0.0` release with prebuilt fuzzy binaries and external sources (`sqmeow.completion.blink`, `blink-cmp-dictionary`) are compatible.
     - **`nickjvandyke/opencode.nvim` (`version = '*'`)**: Check `opencode --version` and `curl -sL https://api.github.com/repos/anomalyco/opencode/releases/latest`. Unpin (`remove version = '*'`) once `anomalyco/opencode` promotes `v2.x` to the official latest stable release and the local `opencode` CLI is upgraded to `2.x`.
     - **Stale SemVer tags (e.g., `LuaSnip`)**: If a plugin is pinned to `version = '...'` but upstream stops tagging releases while pushing Neovim compatibility fixes to `main`/`master`, remove the `version` constraint so Neovim 0.12+ fixes are not blocked.
   - **When to NEWLY PIN a plugin**:
     - If an unpinned plugin begins an unstable major rewrite on `main`/`master` that requires unreleased external binaries, breaks Neovim 0.12, or adds mandatory external dependencies, pin it to its last stable release tag (`version = '...'` or `commit = '...'`) and document the unpin criteria in Section 3.
5. **External Binary Sync**: If `sqmeow.nvim` updates its release version in `lua/sqmeow/rpc/client.lua`, run `nvim --headless -c 'lua require("sqmeow").install()' -c 'qa!'` so the managed `sqmeow-core` binary matches the Lua RPC client version.
6. Record breaking changes, redundancy opportunities, or new features in Section 3 of this document (and [`database_agent.md`](file:///home/georgek/.config/nvim/database_agent.md) for `sqmeow.nvim`).
7. Update the Baseline Commit hash in Section 1 once reviewed and verified.
