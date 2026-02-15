return {
    "stevearc/conform.nvim",
    event = {"BufReadPre", "BufNewFile"},
    config = function()
        local conform = require("conform")

        conform.setup({
            formatters_by_ft = {
                javascript = {"prettier"},
                typescript = {"prettier"},
                javascriptreact = {"prettier"},
                typescriptreact = {"prettier"},
                css = {"prettier"},
                scss = {"prettier"},
                html = {"prettier"},
                json = {"prettier"},
                jsonc = {"prettier"},
                yaml = {"prettier"},
                markdown = {"prettier"},
                mdx = {"prettier"},
                graphql = {"prettier"},
                handlebars = {"prettier"},
                dockerfile = {"prettier"},
                nginx = {"prettier"},
                lua = {"stylua"},
                rust = {"rustfmt"},
                go = {"gofumpt"},
                python = {"black"},
                php = {"phpcbf"},
                ["docker-compose"] = {"prettier"},
                ["yaml.docker-compose"] = {"prettier"},
                ["yaml.github-actions"] = {"prettier"}
            },
            format_on_save = {
                lsp_fallback = true,
                async = false,
                timeout_ms = 1000
            }
        })

        vim.keymap.set({"n", "v"}, "<leader>mp", function()
            conform.format(
                {lsp_fallback = true, async = false, timeout_ms = 1000})
        end, {desc = "Format file or range (in visual mode)"})
    end
}
