# Neovim Cheatsheet

## Essential Keybindings

### File Operations
| Key | Action |
|-----|--------|
| `<leader>ff` | Find files |
| `<leader>fg` | Search text in project |
| `<leader>fr` | Recent files |
| `<leader>e` | Toggle file explorer |
| `<C-s>` | Save file |
| `<leader>q` | Quit |

### Navigation
| Key | Action |
|-----|--------|
| `<C-h/j/k/l>` | Move between windows |
| `<S-h>` | Previous buffer |
| `<S-l>` | Next buffer |
| `gd` | Go to definition |
| `gr` | Show references |
| `gi` / `gt` | Go to implementation / type definition |
| `K` | Show documentation |
| `<C-o>` / `<C-i>` | Jump back / forward in jump history |
| `]q` / `[q` | Next/previous quickfix item |

### Code navigation (Cursor parity)
| Key | Action | Cursor |
|-----|--------|--------|
| `<leader>fs` / `<leader>fS` | Document / workspace symbols | Ctrl+Shift+O / Ctrl+T |
| `<leader>ci` / `<leader>co` | Incoming / outgoing calls | Call Hierarchy |
| `<leader>pd` `pr` `pi` `pt` | Peek definition / references / implementations / type (glance) | Peek |
| `<leader>xx` / `<leader>xX` | Project / buffer diagnostics (trouble) | Problems |
| `<leader>xs` / `<leader>xl` | Symbol outline / LSP locations side panel | Outline |
| `<leader>;` | Pick from the breadcrumb winbar (dropbar) | Breadcrumbs |
| `[x` | Jump to the sticky function/class header (treesitter-context) | Sticky Scroll |
| `[d` / `]d` | Previous / next diagnostic | F8 |

The global `grn`/`grr`/`gra`/`gri`/`grt` defaults are removed so `gr` fires
without waiting `timeoutlen` for a follow-up key.

### Editing
| Key | Action |
|-----|--------|
| `gcc` | Toggle line comment |
| `<leader>ca` | Code actions |
| `<leader>rn` | Rename symbol |
| `<leader>mp` | Format file |
| `<A-j/k>` | Move line down/up |

### Git
| Key | Action |
|-----|--------|
| `<leader>gg` | Open lazygit |
| `<leader>gn` | Neogit (magit-style) |
| `<leader>gd` | Review working tree changes (codediff) |
| `<leader>gs` | Review staged changes (codediff) |
| `<leader>gD` | Review branch changes since the default-branch merge-base (PR scope) |
| `<leader>gf` | Diff current file against HEAD (codediff) |
| `<leader>gl` | Review recent commits one by one (codediff history) |
| `<leader>gL` | Review branch commits one by one (`<default>..HEAD`) |
| `<leader>gc` | Pick a commit, review everything after it through the working tree |
| `<leader>gh` | File history (diffview) |
| `<leader>gx` | Diffview close |
| `<leader>gB` | Blame buffer |
| `]h` / `[h` | Next/previous hunk |
| `<leader>hp` | Preview hunk |
| `<leader>hb` | Blame line (full) |
| `<leader>tb` | Toggle inline blame |

Inline blame (author, relative time, summary) is **on by default** at the end of the current line.

Roles: lazygit stages and pushes, diffview shows file history, codediff reviews.
codediff refreshes live while an agent edits files, and folds unchanged regions.
Inside a codediff tab: `t` inline / side-by-side, `gc` compact, `]c`/`[c` hunk,
`]f`/`[f` file, `-` stage file, `<leader>hs`/`<leader>hr` stage/discard hunk,
`q` close, `g?` all keys. `:CodeDiff pr 512` reviews a PR without checking it out.

### Claude Code
| Key | Action | Mode |
|-----|--------|------|
| `<leader>cc` | Toggle Claude Code | n |
| `<M-c>` | Toggle Claude Code (also from inside the Claude terminal) | n + t |
| `<leader>cf` | Focus Claude Code | n |
| `<leader>cs` | Send selection (visual) | v |
| `<leader>cb` | Add buffer to chat | n |
| `<leader>cda` | Accept Claude diff | n |
| `<leader>cdd` | Deny Claude diff | n |

`<M-c>` is the only one that works while focus is inside the Claude terminal buffer — leader chords don't fire in terminal mode. Use `<leader>cc` from a normal buffer, `<M-c>` from anywhere.

On **macOS**, Option-key combos send special characters by default (Option+c → ç). For `<M-c>` to work, set the terminal's option-as-meta:
- ghostty: `macos-option-as-alt = true` in config
- iTerm2: Profile → Keys → Left/Right Option = "Esc+"
- Terminal.app: Preferences → Profiles → Keyboard → "Use Option as Meta key"

The bridge starts a WebSocket+MCP server (same protocol as the Cursor VS Code extension), so `claude` running in the embedded terminal sees the buffer, selection and diagnostics in real time.

### Text case (parity with `change-case`)
Prefix `gA` (uppercase, so built-in `ga` ASCII inspect is preserved). Examples: `gAu` upper, `gAl` lower, `gAs` snake, `gAc` camel, `gAp` pascal, `gAd` dash (kebab), `gAn` constant.

### Terminal
| Key | Action |
|-----|--------|
| `<C-\>` | Toggle terminal |

## Vim Motions (Quick Reminder)

### Basic Movement
- `h j k l` - Left, Down, Up, Right
- `w` - Next word
- `b` - Previous word
- `e` - End of word
- `0` - Start of line
- `$` - End of line
- `gg` - Top of file
- `G` - Bottom of file
- `{line}G` - Go to line number

### Editing
- `i` - Insert before cursor
- `a` - Insert after cursor
- `I` - Insert at start of line
- `A` - Insert at end of line
- `o` - New line below
- `O` - New line above
- `x` - Delete character
- `dd` - Delete line
- `yy` - Copy line
- `p` - Paste
- `u` - Undo
- `<C-r>` - Redo

### Visual Mode
- `v` - Visual mode
- `V` - Visual line mode
- `<C-v>` - Visual block mode
- Select text then `y` to copy, `d` to delete

### Search & Replace
- `/text` - Search forward
- `?text` - Search backward
- `n` - Next match
- `N` - Previous match
- `:%s/old/new/g` - Replace all in file

## Common Commands

### LSP
```vim
:LspInfo          " Check LSP status
:LspRestart       " Restart LSP server
:Mason            " Open Mason (LSP installer)
```

### Plugins
```vim
:Lazy             " Open plugin manager
:Lazy sync        " Update all plugins
:Lazy clean       " Remove unused plugins
```

### File Explorer (Neo-tree)
- `a` - Add file/directory
- `d` - Delete
- `r` - Rename
- `y` - Copy
- `x` - Cut
- `p` - Paste
- `?` - Show help

### Telescope (in picker)
- `<C-j/k>` - Move up/down
- `<C-q>` - Send to quickfix list
- `<Esc>` - Close picker

## Tips

1. **Use relative line numbers**: `5j` moves 5 lines down
2. **Use `.` to repeat**: After an action, press `.` to repeat it
3. **Use macros**: `qa` starts recording to register `a`, `q` stops, `@a` plays
4. **Use marks**: `ma` sets mark `a`, `'a` jumps to it
5. **Use clipboard**: Visual select + `"+y` to copy to system clipboard

## Browser click-to-source (code-jumper)

`marshallku/code-jumper` registers every nvim running in a tmux or comux pane.
Dev-server inspectors call `$LAUNCH_EDITOR` (set in `.zshrc`), which opens the
file in the nvim whose cwd contains it and focuses that pane (`comux jump` for
comux). A local clone at `~/dev/code-jumper` or `~/workspace/code-jumper` takes
precedence over the lazy.nvim checkout for both the plugin and the launcher.

## Kotlin (kotlin-lsp)

JetBrains' official `kotlin-lsp` (Alpha, IntelliJ-based, bundles its own JBR).
JVM Gradle/Maven projects only; KMP is not supported yet. The config looks for
the server in Mason, then `~/.local/share/kotlin-lsp/kotlin-lsp.sh`, then `PATH`.

Mason's package 404s since JetBrains moved downloads to signed CDN URLs, so
install it manually per machine:

```sh
# macOS
brew install --cask kotlin-lsp

# Linux: standalone archive from https://github.com/Kotlin/kotlin-lsp/releases
# (verify the .sha256 next to it first)
mkdir -p ~/.local/share/kotlin-lsp
tar -xzf kotlin-server-<version>.tar.gz -C ~/.local/share/kotlin-lsp --strip-components=1
```

Formatting uses `ktlint` (installed by Mason).

## Per-project setup: Yarn PnP TypeScript

If a project uses Yarn Berry PnP (`.pnp.cjs` at the root), `vtsls` automatically
points its TypeScript SDK at `<repo>/.yarn/sdks/typescript/lib`. To bootstrap that
SDK once per project:

```sh
yarn add -D @yarnpkg/sdks   # writes to package.json — creates a commit
yarn sdks base              # generates .yarn/sdks/typescript/...
```

Then `:LspRestart` in any open TS buffer. Plain `gd` (LSP go-to-definition)
into a vendored type opens the file directly out of `.yarn/cache/*.zip`
courtesy of vim-rzip.

If the team prefers not to commit `@yarnpkg/sdks`, install it in a sibling dir
and symlink `.yarn/sdks` from there.
