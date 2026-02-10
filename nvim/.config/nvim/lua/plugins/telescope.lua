return {
    "nvim-telescope/telescope.nvim",
    branch = "0.1.x",
    dependencies = {
        "nvim-lua/plenary.nvim",
        {"nvim-telescope/telescope-fzf-native.nvim", build = "make"},
        "nvim-tree/nvim-web-devicons"
    },
    config = function()
        local telescope = require("telescope")
        local actions = require("telescope.actions")

        telescope.setup({
            defaults = {
                path_display = {"truncate"},
                mappings = {
                    i = {
                        ["<C-k>"] = actions.move_selection_previous,
                        ["<C-j>"] = actions.move_selection_next,
                        ["<C-q>"] = actions.send_selected_to_qflist +
                            actions.open_qflist
                    }
                }
            },
            pickers = {
                find_files = {
                    hidden = true,
                },
                live_grep = {
                    additional_args = { "--hidden" },
                },
                grep_string = {
                    additional_args = { "--hidden" },
                },
            },
        })

        telescope.load_extension("fzf")

        -- Keymaps
        local keymap = vim.keymap
        keymap.set("n", "<leader>ff", "<cmd>Telescope find_files<cr>",
                   {desc = "Find files"})
        keymap.set("n", "<leader>fr", "<cmd>Telescope oldfiles<cr>",
                   {desc = "Recent files"})
        keymap.set("n", "<leader>fg", "<cmd>Telescope live_grep<cr>",
                   {desc = "Find text"})
        keymap.set("n", "<leader>fc", "<cmd>Telescope grep_string<cr>",
                   {desc = "Find string under cursor"})
        keymap.set("n", "<leader>fb", "<cmd>Telescope buffers<cr>",
                   {desc = "Find buffers"})
        keymap.set("n", "<leader>fh", "<cmd>Telescope help_tags<cr>",
                   {desc = "Help tags"})
    end
}
