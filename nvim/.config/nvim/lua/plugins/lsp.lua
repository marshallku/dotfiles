return {
    "neovim/nvim-lspconfig",
    cond = function() return not vim.g.vscode end,
    event = { "BufReadPre", "BufNewFile" },
    dependencies = {
        { "antosha417/nvim-lsp-file-operations", config = true },
    },
    config = function()
        -- Drop the global gr* defaults (0.11+). With a buffer-local `gr` they
        -- make `gr` wait timeoutlen for a follow-up key. Their actions live on
        -- <leader>rn, <leader>ca, gi and gt.
        for _, lhs in ipairs({ "grn", "grr", "gri", "grt", "grx" }) do
            pcall(vim.keymap.del, "n", lhs)
        end
        pcall(vim.keymap.del, { "n", "x" }, "gra")

        -- LSP keymaps on attach
        vim.api.nvim_create_autocmd("LspAttach", {
            group = vim.api.nvim_create_augroup("lsp_attach_keymaps", { clear = true }),
            callback = function(event)
                local opts = { buffer = event.buf, silent = true }
                local keymap = vim.keymap

                opts.desc = "Show LSP references"
                keymap.set("n", "gr", "<cmd>Telescope lsp_references<CR>", opts)

                opts.desc = "Go to declaration"
                keymap.set("n", "gD", vim.lsp.buf.declaration, opts)

                opts.desc = "Show LSP definitions"
                keymap.set("n", "gd", "<cmd>Telescope lsp_definitions<CR>", opts)

                opts.desc = "Show LSP implementations"
                keymap.set("n", "gi", "<cmd>Telescope lsp_implementations<CR>", opts)

                opts.desc = "Show LSP type definitions"
                keymap.set("n", "gt", "<cmd>Telescope lsp_type_definitions<CR>", opts)

                opts.desc = "Find document symbols"
                keymap.set("n", "<leader>fs", "<cmd>Telescope lsp_document_symbols<CR>", opts)

                opts.desc = "Find workspace symbols"
                keymap.set("n", "<leader>fS", "<cmd>Telescope lsp_dynamic_workspace_symbols<CR>", opts)

                opts.desc = "Incoming calls"
                keymap.set("n", "<leader>ci", "<cmd>Telescope lsp_incoming_calls<CR>", opts)

                opts.desc = "Outgoing calls"
                keymap.set("n", "<leader>co", "<cmd>Telescope lsp_outgoing_calls<CR>", opts)

                opts.desc = "Show available code actions"
                keymap.set({ "n", "v" }, "<leader>ca", vim.lsp.buf.code_action, opts)

                opts.desc = "Smart rename"
                keymap.set("n", "<leader>rn", vim.lsp.buf.rename, opts)

                opts.desc = "Show buffer diagnostics"
                keymap.set("n", "<leader>D", "<cmd>Telescope diagnostics bufnr=0<CR>", opts)

                opts.desc = "Show line diagnostics"
                keymap.set("n", "<leader>d", vim.diagnostic.open_float, opts)

                opts.desc = "Go to previous diagnostic"
                keymap.set("n", "[d", function() vim.diagnostic.jump({ count = -1 }) end, opts)

                opts.desc = "Go to next diagnostic"
                keymap.set("n", "]d", function() vim.diagnostic.jump({ count = 1 }) end, opts)

                opts.desc = "Show documentation"
                keymap.set("n", "K", vim.lsp.buf.hover, opts)

                opts.desc = "Restart LSP"
                keymap.set("n", "<leader>rs", ":LspRestart<CR>", opts)
            end,
        })

        -- Diagnostic configuration
        vim.diagnostic.config({
            signs = {
                text = {
                    [vim.diagnostic.severity.ERROR] = " ",
                    [vim.diagnostic.severity.WARN] = " ",
                    [vim.diagnostic.severity.HINT] = "󰠠 ",
                    [vim.diagnostic.severity.INFO] = " ",
                },
            },
            virtual_text = {
                spacing = 4,
                prefix = "●",
                severity = {
                    min = vim.diagnostic.severity.HINT,
                },
                format = function(diagnostic)
                    local max_width = math.floor(vim.o.columns * 0.4)
                    local message = diagnostic.message
                    if #message > max_width then
                        return message:sub(1, max_width - 3) .. "..."
                    end
                    return message
                end,
            },
            float = {
                border = "rounded",
                source = true,
                header = "",
                prefix = "",
            },
            update_in_insert = false,
            severity_sort = true,
        })

        -- Auto show diagnostics on cursor hold
        vim.api.nvim_create_autocmd("CursorHold", {
            group = vim.api.nvim_create_augroup("float_diagnostic", { clear = true }),
            callback = function()
                vim.diagnostic.open_float(nil, { focus = false })
            end,
        })

        -- Add missing imports on save (TypeScript/JavaScript)
        vim.api.nvim_create_autocmd("BufWritePre", {
            group = vim.api.nvim_create_augroup("lsp_add_imports", { clear = true }),
            pattern = { "*.ts", "*.tsx", "*.js", "*.jsx" },
            callback = function(event)
                local clients = vim.lsp.get_clients({ bufnr = event.buf, method = "textDocument/codeAction" })
                for _, client in ipairs(clients) do
                    local params = vim.lsp.util.make_range_params(0, client.offset_encoding)
                    params.context = {
                        only = { "source.addMissingImports" },
                        diagnostics = {},
                    }
                    local response = client:request_sync("textDocument/codeAction", params, 3000, event.buf)
                    for _, action in ipairs(response and response.result or {}) do
                        if action.edit then
                            vim.lsp.util.apply_workspace_edit(action.edit, client.offset_encoding)
                        end
                        -- A CodeAction carries a Command table; a bare Command has a string `command`
                        local command = type(action.command) == "table" and action.command
                            or (type(action.command) == "string" and action)
                        if command then
                            client:exec_cmd(command, { bufnr = event.buf })
                        end
                    end
                end
            end,
        })

        -- TypeScript/JavaScript (vtsls - VSCode TypeScript extension wrapper)
        -- Yarn PnP: detect .pnp.cjs upward from buffer dir (NOT cwd, which breaks
        -- in monorepos and when opening files outside the project root) and point
        -- typescript.tsdk at the workspace's .yarn/sdks/typescript/lib.
        vim.lsp.config("vtsls", {
            settings = {
                vtsls = {},
                typescript = {
                    suggest = {
                        autoImports = true,
                        completeFunctionCalls = true,
                    },
                    inlayHints = {
                        parameterNames = { enabled = "literals" },
                        parameterTypes = { enabled = true },
                        variableTypes = { enabled = true },
                        propertyDeclarationTypes = { enabled = true },
                        functionLikeReturnTypes = { enabled = true },
                        enumMemberValues = { enabled = true },
                    },
                },
                javascript = {
                    suggest = {
                        autoImports = true,
                        completeFunctionCalls = true,
                    },
                },
            },
            before_init = function(_, config)
                local buf = vim.api.nvim_get_current_buf()
                local bufname = vim.api.nvim_buf_get_name(buf)
                local search_from = bufname ~= "" and vim.fs.dirname(bufname) or vim.uv.cwd()
                local pnp = vim.fs.find({ ".pnp.cjs", ".pnp.js" }, { upward = true, path = search_from })[1]
                if pnp then
                    local sdk = vim.fs.dirname(pnp) .. "/.yarn/sdks/typescript/lib"
                    if vim.uv.fs_stat(sdk) then
                        config.settings.typescript.tsdk = sdk
                        config.settings.vtsls.autoUseWorkspaceTsdk = true
                    end
                end
            end,
        })

        -- ESLint (language server for linting + auto-fix)
        vim.lsp.config("eslint", {
            settings = {
                format = false, -- Use prettier via conform instead
            },
        })

        -- Rust
        vim.lsp.config("rust_analyzer", {
            settings = {
                ["rust-analyzer"] = {
                    check = {
                        command = "clippy",
                    },
                },
            },
        })

        -- Go
        vim.lsp.config("gopls", {
            settings = {
                gopls = {
                    hints = {
                        assignVariableTypes = true,
                        compositeLiteralFields = true,
                        compositeLiteralTypes = true,
                        constantValues = true,
                        functionTypeParameters = true,
                        parameterNames = true,
                        rangeVariableTypes = true,
                    },
                    analyses = {
                        unusedparams = true,
                    },
                    staticcheck = true,
                },
            },
        })

        -- Python
        vim.lsp.config("pyright", {})

        -- PHP
        vim.lsp.config("intelephense", {})

        -- YAML (k8s, GitHub Actions, docker-compose schemas)
        vim.lsp.config("yamlls", {
            settings = {
                yaml = {
                    keyOrdering = false,
                    schemaStore = {
                        enable = true,
                        url = "https://www.schemastore.org/api/json/catalog.json",
                    },
                },
            },
        })

        -- Svelte
        vim.lsp.config("svelte", {})

        -- Lua (for Neovim config)
        vim.lsp.config("lua_ls", {
            settings = {
                Lua = {
                    diagnostics = { globals = { "vim" } },
                    workspace = {
                        library = {
                            [vim.fn.expand("$VIMRUNTIME/lua")] = true,
                            [vim.fn.stdpath("config") .. "/lua"] = true,
                        },
                    },
                },
            },
        })

        -- Kotlin (JetBrains kotlin-lsp, Alpha; JVM Gradle/Maven only).
        -- Mason's package 404s since JetBrains moved to signed CDN URLs, so look
        -- in Mason first, then a manual install, then PATH (brew cask).
        local function kotlin_lsp_cmd()
            local candidates = {
                vim.fn.stdpath("data") .. "/mason/bin/kotlin-lsp",
                vim.fn.expand("~/.local/share/kotlin-lsp/kotlin-lsp.sh"),
            }
            for _, path in ipairs(candidates) do
                if vim.fn.executable(path) == 1 then
                    return { path, "--stdio" }
                end
            end
            return { "kotlin-lsp", "--stdio" }
        end

        vim.lsp.config("kotlin_lsp", {
            cmd = kotlin_lsp_cmd(),
        })

        -- Enable all configured LSP servers
        vim.lsp.enable({
            "vtsls", "eslint", "rust_analyzer", "gopls",
            "pyright", "intelephense", "lua_ls",
            "html", "cssls", "tailwindcss", "jsonls",
            "yamlls", "svelte", "kotlin_lsp",
        })
    end,
}
