# Database Agent Guide: `sqmeow.nvim` Upstream Audit & Maintenance

This document serves as the single source of truth for managing our integration with [`2giosangmitom/sqmeow.nvim`](https://github.com/2giosangmitom/sqmeow.nvim). Use this guide in future sessions to compare our local overrides against the latest upstream repository, detect if upstream updates have made our patches redundant, and cleanly transition toward standard upstream code.

---

## 1. Upstream Baseline Reference

- **Upstream Repository**: [https://github.com/2giosangmitom/sqmeow.nvim.git](https://github.com/2giosangmitom/sqmeow.nvim.git)
- **Local Clone Location**: `/home/georgek/.local/share/nvim/lazy/sqmeow.nvim`
- **Baseline Commit Pinned**: `0c2db40` (`chore(master): release 3.0.0 (#73)`, tag `v3.0.0`, Fri Oct 9 2026)

### How New Sessions Must Audit Upstream
When starting a new session to inspect updates, run:
```bash
# Fetch latest commits without modifying working tree
git -C ~/.local/share/nvim/lazy/sqmeow.nvim fetch origin --tags

# Check commits introduced since our baseline
git -C ~/.local/share/nvim/lazy/sqmeow.nvim log 0c2db40..origin/master --oneline

# Inspect diffs across specific modules (api, drawer, result, table, view)
git -C ~/.local/share/nvim/lazy/sqmeow.nvim diff 0c2db40..origin/master -- lua/sqmeow/api.lua lua/sqmeow/ui/drawer.lua lua/sqmeow/ui/result.lua lua/sqmeow/ui/table.lua
```

---



## 2. Classification of Local Modifications

We separate our code into two distinct buckets:
1. **Upstream Deficiencies & Bug Fixes**: Architectural problems or missing core features in `sqmeow.nvim`. These should be submitted to the upstream maintainer and removed from our config once merged.
2. **Personal Preferences & Workflow Integrations**: Custom keybindings, Snacks UI integration, Dadbod AST parsing for `blink.cmp`, window dimensions, and persistence paths. These belong in our user configuration permanently.

```mermaid
flowchart TD
    subgraph Resolved Upstream [Merged into Upstream master]
        A["Connection Deduplication (PR #36 / Issue #31)"]
        C["Column Navigation Keymaps (PR #38 / Issue #33)"]
        I["Native Right-Side Drawer Placement (PR #39 / Issue #34)"]
        D["Sticky Column Headers & Dynamic Winbar Indicator (PR #44 / Issue #35)"]
        J["Cluster Child Connection Use on Descendants (PR #48 / Issue #45)"]
        K["In-Memory Relation Preview in Editor (PR #49 / Issue #46)"]
        L["Buffer Re-binding on Drawer 'use' (u) (PR #50 / Issue #47)"]
        B["Drawer Node Scope Separation & Scratchpad Grouping (PR #51 / Issue #32)"]
        N["Preview Buffer Listedness (Issue #59 / Commit 66a8a49)"]
        O["Distinct Preview Buffers & Data Safety (PR #62 / Issue #60)"]
        P["Respect page_size in Drawer Preview (PR #64 / Issue #63)"]
        Q["v3: Vectorized Retained Views with Polars (2c1f30e / 0bd5891)"]
        R["v3: Retained Snapshot Aggregations (gG) (b66fb37)"]
        S["v3: Foreign Key Relationships Browser (gR) (738aab0)"]
        T["v3: Parameterized Scratchpads (:param / -- @param) (1cf3a2a / 27082d1)"]
        U["v3: Distinct preview (grid) vs preview_editor (buffer) Actions"]
    end

    subgraph User Config Integrations [Retain in ~/.config/nvim]
        E["Snacks.picker integration for Saved Queries"]
        F["Native sqmeow blink source + standalone SQL keywords (sql-keywords-blink.lua)"]
        G["BottomPanel / RightPanel layout docking and coordinator"]
        H["Per-database directory structure: scratch/{db_name}/*.sql"]
        M["Two-Step Connection Switcher (<leader>bs)"]
        V["Drawer Keymap Swap: 'p' for preview_editor, 'P' for grid preview"]
    end
```

---

## 3. Detailed Audit Matrix

| Feature / Fix | Local Implementation | Root Cause / Reason | Upstream Status & Redundancy Criteria |
|---|---|---|---|
| **1. Connection Reuse** | [`M.ensure_sqmeow_connection`](file:///home/georgek/.config/nvim/lua/plugins/database.lua#L204) (direct `api.connect_named` call) | `sqmeow.api.connect_named(name)` previously generated duplicate connections unconditionally. | **RESOLVED & MERGED UPSTREAM ([PR #36](https://github.com/2giosangmitom/sqmeow.nvim/pull/36))**. Merged into master in commit `a6e0f8c`. Local deduplication workarounds retired from config. |
| **2. Per-DB Saved Queries & Scratchpad Grouping** | Upstream native folder grouping & `scratchpad_group` | In `drawer.lua`, `toggle()` matched `node.kind == 'scratchpads'` and toggled the global `SCRATCHPADS` container. Nodes under a connection also lacked native grouping. | **RESOLVED & MERGED UPSTREAM ([PR #51](https://github.com/2giosangmitom/sqmeow.nvim/pull/51) / [Issue #32](https://github.com/2giosangmitom/sqmeow.nvim/issues/32))**. Merged into master in commit `90a4212`. Upstream fixed the identity check (`node.id == SCRATCHPADS`), added native folder scanning (`editor.folders()`), and renders expandable folder trees in the drawer with folder-level operations (creation, rename, move, delete). Redundant `editor.list` monkey-patch retired from config. |
| **3. Result Column Navigation** | Native `<Tab>`, `<S-Tab>`, `]c`, `[c` built-ins | `sqmeow/keymap.lua` previously had zero column navigation keymaps in `result`. | **RESOLVED & MERGED UPSTREAM ([PR #38](https://github.com/2giosangmitom/sqmeow.nvim/pull/38))**. Merged into master in commit `c6197ec`. Upstream now natively binds `<Tab>`, `<S-Tab>`, `]c`, and `[c` to `next_column` and `prev_column`. Local keymap overrides removed. |
| **4. Sticky Column Headers & Dynamic Winbar** | `opts.ui.result.sticky_header = true` & `opts.ui.result.winbar_column_info = true` | Result grids with >15 rows lose headers when scrolled down. Users lose context of which column holds which values. | **RESOLVED & MERGED UPSTREAM ([PR #44](https://github.com/2giosangmitom/sqmeow.nvim/pull/44))**. Merged into master in commit `e2a9d5e` (plus fixes in `bcdd2a5` and `7787aec`). Native sticky headers and active column info in winbar are enabled by default. Local float hooks and manual winbar generation retired from config. |
| **5. Right-Side Drawer Placement** | `opts.ui.drawer.position = 'right'` | `sqmeow.ui.drawer.open` previously hardcoded `topleft vertical %dsplit`. | **RESOLVED & MERGED UPSTREAM ([PR #39](https://github.com/2giosangmitom/sqmeow.nvim/pull/39))**. Merged into master in commit `97ed6ab`. Upstream natively uses `botright vertical %dsplit` when `position = 'right'`. All `wincmd L` and scheduled resize hacks removed. |
| **6. SQL Autocompletion** | [`sqmeow.completion.blink`](file:///home/georgek/.local/share/nvim/lazy/sqmeow.nvim/lua/sqmeow/completion/blink.lua) & [`lua/utils/sql-keywords-blink.lua`](file:///home/georgek/.config/nvim/lua/utils/sql-keywords-blink.lua) | Previously relied on `vim-dadbod-completion` and custom AST parsing. | **RESOLVED & MERGED UPSTREAM ([Issue #41](https://github.com/2giosangmitom/sqmeow.nvim/issues/41) / Commit `01cf139`)**. Upstream now natively provides Tree-sitter query-aware database metadata completion for `blink.cmp` and `nvim-cmp`. All Dadbod plugins and wrappers completely removed; fast standalone `sql-keywords-blink.lua` provides boilerplate keywords and phrases. |
| **7. Multi-Sidebar Coordination** | [`_G.RightPanel`](file:///home/georgek/.config/nvim/lua/plugins/database.lua#L386) & [`_G.BottomPanel`](file:///home/georgek/.config/nvim/lua/plugins/database.lua#L1474) | Mutual exclusivity between Snacks Explorer, OpenCode, and Database Drawer. | **User Configuration Only**. Keep permanently in personal dotfiles. |
| **8. Multi-DB Cluster Child Connections** | Upstream native `drawer.actions.use` | Expanding a database node previously did not allow pressing `u` on descendant nodes to select that child connection. | **RESOLVED & MERGED UPSTREAM ([Issue #45](https://github.com/2giosangmitom/sqmeow.nvim/issues/45) / [PR #48](https://github.com/2giosangmitom/sqmeow.nvim/pull/48))**. Merged into master in commit `c78005a`. Upstream now resolves the owning connection ID when `u` is pressed on any database or descendant row (schemas, tables, views) and switches connection with notification. Local hook retired. |
| **9. In-Memory Relation Preview in Editor** | Upstream `drawer.actions.preview_editor` (mapped to `p`) | Dedicated in-memory buffer (`buftype = 'nofile'`) reuses slot `[Preview: <name>]` with zero disk clutter until explicit `:w`. Multi-dialect support without trailing semicolons on redis/json. | **RESOLVED & REFINED IN V3 ([Commit `85f9dcd`](https://github.com/2giosangmitom/sqmeow.nvim/commit/85f9dcdcfb6aa6d50702f54628e2441078af9bf5))**. In v3, upstream cleanly split preview into `actions.preview` (grid peek) and `actions.preview_editor` (editor buffer). Local config maps `p` to `actions.preview_editor` and `P` to `actions.preview`. Light wrapper retains `:w` save hook. |
| **10. Editor Buffer Re-binding on `use` (`u`)** | Upstream native `drawer.actions.use` & `editor.rebind` | Switching connections in the drawer previously left open editor buffers bound to their old connection, causing queries to hit the previous database. | **RESOLVED & MERGED UPSTREAM ([Issue #47](https://github.com/2giosangmitom/sqmeow.nvim/issues/47) / [PR #50](https://github.com/2giosangmitom/sqmeow.nvim/pull/50))**. Merged into master in commit `a299288`. Upstream natively inspects visible editor windows and re-binds them via `editor.rebind(ed_buf, conn.name)`. Local rebind search retired; winbar automatically updates. |
| **11. Multi-DB Connection Switching & Two-Step Picker** | [`M.select_connection`](file:///home/georgek/.config/nvim/lua/plugins/database.lua#L900) & [`M.fetch_connection_databases`](file:///home/georgek/.config/nvim/lua/plugins/database.lua#L778) | Switching to a multi-db cluster connection via picker previously bound the cluster root without a selected database, causing queries to fail. | **RESOLVED & MERGED UPSTREAM ([Issue #52](https://github.com/2giosangmitom/sqmeow.nvim/issues/52) / [PR #57](https://github.com/2giosangmitom/sqmeow.nvim/pull/57))**. Merged into master in commit `74ae98e`. Single-DB connections display as `conn / db` and bind immediately; multi-DB connections prompt for database selection and bind `<conn>/<db>`. Native `api.databases` and `drawer.databases` helpers adopted in config; manual RPC introspection and debug hacks retired. |
| **12. Relation Preview Buffer Listedness (`buflisted`)** | Upstream `ui.drawer.preview_in_editor` | Preview buffer was created unlisted (`buflisted = false`), causing it to vanish from bufferlines (lualine) when switching away and preventing `:bnext`/`:bprev` cycling. | **RESOLVED & MERGED UPSTREAM ([Issue #59](https://github.com/2giosangmitom/sqmeow.nvim/issues/59))**. Merged into master in commit `66a8a49`. Upstream natively creates preview buffers with `nvim_create_buf(true, true)`. Redundant `buflisted = true` workaround retired from `database.lua`. |
| **13. Distinct Relation Preview Buffers & Data Loss Prevention** | Upstream native `drawer.actions.preview` | Upstream cached a single module-level `preview_buf` upvalue, causing subsequent previews of any table to wipe out and overwrite existing preview buffers (including unsaved edits). Users could not compare relations side-by-side or keep query iterations across tables. | **RESOLVED & MERGED UPSTREAM ([PR #62](https://github.com/2giosangmitom/sqmeow.nvim/pull/62) / [Issue #60](https://github.com/2giosangmitom/sqmeow.nvim/issues/60))**. Merged into master in commit `e08832b`. Upstream natively manages `preview_bufs` map per relation and avoids overwriting modified queries (with automatic disambiguation `(1)`, `(2)`, etc.). Local monkey-patches (`debug.setupvalue`, manual buffer name loop) retired completely from config; light wrapper only retains personal `:w` save hook and buffer-ring slot registration. |
| **14. Respect `ui.result.page_size` in Drawer Preview** | Upstream native `drawer.actions.preview` | Preview query previously hardcoded `LIMIT 100` instead of respecting configured `opts.ui.result.page_size`. | **RESOLVED & MERGED UPSTREAM ([PR #64](https://github.com/2giosangmitom/sqmeow.nvim/pull/64) / [Issue #63](https://github.com/2giosangmitom/sqmeow.nvim/issues/63))**. Merged into master in commit `c620d23`. Upstream natively reads `opts.ui.result.page_size` and passes it as the preview limit across all dialects. |
| **15. Vectorized Retained Views with Polars** | Native v3 Rust core engine | Custom ad-hoc evaluator lacked comprehensive SQL syntax and was slow on large result sets. | **RESOLVED UPSTREAM (v3.0.0, commits `2c1f30e`, `0bd5891`)**. All filtering and sorting evaluate locally in Rust with Polars SQL across all relational and NoSQL dialects. |
| **16. Snapshot Aggregation (`gG`)** | Upstream `keymaps.result` (`gG`) & `api.view.aggregate` | No way to group and aggregate query results without issuing new queries to the server. | **RESOLVED UPSTREAM (v3.0.0, commit `b66fb37`)**. Dedicated `GROUP BY`, `AGGREGATE`, `HAVING` interactive bar powered by Polars. |
| **17. Foreign Key Relationships Browser (`gR`)** | Upstream `keymaps.drawer` / `keymaps.result` (`gR`) | Discovering table relationships required complex metadata queries. | **RESOLVED UPSTREAM (v3.0.0, commit `738aab0`)**. Built-in relationship modal with Belongs to / Referenced by inspection and `<CR>` navigation. |
| **18. Parameterized Scratchpads (`:param` / `-- @param`)** | Upstream `api.query` and engine | Scratchpads had no clean parameter prompt or driver-level binding. | **RESOLVED UPSTREAM (v3.0.0, commits `1cf3a2a`, `27082d1`)**. Header comments declare types/defaults; query execution prompts for missing parameters across all adapters. |



---

## 4. Copy-Pasteable GitHub Issues for Upstream (`sqmeow.nvim`)

Copy and paste the markdown blocks below directly into new issues on [https://github.com/2giosangmitom/sqmeow.nvim/issues](https://github.com/2giosangmitom/sqmeow.nvim/issues).

---

### Issue 1: `api.connect_named(name)` unconditionally opens duplicate connections

**Title**: `bug(api): connect_named unconditionally creates duplicate connection sessions when connection is already open`

**Description**:
Calling `require('sqmeow.api').connect_named(name)` when a connection named `name` is already open and connected will unconditionally create a new connection entry with an incremented connection ID and re-register it in `state.connections`.

This causes identical connections (e.g. 4 copies of `test_db`) to accumulate in `sqmeow.state.connections` and appear multiple times in the drawer tree.

**Steps to Reproduce**:
```lua
local api = require('sqmeow.api')
local state = require('sqmeow.state')

-- Connect once
local id1 = api.connect_named('test_db')

-- Execute or switch to it again
local id2 = api.connect_named('test_db')
local id3 = api.connect_named('test_db')

print(#state.connection_list()) -- Prints 3 instead of reusing the active connection!
```

**Proposed Fix**:
In `lua/sqmeow/api.lua`, verify whether a connection with that name is already active before calling `M.connect`:

```lua
function M.connect_named(name)
  local state = require('sqmeow.state')
  local existing = state.connection_by_name(name)
  if existing and existing.state ~= 'closed' then
    M.use(existing.id)
    return existing.id
  end

  local spec = require('sqmeow.sources').find(name)
  if not spec then
    local message = ('there is no configured connection named `%s`'):format(name)
    notify(message, vim.log.levels.ERROR)
    return nil, message
  end

  return M.connect(spec.url, { name = spec.name, read_only = spec.read_only, ssh = spec.ssh })
end
```

---

### Issue 2: Drawer toggle handler conflates any node with `kind == 'scratchpads'` with the global container [RESOLVED & MERGED UPSTREAM - Issue #32 / PR #51]

> **Status**: **RESOLVED & MERGED UPSTREAM**. Merged in commit `90a4212` ([PR #51](https://github.com/2giosangmitom/sqmeow.nvim/pull/51) / [Issue #32](https://github.com/2giosangmitom/sqmeow.nvim/issues/32)).

**Title**: `fix(drawer): toggle() checks node.kind == 'scratchpads' instead of node identity, breaking custom tree nodes`

**Description & Upstream Resolution**:
In `lua/sqmeow/ui/drawer.lua`, the `actions.toggle()` method previously checked `node.kind == 'scratchpads'`, conflating any custom child node that shared this kind with the global scratchpad container.

Upstream resolved this in commit `90a4212`:
1. Switched `toggle()` to match on identity: `if node.id == SCRATCHPADS then ...` and `if node.id == HISTORY then ...`.
2. Introduced native folder grouping (`scratchpad_group` node) under the scratchpads section, recursively walking directories (`walk()`, `editor.folders()`, `editor.list()`).
3. Added full folder management (`rename_dir`, `remove_dir`, and prefilled prompt `api.scratchpad(name, default)`).

---

### Issue 3: Missing default keymaps for horizontal column navigation in result table

**Title**: `feat(result): add actions and keymaps to navigate horizontally between columns in the result grid`

**Description**:
`sqmeow.ui.table` already implements `Table:goto_cell(position, win)` with full support for display snapping and cell offsets (e.g. `{ 0, 1 }` for right, `{ 0, -1 }` for left), as well as `Table:goto_column(index, win)`.

However, `sqmeow/keymap.lua` only maps page-level navigation (`L` / `H`) and row detail (`K`), with no default keymaps to navigate horizontally between cells across columns. Users currently have to navigate character-by-character or using word motions inside cell text.

**Proposed Implementation**:
1. In `lua/sqmeow/ui/result.lua`, add `next_column` and `prev_column` actions:
```lua
function M.actions.next_column()
  if tbl then
    local cell = tbl:goto_cell({ 0, 1 }, win)
    if not cell and tbl._ and tbl._.columns and #tbl._.columns > 0 then
      tbl:goto_column(1, win) -- wrap around
    end
  end
end

function M.actions.prev_column()
  if tbl then
    local cell = tbl:goto_cell({ 0, -1 }, win)
    if not cell and tbl._ and tbl._.columns and #tbl._.columns > 0 then
      tbl:goto_column(#tbl._.columns, win) -- wrap around
    end
  end
end
```
2. In `lua/sqmeow/keymap.lua`, expose these actions under `result`:
```lua
{ action = 'next_column', lhs = { '<Tab>', ']c' }, desc = 'Next column' },
{ action = 'prev_column', lhs = { '<S-Tab>', '[c' }, desc = 'Previous column' },
```

---

### Issue 4: Sticky column headers and active column indicator when scrolling long result sets [RESOLVED UPSTREAM - PR #44 / Issue #35]

> **Status**: Resolved & Merged Upstream in [PR #44](https://github.com/2giosangmitom/sqmeow.nvim/pull/44) (Commits `e2a9d5e`, `bcdd2a5`, `7787aec`). Available via `ui.result.sticky_header = true` and `ui.result.winbar_column_info = true`.

**Title**: `feat(result): pin column headers when scrolling vertically & show active column in winbar`

**Description**:
When a query returns dozens or hundreds of rows, scrolling down past line 2 causes the column names and the separator rule (`├───┼───┤`) to scroll off the top of the window. In queries with many columns or wide numeric/text values, it becomes difficult to identify which column a given cell belongs to without scrolling all the way back to the top.

**Proposed Code Implementation**:

#### 1. In `lua/sqmeow/ui/result.lua`:
Add sticky header float state and lifecycle functions:

```lua
local sticky_buf = nil
local sticky_win = nil

local function close_sticky()
  if sticky_win and vim.api.nvim_win_is_valid(sticky_win) then
    pcall(vim.api.nvim_win_close, sticky_win, true)
  end
  sticky_win = nil
  if sticky_buf and vim.api.nvim_buf_is_valid(sticky_buf) then
    pcall(vim.api.nvim_buf_delete, sticky_buf, { force = true })
  end
  sticky_buf = nil
end

local function update_sticky()
  if not (win and utils.shows(win, buf)) then
    close_sticky()
    return
  end

  local line_count = vim.api.nvim_buf_line_count(buf)
  if line_count < HEADER_LINES + 1 then
    close_sticky()
    return
  end

  local w0 = vim.fn.line('w0', win)
  if w0 > HEADER_LINES then
    if not (sticky_buf and vim.api.nvim_buf_is_valid(sticky_buf)) then
      sticky_buf = vim.api.nvim_create_buf(false, true)
      vim.bo[sticky_buf].buftype = 'nofile'
      vim.bo[sticky_buf].bufhidden = 'hide'
      vim.bo[sticky_buf].swapfile = false
    end

    local header_lines = vim.api.nvim_buf_get_lines(buf, 0, HEADER_LINES, false)
    if #header_lines == HEADER_LINES then
      vim.bo[sticky_buf].modifiable = true
      vim.api.nvim_buf_set_lines(sticky_buf, 0, -1, false, header_lines)
      vim.bo[sticky_buf].modifiable = false

      -- Transfer header highlights/extmarks from NAMESPACE
      local hns = vim.api.nvim_create_namespace('sqmeow_sticky')
      vim.api.nvim_buf_clear_namespace(sticky_buf, hns, 0, -1)
      local marks = vim.api.nvim_buf_get_extmarks(buf, NAMESPACE, { 0, 0 }, { HEADER_LINES - 1, -1 }, { details = true })
      for _, m in ipairs(marks) do
        local row, col, details = m[2], m[3], m[4]
        if details and details.hl_group then
          pcall(vim.api.nvim_buf_set_extmark, sticky_buf, hns, row, col, {
            end_col = details.end_col,
            hl_group = details.hl_group,
            priority = details.priority,
          })
        end
      end

      local win_w = vim.api.nvim_win_get_width(win)
      local view = vim.api.nvim_win_call(win, vim.fn.winsaveview)

      if not (sticky_win and vim.api.nvim_win_is_valid(sticky_win)) then
        sticky_win = vim.api.nvim_open_win(sticky_buf, false, {
          relative = 'win',
          win = win,
          row = 0,
          col = 0,
          width = win_w,
          height = HEADER_LINES,
          focusable = false,
          style = 'minimal',
          zindex = 45,
        })
        if sticky_win and vim.api.nvim_win_is_valid(sticky_win) then
          vim.wo[sticky_win].wrap = false
          vim.wo[sticky_win].spell = false
        end
      else
        vim.api.nvim_win_set_config(sticky_win, { width = win_w, height = HEADER_LINES })
      end

      -- Synchronize horizontal scrolling 1:1 with parent window
      if sticky_win and vim.api.nvim_win_is_valid(sticky_win) then
        vim.api.nvim_win_call(sticky_win, function()
          vim.fn.winrestview({ leftcol = view.leftcol, topline = 1 })
        end)
      end
    end
  else
    if sticky_win and vim.api.nvim_win_is_valid(sticky_win) then
      pcall(vim.api.nvim_win_close, sticky_win, true)
      sticky_win = nil
    end
  end
end
```

#### 2. Enhance `M.update_winbar` in `lua/sqmeow/ui/result.lua`:
```lua
function M.update_winbar(summary)
  if not utils.shows(win, buf) or not require('sqmeow.config').get().ui.winbar then
    return
  end

  local state = require('sqmeow.state')
  local connection = summary and summary.conn_id and state.connections[summary.conn_id]
  if not connection and summary and summary.connection then
    connection = { name = summary.connection, dialect = summary.dialect }
  end
  connection = connection or state.current_connection()
  local label = connection and state.label(connection) or 'not connected'

  -- Dynamic active column information
  local col_info = ''
  local cell = M.current_cell()
  if cell and cell.name and cell.name ~= '' then
    local call = summary or state.call
    local total = call and call.columns and #call.columns or 0
    local col_type = call and call.columns and call.columns[cell.column + 1] and call.columns[cell.column + 1].type_name or ''
    col_info = ('  %%#SqmeowSignAdded#󰠵 %s%%*'):format(cell.name)
    if col_type ~= '' then
      col_info = col_info .. (' %%#SqmeowNull#(%s)%%*'):format(col_type)
    end
    if total > 0 then
      col_info = col_info .. (' %%#SqmeowNull#[%d/%d]%%*'):format(cell.column + 1, total)
    end
  end

  vim.wo[win].winbar = ('%%#SqmeowWinbar# %s  %%*%s%s'):format(label, M.describe(summary, true), col_info)
end
```

#### 3. Attach scroll and cursor listeners in `M.open()` / `M.buffer()`:
```lua
-- In M.open() or when creating the result buffer:
local group = vim.api.nvim_create_augroup('SqmeowResultSticky', { clear = true })
vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
  group = group,
  buffer = buf,
  callback = function()
    M.update_winbar(require('sqmeow.state').call)
    update_sticky()
  end,
})
vim.api.nvim_create_autocmd({ 'WinScrolled' }, {
  group = group,
  callback = function()
    if win and vim.api.nvim_get_current_win() == win then
      update_sticky()
    end
  end,
})
vim.api.nvim_create_autocmd({ 'BufLeave', 'BufHidden', 'BufDelete', 'WinClosed' }, {
  group = group,
  buffer = buf,
  callback = close_sticky,
})
```

#### 4. Clean up in `M.close()`:
```lua
function M.close()
  close_sticky()
  -- (existing close logic continues...)
```

#### 5. Config toggle in `lua/sqmeow/config.lua`:
```lua
ui = {
  result = {
    sticky_header = true,      -- pin column header when scrolling down past line 2
    winbar_column_info = true, -- display active column name and type in winbar
  },
}
```

---

### Issue 5: Configurable drawer placement (`position = 'right' | 'left'`) and responsive width support

**Title**: `feat(drawer): allow configuring drawer placement on the right ('position = right') and responsive width`

**Description**:
Currently, `sqmeow.ui.drawer.open()` hardcodes the split command:
```lua
vim.cmd(('topleft vertical %dsplit'):format(config.width))
```
`topleft` forces the drawer window strictly to the far-left side of the screen.

In modern editor setups (such as VSCode, Zed, or Neovim configurations where file trees sit on the left and database/tools panels sit on the right), users cannot configure `sqmeow` to anchor the drawer on the right side.

To achieve right-side placement currently, users must hack around it by hooking `open()` and running `wincmd L` and manually re-applying width. Using Vim's native `botright vertical %dsplit` allows flawless, native right-side placement that works consistently across all screen sizes, aspect ratios, and ultrawide monitors.

**Proposed Implementation**:
1. In `lua/sqmeow/config.lua`, add `position` to `ui.drawer`:
```lua
ui = {
  drawer = {
    position = 'left', -- 'left' | 'right'
    width = 35,
  },
}
```
2. In `lua/sqmeow/ui/drawer.lua` (`M.open()`):
```lua
local split_cmd = config.position == 'right' and 'botright' or 'topleft'
vim.cmd(('%s vertical %dsplit'):format(split_cmd, config.width))
```
*(Bonus: support responsive or percentage widths if `config.width` is a string like `'20%'` or a function `function() return math.min(50, math.floor(vim.o.columns * 0.2)) end`)*.

---

### Issue 6: Cluster child connections fail to activate on expand and 'use' fails on descendant nodes [RESOLVED & MERGED UPSTREAM - Issue #45 / PR #48]

> **Status**: **RESOLVED & MERGED UPSTREAM**. Merged in commit `c78005a` ([PR #48](https://github.com/2giosangmitom/sqmeow.nvim/pull/48)).

**Title**: `bug(drawer): cluster child connections are not activated on expand and 'use' fails on descendant nodes`

**Description & Maintainer Decision**:
In PostgreSQL/MongoDB/SurrealDB clusters (e.g. `postgresql://user:pass@host:5432/` containing databases `db1`, `db2`), expanding a database node in the drawer calls `toggle_database(node)` which calls `connection.connect(...)` for that database child connection.

Per maintainer review on PR #48:
1. **Expanding (`o`) is for exploration**: `toggle_database` does NOT automatically switch `state.current` to child connections. Parent cluster connections remain queryable (fallback DBs like `postgres`, `test`, `default`) and scratchpads do not silently follow child connections on mere exploration.
2. **Explicit `u` (`actions.use`) on database or descendant rows switches connection**: When the user explicitly presses `u` on an open database row or any descendant row (schemas, tables, views), `actions.use()` resolves the owning connection ID and switches to it with a user notification.

**Implementation in PR #48**:
In `lua/sqmeow/ui/drawer.lua`:
```lua
function M.actions.use()
  local node = M.current_node()
  if node and node.kind == 'database' then
    local opened = opened_database(node)
    node = { kind = 'connection', name = node.name, conn_id = opened and opened.id }
  elseif node and node.conn_id then
    local state = require('sqmeow.state')
    local conn = state.connections[node.conn_id]
    node = { kind = 'connection', name = conn and conn.name or node.name, conn_id = node.conn_id }
  end
  if not node or node.kind ~= 'connection' then
    return
  end
  if not node.conn_id then
    return utils.notify(('%s is not open'):format(node.name), vim.log.levels.WARN)
  end

  require('sqmeow.api').use(node.conn_id)
  M.render()
end
```

---

### Issue 7: Preview relation in an in-memory editor buffer for immediate query iteration [RESOLVED & MERGED UPSTREAM - Issue #46 / PR #49]

> **Status**: **RESOLVED & MERGED UPSTREAM**. Merged in commit `403cef1` ([PR #49](https://github.com/2giosangmitom/sqmeow.nvim/pull/49)).

**Title**: `feat(drawer): preview relation in an in-memory editor buffer for immediate query iteration`

**Description**:
Currently, `sqmeow`'s drawer provides two ways to interact with a table or view:
1. `preview` (`p`): Runs `SELECT * FROM relation LIMIT ...` and displays the result in the bottom grid.
2. `yank_select` (`s`): Copies `SELECT * FROM relation LIMIT ...` to the register.

While `preview` (`p`) is great for a quick read-only peek, in exploratory workflows users almost always want to iterate on the query immediately (adding `WHERE`, `JOIN`, `ORDER BY` clauses).

Opening a scratchpad file per previewed table creates unwanted `.sql` files on disk. By using an in-memory dedicated buffer (`buftype = 'nofile'`) named `[Preview: relation]`, browsing 20 tables creates zero junk files on disk. The buffer only persists to disk when the user explicitly saves it with `:w`.

**Proposed Approaches**:
- **Option A (Recommended & Implemented)**: Upgrade the existing `preview` (`p`) action to open the relation's statement directly in an in-memory editor buffer (`buftype = 'nofile'`) in `editing_window()`, while executing into the result grid. Reuses the preview buffer slot across tables and leaves disk untouched until explicit `:w`. Configurable via `ui.drawer.preview_in_editor = true` (default `true`).
  - **Multi-Dialect Support**: Uses `dialect_of(conn_id)` and maps dialect to buffer filetype (`mongodb` -> `'json'`, `surrealdb` -> `'surql'`, `redis` -> `'redis'`, SQL dialects -> `'sql'`). Statements are generated using `preview_statement` (`sql.read_key` for Redis, `sql.select_from` for MongoDB/SurrealDB/Oracle/SQL). Trailing semicolons are only appended for SQL and SurrealQL (`ft == 'sql' or ft == 'surql'`), leaving JSON and Redis command inputs clean of syntax errors.
- **Option B**: Introduce a separate action (e.g. `actions.query_relation` bound to `O` or `P`), keeping `p` strictly as a bottom-grid-only peek.

---

### Issue 8: Re-bind active editor buffer to selected connection on 'use' (u) [RESOLVED & MERGED UPSTREAM - Issue #47 / PR #50]

> **Status**: **RESOLVED & MERGED UPSTREAM**. Merged in commit `a299288` ([PR #50](https://github.com/2giosangmitom/sqmeow.nvim/pull/50)).

**Title**: `feat(drawer): re-bind active editor buffer to selected connection on 'use' (u)`

**Description**:
When a scratchpad or SQL editor buffer is open, it has `vim.b[buf].sqmeow_connection` set to its originating connection name.
When a user switches connections in the drawer by pressing `u` (`actions.use()`), the plugin displays `queries now run on <target>`. However, because `api.target(buf)` prioritizes `b:sqmeow_connection` over `state.current`, queries executed from the open editor buffer continue to run against the previous database!

**Key Advantages**:
1. Seamless cross-environment querying (`dev` $\leftrightarrow$ `staging` $\leftrightarrow$ `prod` $\leftrightarrow$ cluster DBs) with a single keypress.
2. Matches the user expectation set by the notification.
3. Eliminates throwaway scratchpads and manual `:Sqmeow bind` commands.
4. Accurately updates the editor winbar.

**Proposed Implementation**:
1. In `lua/sqmeow/ui/editor.lua`, add `M.rebind(buf, conn_name)` helper to update `b:sqmeow_connection` and call `M.update_winbar()`.
2. In `lua/sqmeow/ui/drawer.lua`, update `M.actions.use()` to detect the active editor buffer in `editing_window()` / current tab and re-bind it with `editor.rebind`.

---

### Issue 9: :Sqmeow use on multi-database cluster selects root without database, causing queries to fail [PR #57 / Issue #52]

> **Status**: **RESOLVED & MERGED UPSTREAM**. Merged in commit `74ae98e` ([PR #57](https://github.com/2giosangmitom/sqmeow.nvim/pull/57) / [Issue #52](https://github.com/2giosangmitom/sqmeow.nvim/issues/52)).

**Title**: `bug(commands): :Sqmeow use on multi-database cluster selects root without database, causing queries to fail`

**Description**:
Currently, `:Sqmeow use` (and the menu it renders via `sqmeow.ui.form.menu`) only lists already-connected connections in `api.connections()`.

When connecting to a cluster connection (e.g. `postgresql://user:pass@host:5432/` where no database is specified in the URL):
1. `:Sqmeow use` only offers the root cluster connection (`docker_cluster`).
2. Selecting the root cluster connection does not bind a child database. Subsequent queries against the cluster fail because the database is unselected.
3. Users currently must manually open the drawer, expand the cluster node, navigate to a child database node, and press `u`.

**Proposed Fix / Enhancement**:
1. If a connection is a cluster connection (has multiple databases or empty database in its URL), selecting it in `:Sqmeow use` or a new `:Sqmeow select` command should query the engine (`schema:nodes` at path `{}`) to list available databases.
2. Present a secondary menu via `vim.ui.select` (or `sqmeow.ui.form.menu`) to choose the database within that cluster.
3. Open and activate the child connection (`<parent>/<database>`) via `api.connect(parent.url, { name = ('%s/%s'):format(parent.name, db), parent = parent.id, database = db })` followed by `api.use(child_id)`.
4. Single-database connections (where URL specifies a database or SQLite/DuckDB) should display as `<conn> / <db>` and bind immediately without a secondary prompt.

---

### Issue 10: Relation preview buffer in editor is unlisted, breaking bufferline persistence and :bnext/bprev cycling [RESOLVED UPSTREAM - Issue #59 / Commit 66a8a49]

> **Status**: **RESOLVED & MERGED UPSTREAM** ([Issue #59](https://github.com/2giosangmitom/sqmeow.nvim/issues/59) / Commit `66a8a49`). Merged into master in commit `66a8a49`. Upstream natively creates relation preview buffers with `nvim_create_buf(true, true)` (`buflisted = true`).

**Title**: `bug(drawer): relation preview buffer in editor is unlisted, breaking bufferline persistence and :bnext/bprev cycling`

**Problem**:

When `ui.drawer.preview_in_editor = true` is enabled, pressing `p` on a relation in the drawer opens the preview query in the main editing window. However, in `lua/sqmeow/ui/drawer.lua`, the buffer is created with `vim.api.nvim_create_buf(false, true)` (`buflisted = false`).

Because it is unlisted:
1. Bufferlines (`lualine`, `bufferline.nvim`) drop the preview buffer as soon as the user switches to any other file.
2. Standard buffer navigation (`:bnext`, `:bprev`) skips the preview buffer.
3. Hitting `<C-^>` to jump to it triggers Vim's automatic `'buflisted'` promotion, making it behave inconsistently before and after `<C-^>`.

**Proposed Fix**:
In `lua/sqmeow/ui/drawer.lua`, create the buffer with `vim.api.nvim_create_buf(true, true)` (or allow a configuration flag `ui.drawer.preview_listed = true`).

**Local Action**: Redundant `vim.bo[buf].buflisted = true` workaround removed from `lua/plugins/database.lua`.


---

### Issue 11: Allow distinct preview buffers per relation and prevent silent data loss on modified queries [RESOLVED UPSTREAM - PR #62 / Issue #60]

> **Status**: **RESOLVED & MERGED UPSTREAM** ([PR #62](https://github.com/2giosangmitom/sqmeow.nvim/pull/62) / [Issue #60](https://github.com/2giosangmitom/sqmeow.nvim/issues/60)). Merged into upstream `master` in commit `e08832b`.

**Title**: `feat(drawer): allow distinct preview buffers per relation and prevent silent data loss on modified queries`

**Problem**:
In `lua/sqmeow/ui/drawer.lua`, previewing a relation via `preview` (`p`) previously reused a singleton module-level variable (`preview_buf`), overwriting modified buffers and losing edits.

**Solution Merged Upstream**:
Upstream now keys preview buffers per relation (`preview_bufs[key]`), preserves modified buffers by allocating indexed names (`[Preview: relation (1)]`), and tracks original query text (`vim.b[buf].sqmeow_preview_statement`) to distinguish modifications.

**Local Action**: Custom monkey-patch (`debug.setupvalue`, manual buffer search, collision-renaming loop) removed from [`lua/plugins/database.lua`](file:///home/georgek/.config/nvim/lua/plugins/database.lua).

---

### Issue 12: Respect result.page_size for drawer preview relation limit [PR #64 / Issue #63]

> **Status**: **RESOLVED & MERGED UPSTREAM** ([PR #64](https://github.com/2giosangmitom/sqmeow.nvim/pull/64) / [Issue #63](https://github.com/2giosangmitom/sqmeow.nvim/issues/63)). Merged into master in commit `c620d23` and released in `v2.5.0` (`962e25a`).

**Title**: `feat(drawer): respect ui.result.page_size for relation preview`

**Problem**:
Previewing a relation from the drawer (`actions.preview()`) previously used `query.max_rows + 1`, generating queries like `LIMIT 100001` or `LIMIT 10001`. On remote or large databases, pulling tens of thousands of rows across the network when simply wanting to inspect sample data caused high latency and performance lag.

**Solution Proposed & Implemented in PR #64**:
Mirroring `actions.yank_select`, updated `actions.preview()` in `lua/sqmeow/ui/drawer.lua` to use `ui.result.page_size` (default `100`):
- Snappy, sub-second previews on large tables and remote/high-latency databases.
- Consistent with `actions.yank_select`, which already uses `ui.result.page_size`.
- If `ui.result.page_size` is disabled or `0`, passes `nil` (fetching all rows).
- Includes unit test coverage in `tests/test_drawer.lua`.

