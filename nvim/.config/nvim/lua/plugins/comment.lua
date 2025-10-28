return {
    "numToStr/Comment.nvim",
    event = {"BufReadPre", "BufNewFile"},
    dependencies = {"JoosepAlviste/nvim-ts-context-commentstring"},
    config = function()
        local comment = require("Comment")

        -- Integration with treesitter for JSX/TSX
        local ts_context_commentstring = require(
                                             "ts_context_commentstring.integrations.comment_nvim")

        comment.setup({
            -- Pre-hook for JSX/TSX
            pre_hook = ts_context_commentstring.create_pre_hook()
        })
    end
}
