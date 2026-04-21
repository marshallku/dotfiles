return {
    "olimorris/codecompanion.nvim",
    cond = function() return not vim.g.vscode end,
    cmd = { "CodeCompanion", "CodeCompanionChat", "CodeCompanionActions" },
    keys = {
        { "<leader>ai", "<cmd>CodeCompanionChat Toggle<CR>", mode = { "n", "v" }, desc = "AI Chat" },
        { "<leader>aa", "<cmd>CodeCompanionActions<CR>", mode = { "n", "v" }, desc = "AI Actions" },
        { "<leader>ac", "<cmd>CodeCompanionChat Add<CR>", mode = "v", desc = "AI Add to Chat" },
    },
    dependencies = {
        "nvim-lua/plenary.nvim",
        "nvim-treesitter/nvim-treesitter",
    },
    opts = {
        strategies = {
            chat = { adapter = "copilot" },
            inline = { adapter = "copilot" },
        },
        display = {
            chat = {
                window = {
                    layout = "vertical",
                    width = 0.4,
                },
            },
        },
    },
}
