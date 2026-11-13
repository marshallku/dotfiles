-- Plugins that fill the gaps left by Cursor extensions.
return {
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
