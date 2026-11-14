return {
    "folke/which-key.nvim",
    cond = function() return not vim.g.vscode end,
    event = "VeryLazy",
    init = function()
        vim.o.timeout = true
        vim.o.timeoutlen = 300
    end,
    config = function()
        local wk = require("which-key")

        wk.setup({})

        -- Register group names
        wk.add({
            {"<leader>f", group = "Find"}, {"<leader>s", group = "Split"},
            {"<leader>t", group = "Tab"}, {"<leader>c", group = "Code"},
            {"<leader>r", group = "Rename/Restart"}, {"<leader>h", group = "Git Hunk"},
            {"<leader>b", group = "Buffer"}, {"<leader>e", group = "Explorer"},
            {"<leader>m", group = "Format"}, {"<leader>g", group = "Git"},
            {"<leader>v", group = "Review"}, {"<leader>x", group = "Trouble"},
            {"<leader>p", group = "Peek"}, {"<leader>y", group = "Yank ref"}
        })
    end
}
