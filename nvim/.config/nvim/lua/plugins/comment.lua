return {
    "numToStr/Comment.nvim",
    event = {"BufReadPre", "BufNewFile"},
    dependencies = {"JoosepAlviste/nvim-ts-context-commentstring"},
    config = function()
        -- Configure ts-context-commentstring first
        local ok_ts_context, ts_context_commentstring = pcall(require, "ts_context_commentstring")
        if ok_ts_context then
            ts_context_commentstring.setup({
                enable_autocmd = false, -- Disable auto-installation of parsers
            })
        end

        local comment = require("Comment")

        -- Integration with treesitter for JSX/TSX
        local ok, ts_integration = pcall(require,
                                        "ts_context_commentstring.integrations.comment_nvim")

        comment.setup({
            -- Pre-hook for JSX/TSX (only if available)
            pre_hook = ok and ts_integration.create_pre_hook() or nil
        })
    end
}
