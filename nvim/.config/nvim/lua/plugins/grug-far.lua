-- Project-wide find and replace (VS Code's search panel): a buffer with the
-- search, replacement, flags and file filter on top and the live ripgrep
-- results below; edit result lines to change them in place.
local function open(prefills)
    require("grug-far").open({ prefills = prefills })
end

return {
    "MagicDuck/grug-far.nvim",
    cond = function() return not vim.g.vscode end,
    cmd = "GrugFar",
    keys = {
        {
            "<leader>fR",
            function() open({ search = vim.fn.expand("<cword>") }) end,
            desc = "Find and replace in project",
        },
        {
            "<leader>fR",
            function() require("grug-far").with_visual_selection() end,
            mode = "x",
            desc = "Find and replace the selection in project",
        },
        {
            "<leader>fF",
            function()
                -- grug-far splits paths on spaces unless they are escaped
                open({ search = vim.fn.expand("<cword>"), paths = (vim.fn.expand("%"):gsub(" ", "\\ ")) })
            end,
            desc = "Find and replace in this file",
        },
    },
    opts = {},
}
