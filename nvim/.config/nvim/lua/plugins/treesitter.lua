return {
    "nvim-treesitter/nvim-treesitter",
    branch = "main",
    build = ":TSUpdate",
    lazy = false,
    dependencies = {
        {"nvim-treesitter/nvim-treesitter-textobjects", branch = "main"}
    },
    config = function()
        require("nvim-treesitter").setup()

        require("nvim-treesitter").install({
            "typescript", "tsx", "javascript", "rust", "go", "python",
            "php", "lua", "vim", "vimdoc", "html", "css", "scss", "json",
            "yaml", "toml", "markdown", "markdown_inline", "bash",
            "dockerfile", "gitignore", "graphql"
        })

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

        -- v2 (main) drops the built-in highlight/indent modules: enable per buffer
        vim.api.nvim_create_autocmd("FileType", {
            callback = function(args)
                if not pcall(vim.treesitter.start, args.buf) then return end
                vim.bo[args.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
            end,
        })
    end
}
