return {
    "folke/todo-comments.nvim",
    event = { "BufReadPre", "BufNewFile" },
    dependencies = { "nvim-lua/plenary.nvim" },
    opts = {
        signs = true,
        highlight = {
            multiline = false,
            before = "",
            keyword = "wide",
            after = "fg",
            pattern = [[.*<(KEYWORDS)\s*:]],
        },
        search = {
            command = "rg",
            args = { "--color=never", "--no-heading", "--with-filename", "--line-number", "--column" },
            pattern = [[\b(KEYWORDS):]],
        },
    },
    keys = {
        { "]t", function() require("todo-comments").jump_next() end, desc = "Next TODO" },
        { "[t", function() require("todo-comments").jump_prev() end, desc = "Previous TODO" },
        { "<leader>ft", "<cmd>TodoTelescope<CR>", desc = "Find TODOs" },
    },
}
