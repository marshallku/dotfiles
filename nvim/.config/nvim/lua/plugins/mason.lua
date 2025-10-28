return {
    "williamboman/mason.nvim",
    dependencies = {
        "williamboman/mason-lspconfig.nvim",
        "WhoIsSethDaniel/mason-tool-installer.nvim"
    },
    config = function()
        local mason = require("mason")
        local mason_lspconfig = require("mason-lspconfig")
        local mason_tool_installer = require("mason-tool-installer")

        mason.setup({
            ui = {
                icons = {
                    package_installed = "✓",
                    package_pending = "➜",
                    package_uninstalled = "✗"
                }
            }
        })

        mason_lspconfig.setup({
            ensure_installed = {
                "ts_ls", -- TypeScript/JavaScript
                "rust_analyzer", -- Rust
                "gopls", -- Go
                "pyright", -- Python
                "intelephense", -- PHP
                "lua_ls", -- Lua
                "html", -- HTML
                "cssls", -- CSS
                "tailwindcss", -- Tailwind CSS
                "jsonls" -- JSON
            },
            automatic_installation = true
        })

        mason_tool_installer.setup({
            ensure_installed = {
                "prettier", -- Formatter for web langs
                "stylua", -- Lua formatter
                "eslint_d", -- JS/TS linter
                "rustfmt", -- Rust formatter
                "gofumpt", -- Go formatter
                "black", -- Python formatter
                "pylint", -- Python linter
                "phpcs", -- PHP linter
                "phpcbf" -- PHP formatter
            }
        })
    end
}
