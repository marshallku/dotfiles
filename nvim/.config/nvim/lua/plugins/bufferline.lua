return {
    "akinsho/bufferline.nvim",
    dependencies = {"nvim-tree/nvim-web-devicons"},
    version = "*",
    config = function()
        require("bufferline").setup({
            options = {
                mode = "buffers",
                separator_style = "slant",
                always_show_bufferline = false,
                diagnostics = "nvim_lsp",
                offsets = {
                    {
                        filetype = "neo-tree",
                        text = "File Explorer",
                        highlight = "Directory",
                        text_align = "left"
                    }
                }
            }
        })
    end
}
