local autocmd = vim.api.nvim_create_autocmd
local augroup = vim.api.nvim_create_augroup

-- Highlight on yank
autocmd("TextYankPost", {
    group = augroup("highlight_yank", {clear = true}),
    callback = function() vim.highlight.on_yank({timeout = 200}) end
})

-- Remove trailing whitespace on save
autocmd("BufWritePre", {
    group = augroup("trim_whitespace", {clear = true}),
    pattern = "*",
    command = [[%s/\s\+$//e]]
})

-- Auto-close certain filetypes with q
autocmd("FileType", {
    group = augroup("close_with_q", {clear = true}),
    pattern = {"help", "lspinfo", "man", "qf", "query", "checkhealth"},
    callback = function(event)
        vim.bo[event.buf].buflisted = false
        vim.keymap.set("n", "q", "<cmd>close<CR>",
                       {buffer = event.buf, silent = true})
    end
})

-- Auto-resize splits when window is resized
autocmd("VimResized", {
    group = augroup("resize_splits", {clear = true}),
    callback = function() vim.cmd("tabdo wincmd =") end
})

-- Don't auto-comment new lines
autocmd("BufEnter", {
    group = augroup("no_auto_comment", {clear = true}),
    callback = function() vim.opt.formatoptions:remove({"c", "r", "o"}) end
})
