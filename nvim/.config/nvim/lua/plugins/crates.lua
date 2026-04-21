return {
    "saecki/crates.nvim",
    cond = function() return not vim.g.vscode end,
    event = { "BufRead Cargo.toml" },
    config = function()
        require("crates").setup()
    end,
}
