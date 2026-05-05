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
| `K` | Show documentation |

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
| `<leader>gd` | Diffview open |
| `<leader>gh` | File history |
| `<leader>gx` | Diffview close |
| `<leader>gB` | Blame buffer |
| `]h` / `[h` | Next/previous hunk |
| `<leader>hp` | Preview hunk |
| `<leader>hb` | Blame line (full) |
| `<leader>tb` | Toggle inline blame |

Inline blame (author, relative time, summary) is **on by default** at the end of the current line.

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
