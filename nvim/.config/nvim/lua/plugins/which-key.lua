return {
    "folke/which-key.nvim",
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
            {"<leader>r", group = "Rename"}, {"<leader>h", group = "Git Hunk"},
            {"<leader>b", group = "Buffer"}, {"<leader>e", group = "Explorer"},
            {"<leader>m", group = "Format"}
        })
    end
}
