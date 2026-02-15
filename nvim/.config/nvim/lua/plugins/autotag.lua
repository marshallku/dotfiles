return {
    "windwp/nvim-ts-autotag",
    event = {"BufReadPre", "BufNewFile"},
    dependencies = {"nvim-treesitter/nvim-treesitter"},
    config = function()
        require("nvim-ts-autotag").setup({
            filetypes = {
                "html", "javascript", "typescript", "javascriptreact",
                "typescriptreact", "svelte", "vue", "tsx", "jsx", "rescript",
                "xml", "php", "markdown", "glimmer", "handlebars", "hbs"
            }
        })
    end
}

