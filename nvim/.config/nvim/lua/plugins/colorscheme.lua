return {
    "folke/tokyonight.nvim",
    lazy = false, -- Load during startup
    priority = 1000, -- Load before other plugins
    config = function()
        require("tokyonight").setup({
            style = "night", -- storm, night, moon, or day
            transparent = true, -- Transparent background
            terminal_colors = true, -- Terminal colors
            styles = {
                comments = {italic = true},
                keywords = {italic = true},
                functions = {},
                variables = {}
            },
            on_highlights = function(hl, c)
                hl.NeoTreeNormal = {bg = "NONE"}
                hl.NeoTreeNormalNC = {bg = "NONE"}
                hl.NeoTreeEndOfBuffer = {bg = "NONE"}
            end
        })
        vim.cmd([[colorscheme tokyonight]])
    end
}
