local keymap = vim.keymap

-- Clear search highlights
keymap.set("n", "<Esc>", "<cmd>nohlsearch<CR>")

-- Better window navigation
keymap.set("n", "<C-h>", "<C-w>h", { desc = "Move to left window" })
keymap.set("n", "<C-j>", "<C-w>j", { desc = "Move to bottom window" })
keymap.set("n", "<C-k>", "<C-w>k", { desc = "Move to top window" })
keymap.set("n", "<C-l>", "<C-w>l", { desc = "Move to right window" })

-- Resize windows
keymap.set("n", "<C-Up>", "<cmd>resize +2<CR>", { desc = "Increase window height" })
keymap.set("n", "<C-Down>", "<cmd>resize -2<CR>", { desc = "Decrease window height" })
keymap.set("n", "<C-Left>", "<cmd>vertical resize -2<CR>", { desc = "Decrease window width" })
keymap.set("n", "<C-Right>", "<cmd>vertical resize +2<CR>", { desc = "Increase window width" })

-- Buffer navigation
keymap.set("n", "<S-h>", "<cmd>bprevious<CR>", { desc = "Previous buffer" })
keymap.set("n", "<S-l>", "<cmd>bnext<CR>", { desc = "Next buffer" })
keymap.set("n", "<leader>bd", "<cmd>bdelete<CR>", { desc = "Delete buffer" })

-- Better indenting
keymap.set("v", "<", "<gv", { desc = "Indent left" })
keymap.set("v", ">", ">gv", { desc = "Indent right" })

-- Move lines up/down
keymap.set("n", "<A-j>", "<cmd>m .+1<CR>==", { desc = "Move line down" })
keymap.set("n", "<A-k>", "<cmd>m .-2<CR>==", { desc = "Move line up" })
keymap.set("v", "<A-j>", ":m '>+1<CR>gv=gv", { desc = "Move selection down" })
keymap.set("v", "<A-k>", ":m '<-2<CR>gv=gv", { desc = "Move selection up" })

-- Better paste (don't yank replaced text)
keymap.set("v", "p", '"_dP', { desc = "Paste without yanking" })

-- Quick save
keymap.set("n", "<C-s>", "<cmd>w<CR>", { desc = "Save file" })
keymap.set("i", "<C-s>", "<Esc><cmd>w<CR>a", { desc = "Save file" })

-- Quick quit
keymap.set("n", "<leader>q", "<cmd>q<CR>", { desc = "Quit" })
keymap.set("n", "<leader>Q", "<cmd>qa!<CR>", { desc = "Quit all without saving" })

-- Split windows
keymap.set("n", "<leader>sv", "<C-w>v", { desc = "Split vertically" })
keymap.set("n", "<leader>sh", "<C-w>s", { desc = "Split horizontally" })
keymap.set("n", "<leader>se", "<C-w>=", { desc = "Equal split size" })
keymap.set("n", "<leader>sx", "<cmd>close<CR>", { desc = "Close split" })

-- Tab management
keymap.set("n", "<leader>to", "<cmd>tabnew<CR>", { desc = "Open new tab" })
keymap.set("n", "<leader>tx", "<cmd>tabclose<CR>", { desc = "Close tab" })
keymap.set("n", "<leader>tn", "<cmd>tabn<CR>", { desc = "Next tab" })
keymap.set("n", "<leader>tp", "<cmd>tabp<CR>", { desc = "Previous tab" })

-- Yank file reference as @path:line or @path:start-end (for Claude / chat paste)
local function yank_ref(range)
    local abs = vim.fn.expand("%:p")
    if abs == "" then
        vim.notify("yank_ref: no file", vim.log.levels.WARN)
        return
    end
    local root = vim.fn.systemlist("git -C " .. vim.fn.shellescape(vim.fn.expand("%:p:h")) .. " rev-parse --show-toplevel")[1]
    local path
    if vim.v.shell_error == 0 and root and root ~= "" then
        path = abs:sub(#root + 2) -- strip "<root>/"
    else
        path = vim.fn.fnamemodify(abs, ":.")
    end
    local ref = range and ("@%s:%d-%d"):format(path, range[1], range[2]) or ("@%s:%d"):format(path, vim.fn.line("."))
    vim.fn.setreg("+", ref)
    vim.notify(ref)
end

keymap.set("n", "<leader>yr", function() yank_ref(nil) end, { desc = "Yank @path:line ref" })
keymap.set("x", "<leader>yr", function()
    local s, e = vim.fn.line("v"), vim.fn.line(".")
    if s > e then s, e = e, s end
    -- leave visual mode so getpos marks settle (cosmetic; line() already correct here)
    vim.cmd("normal! \27")
    yank_ref({ s, e })
end, { desc = "Yank @path:start-end ref" })
