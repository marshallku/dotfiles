return {
    "akinsho/toggleterm.nvim",
    cond = function() return not vim.g.vscode end,
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

        -- Called by lazygit's `e` (~/.config/lazygit/config.yml) through
        -- `nvim --server $NVIM --remote-expr`. The shell writes "<path>\n<line>"
        -- pairs, one per selected file, to <servername>.lazygit-edit, so no path
        -- has to be quoted into an expression. Hide lazygit (it keeps running,
        -- <leader>gg brings it back where it was) and open the first file in the
        -- window it covered, instead of the preset's new tab; the rest join the
        -- buffer list.
        function LazygitEdit()
            local request = vim.v.servername .. ".lazygit-edit"
            local lines = vim.fn.filereadable(request) == 1 and vim.fn.readfile(request) or {}
            os.remove(request)
            local files = {}
            for i = 1, #lines - 1, 2 do
                if lines[i] ~= "" then
                    table.insert(files, { path = lines[i], line = tonumber(lines[i + 1]) or 0 })
                end
            end
            if #files == 0 then
                return "no request"
            end
            vim.schedule(function()
                if lazygit:is_open() then lazygit:close() end
                for i = #files, 2, -1 do
                    vim.cmd.badd(vim.fn.fnameescape(files[i].path))
                end
                vim.cmd.edit(vim.fn.fnameescape(files[1].path))
                if files[1].line > 0 then
                    pcall(vim.api.nvim_win_set_cursor, 0, { files[1].line, 0 })
                    vim.cmd("normal! zz")
                end
                if #files > 1 then
                    vim.notify(("Opened %d files from lazygit (buffers)"):format(#files))
                end
            end)
            return "ok"
        end

        -- Bottom split terminal beside the code (VS Code panel). Hidden, so
        -- <C-\> keeps toggling only the floating one.
        local split = Terminal:new({ direction = "horizontal", hidden = true })
        vim.keymap.set({ "n", "t" }, "<M-\\>", function()
            split:toggle(math.floor(vim.o.lines * 0.3))
        end, { desc = "Toggle split terminal" })

        vim.keymap.set("n", "<leader>gg", "<cmd>lua _lazygit_toggle()<CR>",
                       {desc = "Toggle lazygit"})
    end
}
