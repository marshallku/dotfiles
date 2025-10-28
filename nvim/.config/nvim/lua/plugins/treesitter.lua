return {
    "nvim-treesitter/nvim-treesitter",
    event = {"BufReadPre", "BufNewFile"},
    build = ":TSUpdate",
    dependencies = {"nvim-treesitter/nvim-treesitter-textobjects"},
    config = function()
        require("nvim-treesitter.configs").setup({
            -- Languages to install
            ensure_installed = {
                "typescript", "tsx", "javascript", "rust", "go", "python",
                "php", "lua", "vim", "vimdoc", "html", "css", "json", "yaml",
                "toml", "markdown", "markdown_inline", "bash", "dockerfile",
                "gitignore"
            },

            -- Auto-install missing parsers
            auto_install = true,

            -- Syntax highlighting
            highlight = {
                enable = true,
                additional_vim_regex_highlighting = false
            },

            -- Indentation
            indent = {enable = true},

            -- Incremental selection
            incremental_selection = {
                enable = true,
                keymaps = {
                    init_selection = "<C-space>",
                    node_incremental = "<C-space>",
                    scope_incremental = false,
                    node_decremental = "<bs>"
                }
            },

            -- Text objects
            textobjects = {
                select = {
                    enable = true,
                    lookahead = true,
                    keymaps = {
                        ["af"] = "@function.outer",
                        ["if"] = "@function.inner",
                        ["ac"] = "@class.outer",
                        ["ic"] = "@class.inner"
                    }
                }
            }
        })
    end
}
