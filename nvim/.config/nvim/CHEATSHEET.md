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
| `]h` / `[h>` | Next/previous hunk |
| `<leader>hp` | Preview hunk |
| `<leader>hb` | Blame line |

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
