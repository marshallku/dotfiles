return {
    "folke/tokyonight.nvim",
    lazy = false,
    priority = 1000,
    cond = function() return not vim.g.vscode end,
    -- Loaded for its lualine theme (statusline theme = "tokyonight").
    -- The active colorscheme stays catppuccin (see colorscheme.lua).
    opts = {style = "storm"},
}
