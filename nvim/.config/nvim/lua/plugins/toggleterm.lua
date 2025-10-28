return {
    "akinsho/toggleterm.nvim",
    version = "*",
    config = function()
        require("toggleterm").setup({
            size = 20,
            open_mapping = [[<C-\>]],
            hide_numbers = true,
            shade_terminals = true,
            start_in_insert = true,
            insert_mappings = true,
            terminal_mappings = true,
            persist_size = true,
            direction = "float",
            close_on_exit = true,
            shell = vim.o.shell,
            float_opts = {border = "curved"}
        })

        local Terminal = require("toggleterm.terminal").Terminal

        -- Lazygit integration
        local lazygit = Terminal:new({
            cmd = "lazygit",
            dir = "git_dir",
            direction = "float",
            float_opts = {border = "double"},
            on_open = function(term)
                vim.cmd("startinsert!")
                vim.api.nvim_buf_set_keymap(term.bufnr, "n", "q",
                                            "<cmd>close<CR>",
                                            {noremap = true, silent = true})
            end
        })

        function _lazygit_toggle() lazygit:toggle() end

        vim.keymap.set("n", "<leader>gg", "<cmd>lua _lazygit_toggle()<CR>",
                       {desc = "Toggle lazygit"})
    end
}
