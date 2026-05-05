-- Plugins that fill the gaps left by Cursor extensions.
return {
    -- magit-style git UI (replaces kahole.magit)
    {
        "NeogitOrg/neogit",
        cond = function() return not vim.g.vscode end,
        cmd = "Neogit",
        keys = {
            { "<leader>gn", "<cmd>Neogit<cr>", desc = "Neogit" },
        },
        dependencies = {
            "nvim-lua/plenary.nvim",
            "sindrets/diffview.nvim",
            "nvim-telescope/telescope.nvim",
        },
        opts = {
            integrations = { telescope = true, diffview = true },
        },
    },

    -- Side-by-side diff viewer (parity with GitLens "Open Changes")
    {
        "sindrets/diffview.nvim",
        cond = function() return not vim.g.vscode end,
        cmd = { "DiffviewOpen", "DiffviewFileHistory", "DiffviewClose" },
        keys = {
            { "<leader>gd", "<cmd>DiffviewOpen<cr>", desc = "Diffview open" },
            { "<leader>gh", "<cmd>DiffviewFileHistory %<cr>", desc = "File history" },
            { "<leader>gx", "<cmd>DiffviewClose<cr>", desc = "Diffview close" },
        },
        dependencies = { "nvim-lua/plenary.nvim" },
    },

    -- Case conversion (parity with wmaurer.change-case).
    -- Prefix is `gA` (capital) so built-in `ga` (ASCII inspect) is preserved.
    {
        "johmsalas/text-case.nvim",
        cond = function() return not vim.g.vscode end,
        keys = {
            { "gA", mode = { "n", "x" }, desc = "Text case" },
        },
        dependencies = { "nvim-telescope/telescope.nvim" },
        config = function()
            require("textcase").setup({
                default_keymappings_enabled = true,
                prefix = "gA",
            })
        end,
    },

    -- Tab out of brackets/quotes (parity with albert.tabout)
    {
        "abecodes/tabout.nvim",
        cond = function() return not vim.g.vscode end,
        event = "InsertEnter",
        dependencies = { "nvim-treesitter/nvim-treesitter" },
        opts = {
            tabkey = "<Tab>",
            backwards_tabkey = "<S-Tab>",
            act_as_tab = true,
            act_as_shift_tab = false,
            default_tab = "<C-t>",
            default_shift_tab = "<C-d>",
        },
    },
}
