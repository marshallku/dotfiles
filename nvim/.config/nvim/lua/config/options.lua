-- Leader key (set before plugins load)
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- General settings
vim.opt.number = true -- Show line numbers
vim.opt.relativenumber = true -- Relative line numbers
vim.opt.mouse = "a" -- Enable mouse support
vim.opt.clipboard = "unnamedplus" -- Use system clipboard
vim.opt.undofile = true -- Persistent undo
vim.opt.ignorecase = true -- Case-insensitive search
vim.opt.smartcase = true -- Case-sensitive if uppercase present
vim.opt.updatetime = 250 -- Faster completion
vim.opt.timeoutlen = 300 -- Faster key sequence completion
vim.opt.splitright = true -- Vertical splits to the right
vim.opt.splitbelow = true -- Horizontal splits below
vim.opt.termguicolors = true -- True color support
vim.opt.cursorline = true -- Highlight current line
vim.opt.signcolumn = "yes" -- Always show sign column

-- Tabs and indentation
vim.opt.tabstop = 2 -- 2 spaces for tabs
vim.opt.shiftwidth = 2 -- 2 spaces for indent width
vim.opt.expandtab = true -- Expand tab to spaces
vim.opt.autoindent = true -- Copy indent from current line
vim.opt.smartindent = true -- Smart indentation

-- Line wrapping
vim.opt.wrap = true -- Enable line wrapping (matching Cursor setting)

-- Search
vim.opt.hlsearch = true -- Highlight search results
vim.opt.incsearch = true -- Incremental search

-- Appearance
vim.opt.scrolloff = 8 -- Minimum lines above/below cursor
vim.opt.sidescrolloff = 8 -- Minimum columns left/right of cursor
vim.opt.showmode = false -- Don't show mode (statusline shows it)
vim.opt.winblend = 10 -- Window transparency (0-100, 0 = opaque, 100 = fully transparent)
vim.opt.pumblend = 10 -- Popup menu transparency (0-100, 0 = opaque, 100 = fully transparent)
vim.opt.conceallevel = 0 -- Don't conceal characters (for ligatures to work properly)

-- Completion menu
vim.opt.completeopt = "menu,menuone,noselect"

-- File handling
vim.opt.backup = false -- No backup file
vim.opt.swapfile = false -- No swap file

-- Linked editing (for HTML/XML tags - matching Cursor's editor.linkedEditing)
vim.opt.matchpairs:append("<:>") -- Enable linked editing for angle brackets
