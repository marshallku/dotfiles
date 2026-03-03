return {
    "catppuccin/nvim",
    name = "catppuccin",
    lazy = false,
    priority = 1000,
    config = function()
        require("catppuccin").setup({
            flavour = "mocha",
            transparent_background = true,
            term_colors = true,
            styles = {
                comments = { "italic" },
                keywords = { "italic" },
                functions = {},
                variables = {},
            },
            integrations = {
                neotree = true,
                treesitter = true,
                native_lsp = { enabled = true },
            },
            custom_highlights = function(colors)
                return {
                    NeoTreeNormal = { bg = "NONE" },
                    NeoTreeNormalNC = { bg = "NONE" },
                    NeoTreeEndOfBuffer = { bg = "NONE" },
                }
            end,
        })
        vim.cmd([[colorscheme catppuccin]])
    end,
}
