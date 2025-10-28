return {
    "nvim-neo-tree/neo-tree.nvim",
    branch = "v3.x",
    dependencies = {
        "nvim-lua/plenary.nvim", "nvim-tree/nvim-web-devicons",
        "MunifTanjim/nui.nvim"
    },
    config = function()
        require("neo-tree").setup({
            close_if_last_window = true,
            window = {width = 35},
            filesystem = {
                follow_current_file = {enabled = true},
                filtered_items = {
                    visible = false,
                    hide_dotfiles = false,
                    hide_gitignored = false
                }
            }
        })

        vim.keymap.set("n", "<leader>e", "<cmd>Neotree toggle<CR>",
                       {desc = "Toggle file explorer"})
        vim.keymap.set("n", "<leader>ef", "<cmd>Neotree reveal<CR>",
                       {desc = "Reveal current file in explorer"})
    end
}
