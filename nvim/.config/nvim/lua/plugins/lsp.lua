return {
    "neovim/nvim-lspconfig",
    event = {"BufReadPre", "BufNewFile"},
    dependencies = {
        "hrsh7th/cmp-nvim-lsp",
        {"antosha417/nvim-lsp-file-operations", config = true}
    },
    config = function()
        local cmp_nvim_lsp = require("cmp_nvim_lsp")
        local keymap = vim.keymap

        -- LSP keymaps on attach
        local on_attach = function(client, bufnr)
            local opts = {buffer = bufnr, silent = true}

            opts.desc = "Show LSP references"
            keymap.set("n", "gr", "<cmd>Telescope lsp_references<CR>", opts)

            opts.desc = "Go to declaration"
            keymap.set("n", "gD", vim.lsp.buf.declaration, opts)

            opts.desc = "Show LSP definitions"
            keymap.set("n", "gd", "<cmd>Telescope lsp_definitions<CR>", opts)

            opts.desc = "Show LSP implementations"
            keymap.set("n", "gi", "<cmd>Telescope lsp_implementations<CR>", opts)

            opts.desc = "Show LSP type definitions"
            keymap.set("n", "gt", "<cmd>Telescope lsp_type_definitions<CR>",
                       opts)

            opts.desc = "Show available code actions"
            keymap.set({"n", "v"}, "<leader>ca", vim.lsp.buf.code_action, opts)

            opts.desc = "Smart rename"
            keymap.set("n", "<leader>rn", vim.lsp.buf.rename, opts)

            opts.desc = "Show buffer diagnostics"
            keymap.set("n", "<leader>D",
                       "<cmd>Telescope diagnostics bufnr=0<CR>", opts)

            opts.desc = "Show line diagnostics"
            keymap.set("n", "<leader>d", vim.diagnostic.open_float, opts)

            opts.desc = "Go to previous diagnostic"
            keymap.set("n", "[d", vim.diagnostic.goto_prev, opts)

            opts.desc = "Go to next diagnostic"
            keymap.set("n", "]d", vim.diagnostic.goto_next, opts)

            opts.desc = "Show documentation"
            keymap.set("n", "K", vim.lsp.buf.hover, opts)

            opts.desc = "Restart LSP"
            keymap.set("n", "<leader>rs", ":LspRestart<CR>", opts)
        end

        -- Enhanced capabilities with nvim-cmp
        local capabilities = cmp_nvim_lsp.default_capabilities()

        -- Diagnostic signs
        vim.diagnostic.config({
            signs = {
                text = {
                    [vim.diagnostic.severity.ERROR] = " ",
                    [vim.diagnostic.severity.WARN] = " ",
                    [vim.diagnostic.severity.HINT] = "󰠠 ",
                    [vim.diagnostic.severity.INFO] = " "
                }
            }
        })

        -- TypeScript/JavaScript
        vim.lsp.config("ts_ls",
                       {capabilities = capabilities, on_attach = on_attach})

        -- Rust
        vim.lsp.config("rust_analyzer", {
            capabilities = capabilities,
            on_attach = on_attach,
            settings = {
                ["rust-analyzer"] = {
                    check = {
                        command = "clippy"
                    }
                }
            }
        })

        -- Go
        vim.lsp.config("gopls",
                       {capabilities = capabilities, on_attach = on_attach})

        -- Python
        vim.lsp.config("pyright",
                       {capabilities = capabilities, on_attach = on_attach})

        -- PHP
        vim.lsp.config("intelephense",
                       {capabilities = capabilities, on_attach = on_attach})

        -- Lua (for Neovim config)
        vim.lsp.config("lua_ls", {
            capabilities = capabilities,
            on_attach = on_attach,
            settings = {
                Lua = {
                    diagnostics = {globals = {"vim"}},
                    workspace = {
                        library = {
                            [vim.fn.expand("$VIMRUNTIME/lua")] = true,
                            [vim.fn.stdpath("config") .. "/lua"] = true
                        }
                    }
                }
            }
        })

        -- Auto-enable LSP servers when filetype is detected
        vim.api.nvim_create_autocmd("FileType", {
            group = vim.api.nvim_create_augroup("lsp_enable", {clear = true}),
            callback = function(args)
                local server_map = {
                    typescript = "ts_ls",
                    typescriptreact = "ts_ls",
                    javascript = "ts_ls",
                    javascriptreact = "ts_ls",
                    rust = "rust_analyzer",
                    go = "gopls",
                    python = "pyright",
                    php = "intelephense",
                    lua = "lua_ls"
                }

                local server = server_map[vim.bo[args.buf].filetype]
                if server then vim.lsp.enable(server) end
            end
        })
    end
}
