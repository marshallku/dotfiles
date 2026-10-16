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

-- Repo shown in the current codediff tab. The session knows it even before any
-- file is open (internal API, so guarded); otherwise read it from the diff
-- buffers' codediff://<root>///<rev>/<path> names.
local function tab_repo_root()
    local ok, lifecycle = pcall(require, "codediff.ui.lifecycle")
    local context = ok and lifecycle.get_git_context and lifecycle.get_git_context(vim.api.nvim_get_current_tabpage())
    if context and context.git_root then
        return context.git_root
    end

    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        local name = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win))
        local root = name:match("^codediff://(.-)///%x+/")
        if root then
            return root
        end
    end
    return nil
end

-- Hash of the commit under the cursor, or of the commit owning the file line
local function history_commit_at_cursor(bufnr)
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, vim.fn.line("."), false)
    for i = #lines, 1, -1 do
        local hash = lines[i]:match("| (%x%x%x%x%x%x%x+) ")
        if hash then
            return hash
        end
    end
    return nil
end

-- Open one commit in its own explorer tab: only its files, nothing else listed
local function open_commit(bufnr)
    local root = tab_repo_root()
    if not root then
        vim.notify("Could not tell which repository this history belongs to", vim.log.levels.WARN)
        return
    end
    local hash = history_commit_at_cursor(bufnr)
    if not hash then
        vim.notify("No commit under the cursor", vim.log.levels.WARN)
        return
    end

    local function git(...)
        return vim.system({ "git", "-C", root, ... }, { text = true }):wait()
    end
    local commit = git("rev-parse", "--verify", "--quiet", hash .. "^{commit}")
    if commit.code ~= 0 then
        vim.notify("Unknown commit " .. hash, vim.log.levels.WARN)
        return
    end
    commit = vim.trim(commit.stdout)

    -- Root commits have no parent; diff against the empty tree instead
    local parent = git("rev-parse", "--verify", "--quiet", commit .. "^")
    if parent.code ~= 0 then
        parent = git("hash-object", "-t", "tree", "/dev/null")
    end
    codediff(root, vim.trim(parent.stdout), commit)
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
    init = function()
        vim.api.nvim_create_autocmd("FileType", {
            pattern = "codediff-history",
            callback = function(event)
                vim.keymap.set("n", "O", function() open_commit(event.buf) end, {
                    buffer = event.buf,
                    nowait = true,
                    desc = "Open commit in its own tab",
                })
            end,
        })
    end,
    opts = {
        diff = {
            compact = true,
        },
    },
}
