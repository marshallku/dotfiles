-- Browser click-to-source into this nvim (tmux or comux pane).
-- Prefer a local clone so unpushed changes are live; zsh points LAUNCH_EDITOR at
-- the same checkout's bin/code-jumper.
local function local_clone()
    for _, path in ipairs({ "~/dev/code-jumper", "~/workspace/code-jumper" }) do
        local dir = vim.fn.expand(path)
        if vim.uv.fs_stat(dir) then
            return dir
        end
    end
    return nil
end

return {
    "marshallku/code-jumper",
    dir = local_clone(),
    cond = function() return not vim.g.vscode end,
    -- Registers on VimEnter; lazy-loading would miss panes opened before first use
    lazy = false,
}
