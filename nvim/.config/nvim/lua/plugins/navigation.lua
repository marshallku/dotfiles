-- IDE-style code navigation (parity with Cursor's Problems, Peek, Outline,
-- Breadcrumbs and Sticky Scroll).
return {
    -- Problems panel, symbol outline, LSP locations side panel
    {
        "folke/trouble.nvim",
        cond = function() return not vim.g.vscode end,
        cmd = "Trouble",
        keys = {
            { "<leader>xx", "<cmd>Trouble diagnostics toggle<cr>", desc = "Project diagnostics" },
            { "<leader>xX", "<cmd>Trouble diagnostics toggle filter.buf=0<cr>", desc = "Buffer diagnostics" },
            { "<leader>xs", "<cmd>Trouble symbols toggle focus=false<cr>", desc = "Symbol outline" },
            {
                "<leader>xl",
                "<cmd>Trouble lsp toggle focus=false win.position=right<cr>",
                desc = "LSP definitions/references/calls",
            },
        },
        opts = {},
    },

    -- Peek definitions/references without leaving the current location
    {
        "dnlhc/glance.nvim",
        cond = function() return not vim.g.vscode end,
        cmd = "Glance",
        keys = {
            { "<leader>pd", "<cmd>Glance definitions<cr>", desc = "Peek definition" },
            { "<leader>pr", "<cmd>Glance references<cr>", desc = "Peek references" },
            { "<leader>pi", "<cmd>Glance implementations<cr>", desc = "Peek implementations" },
            { "<leader>pt", "<cmd>Glance type_definitions<cr>", desc = "Peek type definition" },
        },
        opts = {},
    },

    -- Breadcrumbs in the winbar
    {
        "Bekaboo/dropbar.nvim",
        cond = function() return not vim.g.vscode end,
        event = { "BufReadPost", "BufNewFile" },
        keys = {
            { "<leader>;", function() require("dropbar.api").pick() end, desc = "Pick breadcrumb" },
        },
        opts = {},
    },

    -- Sticky function/class headers
    {
        "nvim-treesitter/nvim-treesitter-context",
        cond = function() return not vim.g.vscode end,
        event = { "BufReadPost", "BufNewFile" },
        keys = {
            {
                "[x",
                function() require("treesitter-context").go_to_context(vim.v.count1) end,
                desc = "Jump to context",
            },
        },
        opts = { max_lines = 3 },
    },
}
