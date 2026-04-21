return {
    "nvim-treesitter/nvim-treesitter",
    build = ":TSUpdate",
    lazy = false,
    dependencies = {"nvim-treesitter/nvim-treesitter-textobjects"},
    config = function()
        -- nvim-treesitter v2.x: setup() is optional (only needed for custom install_dir)
        require("nvim-treesitter").setup()

        -- Ensure parsers are installed (async, no-op if already installed)
        require("nvim-treesitter").install({
            "typescript", "tsx", "javascript", "rust", "go", "python",
            "php", "lua", "vim", "vimdoc", "html", "css", "scss", "json",
            "yaml", "toml", "markdown", "markdown_inline", "bash",
            "dockerfile", "gitignore", "graphql"
        })

        -- Text objects (using nvim-treesitter-textobjects v2 API)
        require("nvim-treesitter-textobjects").setup({
            select = {
                lookahead = true,
                keymaps = {
                    ["af"] = "@function.outer",
                    ["if"] = "@function.inner",
                    ["ac"] = "@class.outer",
                    ["ic"] = "@class.inner",
                },
            },
        })
    end
}
