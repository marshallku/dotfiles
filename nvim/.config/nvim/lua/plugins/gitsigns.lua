return {
    "lewis6991/gitsigns.nvim",
    cond = function() return not vim.g.vscode end,
    event = {"BufReadPre", "BufNewFile"},
    config = function()
        require("gitsigns").setup({
            signs = {
                add = {text = "│"},
                change = {text = "│"},
                delete = {text = "_"},
                topdelete = {text = "‾"},
                changedelete = {text = "~"},
                untracked = {text = "┆"}
            },
            current_line_blame = true,
            current_line_blame_opts = {
                virt_text = true,
                virt_text_pos = "eol",
                delay = 300,
                ignore_whitespace = false,
            },
            current_line_blame_formatter = function(_, blame_info)
                if not blame_info.author or blame_info.author == "Not Committed Yet" then
                    return {{"  uncommitted", "GitSignsCurrentLineBlame"}}
                end
                local ts = tonumber(blame_info["author_time"]) or 0
                local diff = os.time() - ts
                local rel
                if diff < 60 then rel = diff .. "s ago"
                elseif diff < 3600 then rel = math.floor(diff / 60) .. "m ago"
                elseif diff < 86400 then rel = math.floor(diff / 3600) .. "h ago"
                elseif diff < 86400 * 30 then rel = math.floor(diff / 86400) .. "d ago"
                elseif diff < 86400 * 365 then rel = math.floor(diff / (86400 * 30)) .. "mo ago"
                else rel = math.floor(diff / (86400 * 365)) .. "y ago"
                end
                local text = string.format("  %s, %s · %s", blame_info.author, rel, blame_info.summary or "")
                return {{text, "GitSignsCurrentLineBlame"}}
            end,
            on_attach = function(bufnr)
                local gs = package.loaded.gitsigns

                local function map(mode, l, r, opts)
                    opts = opts or {}
                    opts.buffer = bufnr
                    vim.keymap.set(mode, l, r, opts)
                end

                -- Navigation
                map("n", "]h", function()
                    if vim.wo.diff then return "]c" end
                    vim.schedule(function() gs.next_hunk() end)
                    return "<Ignore>"
                end, {expr = true, desc = "Next git hunk"})

                map("n", "[h", function()
                    if vim.wo.diff then return "[c" end
                    vim.schedule(function() gs.prev_hunk() end)
                    return "<Ignore>"
                end, {expr = true, desc = "Previous git hunk"})

                -- Actions
                map("n", "<leader>hs", gs.stage_hunk, {desc = "Stage hunk"})
                map("n", "<leader>hr", gs.reset_hunk, {desc = "Reset hunk"})
                map("v", "<leader>hs", function()
                    gs.stage_hunk({vim.fn.line("."), vim.fn.line("v")})
                end, {desc = "Stage hunk"})
                map("v", "<leader>hr", function()
                    gs.reset_hunk({vim.fn.line("."), vim.fn.line("v")})
                end, {desc = "Reset hunk"})
                map("n", "<leader>hS", gs.stage_buffer, {desc = "Stage buffer"})
                map("n", "<leader>hu", gs.undo_stage_hunk,
                    {desc = "Undo stage hunk"})
                map("n", "<leader>hR", gs.reset_buffer, {desc = "Reset buffer"})
                map("n", "<leader>hp", gs.preview_hunk, {desc = "Preview hunk"})
                map("n", "<leader>hb",
                    function() gs.blame_line({full = true}) end,
                    {desc = "Blame line (full)"})
                map("n", "<leader>gB", "<cmd>Gitsigns blame<cr>",
                    {desc = "Blame buffer"})
                map("n", "<leader>tb", gs.toggle_current_line_blame,
                    {desc = "Toggle inline blame"})
                map("n", "<leader>hd", gs.diffthis, {desc = "Diff this"})
            end
        })
    end
}
