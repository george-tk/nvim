# Personal Neovim Configuration

A modern, fast, modular Neovim IDE configuration powered by [`lazy.nvim`](https://github.com/folke/lazy.nvim), [`snacks.nvim`](https://github.com/folke/snacks.nvim), [`vim-dadbod-ui`](https://github.com/kristijanhusak/vim-dadbod-ui), [`opencode.nvim`](https://github.com/nickjvandyke/opencode.nvim), [`blink.cmp`](https://github.com/saghen/blink.cmp), and [`nvim-origami`](https://github.com/chrisgrieser/nvim-origami).

---

## 📦 Prerequisites & Installation

### 1. Neovim Installation (>= 0.10.0 Required)

This configuration utilizes Neovim 0.10+ native features (LSP inlay hints, diagnostics structure, `vim.uv`, Treesitter foldexpr, and modern plugin APIs).

| Operating System | Installation Method / Command |
| :--- | :--- |
| **Ubuntu / Debian** | `sudo add-apt-repository ppa:neovim-ppa/unstable -y && sudo apt update && sudo apt install -y neovim`<br>*(Or download the official AppImage below)* |
| **Arch Linux** | `sudo pacman -S neovim` |
| **Fedora** | `sudo dnf install neovim` |
| **macOS (Homebrew)** | `brew install neovim` |
| **Windows (winget)** | `winget install Neovim.Neovim` |
| **Universal Linux (AppImage)** | ```bash<br>curl -LO https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.appimage<br>chmod u+x nvim-linux-x86_64.appimage<br>sudo mv nvim-linux-x86_64.appimage /usr/local/bin/nvim<br>``` |

Verify your Neovim version:
```bash
nvim --version # Must be >= 0.10.0
```

---

### 2. External Dependencies

To enable all features (fuzzy pickers, code completion, Tree-sitter parsers, database tooling, formatters, and AI assistance), install the following tools:

| Tool | Purpose in Configuration |
| :--- | :--- |
| **`git`** | Plugin management via `lazy.nvim`, `neogit`, `diffview`, and `gitsigns` |
| **`make` & `gcc` / `clang`** | C compiler for Treesitter parsers and LuaSnip regex extensions |
| **`ripgrep` (`rg`)** | Fast workspace search & live grep in `snacks.picker` |
| **`fd` / `fd-find`** | Fast file indexing and image search in `snacks.picker` / `snacks.image` |
| **`unzip`, `tar`, `curl`** | Required by `mason.nvim` to download and unpack LSPs and formatters |
| **`nodejs` & `npm` / `pnpm`** | Required for Mason formatters & LSPs (`prettier`, `sql-formatter`, etc.) |
| **`python3` & `pip`** | Python language support and linters |
| **`sqlite3`** | SQLite CLI engine for `vim-dadbod` and local database testing |
| **`opencode` CLI** *(Optional)* | AI coding assistant integration (`opencode.nvim`) |

#### One-Liner Dependency Installation by OS:

- **Ubuntu / Debian:**
  ```bash
  sudo apt update && sudo apt install -y \
    git \
    build-essential \
    ripgrep \
    fd-find \
    unzip \
    curl \
    nodejs \
    npm \
    python3 \
    python3-pip \
    sqlite3

  # Ubuntu packages fd as fdfind; symlink to fd so Neovim/Snacks can discover it:
  mkdir -p ~/.local/bin
  ln -sf $(which fdfind) ~/.local/bin/fd
  ```

- **Arch Linux:**
  ```bash
  sudo pacman -S --needed \
    git \
    base-devel \
    ripgrep \
    fd \
    unzip \
    curl \
    nodejs \
    npm \
    python \
    python-pip \
    sqlite
  ```

- **Fedora:**
  ```bash
  sudo dnf install -y \
    git \
    @development-tools \
    ripgrep \
    fd-find \
    unzip \
    curl \
    nodejs \
    npm \
    python3 \
    python3-pip \
    sqlite
  ```

- **macOS (Homebrew):**
  ```bash
  brew install git ripgrep fd unzip curl node python sqlite
  ```

- **Windows (winget / PowerShell):**
  ```powershell
  winget install Git.Git BurntSushi.ripgrep.MSVC sharkdp.fd OpenJS.NodeJS Python.Python.3 SQLite.SQLite
  ```

#### OpenCode AI CLI Installation (Optional for `<leader>a`):
```bash
curl -fsSL https://opencode.ai/install | bash
```

---

### 3. Nerd Font Installation (Required for UI Icons)

This configuration has `vim.g.have_nerd_font = true` enabled and relies on a [Nerd Font](https://www.nerdfonts.com/) (v3.0+) for:
- File tree icons (`nvim-web-devicons`, Snacks Explorer)
- Statusline glyphs and database indicators in `lualine` (`󰆼`)
- Markdown rendered heading numerals and badges (`render-markdown.nvim`: `󰎤 `, `󰎧 `, `󰎪 `, etc.)
- Database table and drawer node icons in `vim-dadbod-ui` (``, ``)
- LSP diagnostic status signs (` `, ` `, ` `, ` `)
- Blink completion item kind icons

#### Recommended Fonts:
- **JetBrainsMono Nerd Font** *(Recommended)*
- **FiraCode Nerd Font**
- **MesloLGS Nerd Font**
- **Hack Nerd Font**

#### Installation:

- **Ubuntu / Debian:**
  ```bash
  # Ensure fontconfig and curl are installed
  sudo apt install -y fontconfig curl

  # Download and install JetBrainsMono Nerd Font
  mkdir -p ~/.local/share/fonts
  curl -fLO https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.tar.xz
  tar -xf JetBrainsMono.tar.xz -C ~/.local/share/fonts/
  rm JetBrainsMono.tar.xz
  fc-cache -fv
  ```

- **Arch Linux:**
  ```bash
  sudo pacman -S ttf-jetbrains-mono-nerd
  ```

- **Fedora:**
  ```bash
  sudo dnf copr enable che/nerd-fonts
  sudo dnf install -y jetbrains-mono-nerd-fonts
  ```

- **macOS (Homebrew):**
  ```bash
  brew install --cask font-jetbrains-mono-nerd-font
  ```

- **Windows (winget):**
  ```powershell
  winget install --id=DEVCOM.JetBrainsMonoNerdFont
  ```

- **Universal Linux (Manual Download):**
  Download any font archive from [Nerd Fonts Downloads](https://www.nerdfonts.com/font-downloads) or [GitHub Releases](https://github.com/ryanoasis/nerd-fonts/releases), extract `.ttf`/`.otf` files to `~/.local/share/fonts/`, and run `fc-cache -fv`.

> [!IMPORTANT]
> **Configure your Terminal Emulator**: After installing the font, open your terminal settings (Alacritty, Kitty, WezTerm, Ghostty, iTerm2, Windows Terminal, etc.) and set the font to **`JetBrainsMono Nerd Font`** (or your chosen Nerd Font).

---

### 4. Setup & First Launch

#### 1. Backup any existing configuration:
```bash
# Backup Neovim config and cache
mv ~/.config/nvim ~/.config/nvim.backup.$(date +%Y%m%d) 2>/dev/null
mv ~/.local/share/nvim ~/.local/share/nvim.backup.$(date +%Y%m%d) 2>/dev/null
mv ~/.local/state/nvim ~/.local/state/nvim.backup.$(date +%Y%m%d) 2>/dev/null
mv ~/.cache/nvim ~/.cache/nvim.backup.$(date +%Y%m%d) 2>/dev/null
```

#### 2. Clone this repository:
```bash
# Via HTTPS:
git clone https://github.com/george-tk/nvim.git ~/.config/nvim

# Or via SSH:
# git clone git@github.com:george-tk/nvim.git ~/.config/nvim
```

#### 3. Start Neovim:
```bash
nvim
```

On first launch:
1. **[`lazy.nvim`](https://github.com/folke/lazy.nvim)** will automatically clone and install all plugins.
2. **[`mason-tool-installer`](https://github.com/WhoIsSethDaniel/mason-tool-installer.nvim)** will automatically install configured LSPs (`lua_ls`, `marksman`) and formatters (`stylua`, `prettier`, `sql-formatter`).
3. **[`nvim-treesitter`](https://github.com/nvim-treesitter/nvim-treesitter)** will compile syntax parsers.

#### 4. Verify System Health:
Run the built-in health check to confirm all tools and dependencies are properly detected:
```vim
:checkhealth
```

---

## 🎯 Unified Spatial IDE Architecture

```text
┌────────────────────────────────────────────────────────┬──────────────────────────┐
│                                                        │       Right Panel        │
│                      Code Editor                       │         (<C-l>)          │
│                        (Center)                        │                          │
│                                                        │  1. File Explorer (25 w) │
│                                                        │  2. DB Explorer (25 w)   │
├────────────────────────────────────────────────────────┤  3. OpenCode AI (38% w)  │
│            Unified Bottom Output (<C-j>)               │  (Only ONE ever visible) │
│                                                        │                          │
│  1. Persistent Multi-Terminals (<leader>/ / [N]<C-j>)  │  * DB Drawer is never    │
│  2. SQL Query Results Table (<leader>bo / <leader>br)  │    split by queries      │
│  (Strictly Center-Scoped, never splits the right side) │                          │
└────────────────────────────────────────────────────────┴──────────────────────────┘
```

---

## 🧭 Spatial Navigation & Window Management

### 1. Panel Toggling
| Keybinding | Action | Description |
| :--- | :--- | :--- |
| **`<C-l>`** | **Right Panel** | Dynamically toggle active right tool (File Explorer, DBUI, AI) |
| **`<C-j>`** | **Bottom Output** | Dynamically toggle active bottom tool (Terminal, SQL Results) |
| **`<C-h>`** | **Editor Left** | Return directly to Code Editor from any side panel |
| **`<C-k>`** | **Editor Up** | Navigate up from bottom output back into Code Editor |

### 2. Resizing & Layout Reset (`Alt + hjkl` & `<C-w>=`)
| Keybinding | Mode | Action |
| :--- | :--- | :--- |
| **`<M-h>`** | Normal, Insert, Terminal | **Shrink width** by 3 columns |
| **`<M-l>`** | Normal, Insert, Terminal | **Expand width** by 3 columns |
| **`<M-k>`** | Normal, Insert, Terminal | **Expand height** by 2 lines |
| **`<M-j>`** | Normal, Insert, Terminal | **Shrink height** by 2 lines |
| **`<C-w>=`** | Normal | **Reset all windows** to default IDE dimensions |

---

## 📂 Universal Folding & Explorer Controls (`h` / `l`)

```text
┌─────────────────────────┬──────────────────────────────────┬─────────────────────────────────┐
│ Zone                    │ Left / Collapse (h)              │ Right / Expand (l / CR)         │
├─────────────────────────┼──────────────────────────────────┼─────────────────────────────────┤
│ 1. File Explorer        │ Collapse folder / go to parent   │ Expand / Open file              │
│ 2. Database Explorer    │ Collapse table / go to parent    │ Expand / Open table query       │
│ 3. Code Editor Buffer   │ Smart collapse fold (origami)    │ Smart expand fold (origami)     │
└─────────────────────────┴──────────────────────────────────┴─────────────────────────────────┘
```

---

## 📑 Complete Keymap Reference (All Uniform 2-Key, Zero Collisions)

### 🗂️ Buffer & Window Management
| Keybinding | Action | Description |
| :--- | :--- | :--- |
| **`<leader>1` .. `<leader>9`** | Buffer Jump | Switch to buffer 1 through 9 instantly |
| **`<leader><Tab>`** | Next Buffer | Navigate to next open buffer |
| **`<leader><S-Tab>`** | Previous Buffer | Navigate to previous open buffer |
| **`<leader>q`** | Close Buffer | Delete current buffer |
| **`<leader>r`** | Alternate Buffer | Switch to previous alternate buffer |
| **`<leader>d`** | Dashboard | Return to start dashboard |
| **`<leader>z`** | Zen Mode | Toggle distraction-free centered Zen Mode |
| **`<leader>e`** | File Explorer | Open/switch right panel to File Explorer (25 cols) |
| **`<leader>/`** | Terminal | Open/toggle persistent Terminal at bottom |
| **`<leader>=`** | Format Buffer | Run code formatter via Conform |

---

### 🔍 Find & Search (`<leader>f`)
| Keybinding | Action | Description |
| :--- | :--- | :--- |
| **`<leader>fa`** | **All Pickers** | **Meta-picker to search and launch any Snacks picker** |
| **`<leader>fn`** | **Notifications** | **Find & view all notification history** |
| **`<leader>ff`** | Find Files | Search files in workspace |
| **`<leader>fb`** | Open Buffers | Search active buffers |
| **`<leader>fg`** | Word in Workspace | Live grep across entire codebase |
| **`<leader>fl`** | Word in Current Buffer | Fuzzy-find any word on the fly in active buffer |
| **`<leader>fo`** | Word in Open Buffers | Grep across all open buffers |
| **`<leader>fw`** | Word Under Cursor | Instant grep for symbol under cursor |
| **`<leader>fc`** | Neovim Config | Jump to `~/.config/nvim` files |
| **`<leader>fd`** | Diagnostics | Workspace errors, warnings, and lints |
| **`<leader>fr`** | Recent Files | Search recently opened files |
| **`<leader>fp`** | Projects | Project switcher |
| **`<leader>fs`** | Sessions | Saved workspace sessions |
| **`<leader>fi`** | Images | Search images in workspace |
| **`<leader>fh`** | Help Tags | Neovim help documentation |
| **`<leader>fk`** | Keymaps | Search all registered keymaps |

---

### 🗄️ Database Studio (`<leader>b`)
| Keybinding | Action | Description |
| :--- | :--- | :--- |
| **`<leader>bq`** | Query Scratchpad | Open clean, blank SQL buffer connected to active DB |
| **`<leader>br`** | Run Query | Execute statement under cursor, visual block, or file |
| **`<leader>bo`** | Query Output | Show/hide Query Results Table without re-executing |
| **`<leader>bc`** | Switch Database | Fast fuzzy picker to switch environments on the fly |
| **`<leader>ba`** | Add Database | Interactive prompt to add a new connection URL |
| **`<leader>bt`** | Database Explorer | Open Database Explorer drawer on the right panel (25 cols) |
| **`<leader>bs`** | Save Query | Bookmark current query |

---

### 📝 Todo List (`<leader>t`)
| Keybinding | Action | Description |
| :--- | :--- | :--- |
| **`<leader>tt`** | Todo List | Open interactive Todo List |
| **`<leader>tb`** | Todo Board | Open Kanban-style Todo Board |
| **`<leader>tn`** | New Todo | Create new Todo item |
| **`<leader>tr`** | Reference Todo | Add reference to current code location |
| **`<leader>tj`** | Jump to Todo | Jump directly to Todo location |
| **`<leader>tl`** | Todo Log | View completed/archived log |

---

### 🌿 Git Suite (`<leader>g`)
| Keybinding | Action | Description |
| :--- | :--- | :--- |
| **`<leader>gs`** | Status | Neogit status |
| **`<leader>gc`** | Commit | Open commit editor |
| **`<leader>gp`** | Push | Git Push *(lowercase)* |
| **`<leader>gl`** | Pull | Git Pull *(lowercase)* |
| **`<leader>gb`** | Branch | Branch switcher |
| **`<leader>gd`** | Diff | Diffview open |

---

### 📊 Markdown Table Editing (`<leader>m`)
| Keybinding | Action | Description |
| :--- | :--- | :--- |
| **`<leader>mt`** | Create Table | Prompt for table dimensions |
| **`<leader>mr`** | Row Below | Insert row below cursor |
| **`<leader>ma`** | Row Above | Insert row above cursor *(replaces Shift+R)* |
| **`<leader>mc`** | Column Right | Insert column after cursor |
| **`<leader>mb`** | Column Left | Insert column before cursor *(replaces Shift+C)* |
| **`<leader>md`** | Delete Row | Delete current table row |
| **`<leader>mx`** | Delete Column | Delete current table column |
| **`<leader>mu`** | Update Numbering | Renumber ordered lists |
| **`<leader>mi`** | Insert Image | Search image & insert relative markdown link |

---

### 🔤 Spelling (`<leader>s`)
| Keybinding | Action | Description |
| :--- | :--- | :--- |
| **`<leader>st`** | Spelling Toggle | Toggle spell check on/off *(replaces Shift+S)* |
| **`<leader>ss`** | Spelling Suggestions | Open picker suggestions |
| **`<leader>sn`** | Next Spell Error | Jump to next error |
| **`<leader>sp`** | Previous Spell Error | Jump to previous error |

---

### 🤖 OpenCode AI (`<leader>a`)
| Keybinding | Action | Description |
| :--- | :--- | :--- |
| **`<leader>aa`** | Ask AI | Prompt referencing `@this` selection/file |
| **`<leader>as`** | AI Prompts | Prompt menu (`explain`, `fix`, `test`, `review`) |
| **`<leader>at`** | AI Panel | Right sidebar panel toggle (38% width) |
| **`<leader>an`** | New AI Session | Fresh conversation |
| **`<leader>ac`** | Compact AI Session | Compact history to conserve tokens |

---

## License

MIT License. Feel free to use and adapt for your own Neovim workflow!
