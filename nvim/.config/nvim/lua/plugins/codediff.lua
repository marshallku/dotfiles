-- Live review workspace for agent-made changes.
-- Roles: lazygit commits/pushes, diffview shows file history, codediff reviews.

-- Repo of the current buffer, falling back to cwd for non-file buffers or
-- files outside any Git repo.
local function repo_root()
    local bufname = vim.api.nvim_buf_get_name(0)
    local dirs = { vim.uv.cwd() }
    -- Parent dir, not the file itself, so unsaved new files still resolve
    if vim.bo.buftype == "" and bufname ~= "" then
        local parent = vim.fs.dirname(bufname)
        local stat = vim.uv.fs_stat(parent)
        if stat and stat.type == "directory" then
            table.insert(dirs, 1, parent)
        end
    end

    for _, dir in ipairs(dirs) do
        local result = vim.system({ "git", "-C", dir, "rev-parse", "--show-toplevel" }, { text = true }):wait()
        if result.code == 0 then
            return vim.trim(result.stdout)
        end
    end
    return nil
end

local function default_branch(root)
    local function git(...)
        return vim.system({ "git", "-C", root, ... }, { text = true }):wait()
    end

    local head = git("rev-parse", "--abbrev-ref", "origin/HEAD")
    if head.code == 0 then
        return vim.trim(head.stdout)
    end

    for _, ref in ipairs({ "origin/main", "origin/master", "main", "master" }) do
        if git("rev-parse", "--verify", "--quiet", ref).code == 0 then
            return ref
        end
    end
    return nil
end

local function codediff(root, ...)
    vim.cmd({ cmd = "CodeDiff", args = { "--repo", root, ... } })
end

-- Run fn(root) for the current buffer's repo
local function with_repo(fn)
    return function()
        local root = repo_root()
        if not root then
            vim.notify("Not inside a Git repository", vim.log.levels.WARN)
            return
        end
        fn(root)
    end
end

-- Run fn(root, base) where base is the repo's default branch
local function with_default_branch(fn)
    return with_repo(function(root)
        local base = default_branch(root)
        if not base then
            vim.notify("Could not resolve a default branch to compare against", vim.log.levels.WARN)
            return
        end
        fn(root, base)
    end)
end

-- Pick a commit, then review everything after it up to the working tree in one
-- diff ("since I last looked" for commits an agent stacked up)
local function review_since_commit(root)
    local actions = require("telescope.actions")
    local action_state = require("telescope.actions.state")
    require("telescope.builtin").git_commits({
        cwd = root,
        prompt_title = "Review changes after commit",
        attach_mappings = function(prompt_bufnr)
            actions.select_default:replace(function()
                local entry = action_state.get_selected_entry()
                actions.close(prompt_bufnr)
                if entry then
                    codediff(root, entry.value)
                end
            end)
            return true
        end,
    })
end

return {
    "esmuellert/codediff.nvim",
    cond = function() return not vim.g.vscode end,
    cmd = "CodeDiff",
    keys = {
        -- Working tree
        { "<leader>gd", with_repo(function(root) codediff(root) end), desc = "Review working tree changes" },
        { "<leader>gs", with_repo(function(root) codediff(root, "--staged") end), desc = "Review staged changes" },
        { "<leader>gf", "<cmd>CodeDiff file HEAD<cr>", desc = "Diff current file against HEAD" },
        -- Same scope as a PR: merge-base of the default branch vs the working tree
        {
            "<leader>gD",
            with_default_branch(function(root, base) codediff(root, base .. "...") end),
            desc = "Review branch changes (PR scope)",
        },
        -- Commit history
        { "<leader>gl", with_repo(function(root) codediff(root, "history") end), desc = "Review recent commits" },
        {
            "<leader>gL",
            with_default_branch(function(root, base) codediff(root, "history", base .. "..HEAD") end),
            desc = "Review branch commits one by one",
        },
        { "<leader>gc", with_repo(review_since_commit), desc = "Review changes after a picked commit" },
    },
    opts = {
        diff = {
            compact = true,
        },
    },
}
