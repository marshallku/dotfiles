return {
    "hrsh7th/nvim-cmp",
    event = "InsertEnter",
    dependencies = {
        "hrsh7th/cmp-buffer", -- Buffer completions
        "hrsh7th/cmp-path", -- Path completions
        "L3MON4D3/LuaSnip", -- Snippet engine
        "saadparwaiz1/cmp_luasnip", -- Snippet completions
        "rafamadriz/friendly-snippets", -- Useful snippets
        "onsails/lspkind.nvim" -- VS Code-like pictograms
    },
    config = function()
        local cmp = require("cmp")
        local luasnip = require("luasnip")
        local lspkind = require("lspkind")

        -- Load friendly-snippets
        require("luasnip.loaders.from_vscode").lazy_load()

        cmp.setup({
            completion = {completeopt = "menu,menuone,preview,noselect"},
            snippet = {
                expand = function(args)
                    luasnip.lsp_expand(args.body)
                end
            },
            mapping = cmp.mapping.preset.insert({
                ["<C-k>"] = cmp.mapping.select_prev_item(), -- Previous suggestion
                ["<C-j>"] = cmp.mapping.select_next_item(), -- Next suggestion
                ["<C-b>"] = cmp.mapping.scroll_docs(-4),
                ["<C-f>"] = cmp.mapping.scroll_docs(4),
                ["<C-Space>"] = cmp.mapping.complete(), -- Show completion suggestions
                ["<C-e>"] = cmp.mapping.abort(), -- Close completion window
                ["<CR>"] = cmp.mapping.confirm({select = false})
            }),
            -- Sources for autocompletion
            sources = cmp.config.sources({
                {name = "nvim_lsp"}, {name = "luasnip"}, -- Snippets
                {name = "buffer"}, -- Text within current buffer
                {name = "path"} -- File system paths
            }),
            -- Configure lspkind for VS Code-like pictograms
            formatting = {
                format = lspkind.cmp_format({
                    maxwidth = 50,
                    ellipsis_char = "..."
                })
            }
        })
    end
}
