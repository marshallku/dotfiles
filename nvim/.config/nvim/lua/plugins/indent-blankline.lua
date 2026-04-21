return {
    "lukas-reineke/indent-blankline.nvim",
    cond = function() return not vim.g.vscode end,
    event = {"BufReadPre", "BufNewFile"},
    main = "ibl",
    config = function()
        require("ibl").setup({
            indent = {char = "│"},
            scope = {enabled = true, show_start = true, show_end = false},
            exclude = {filetypes = {"help", "lazy", "mason", "neo-tree"}}
        })
    end
}
