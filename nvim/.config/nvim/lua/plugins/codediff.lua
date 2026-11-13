-- Live review workspace for agent-made changes.
-- Roles: lazygit commits/pushes, codediff reviews (working tree, history).

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

-- Keep the other pane's cursor on the line that corresponds to this one, and
-- its folds open where this pane's are. Native cursorbind can't: codediff
-- aligns panes with filler virtual lines, not diff mode, so cursorbind follows
-- line numbers and drifts after any insertion. Compact mode syncs zo/zc, but a
-- jump (G, search, ]c) opens the fold in the current pane only, which shifts
-- one pane against the other. The line mapping is codediff's own (internal
-- API, so every call is guarded).
local function sync_diff_cursor()
    local ok_life, lifecycle = pcall(require, "codediff.ui.lifecycle")
    local ok_compact, compact = pcall(require, "codediff.ui.view.compact")
    if not (ok_life and ok_compact and lifecycle.get_session and compact.compute_corresponding_lnum) then
        return
    end
    local session = lifecycle.get_session(vim.api.nvim_get_current_tabpage())
    local win = vim.api.nvim_get_current_win()
    -- Inline has one pane. A merge-conflict view's stored diff maps base to
    -- modified, not the ours/theirs panes on screen, so it would mislead.
    if not session or session.layout == "inline" or session.merge or session.result_win then
        return
    end
    local panes = {
        { win = session.original_win, side = "original" },
        { win = session.modified_win, side = "modified" },
    }
    local from, to
    for i, pane in ipairs(panes) do
        if pane.win == win then
            from, to = pane, panes[3 - i]
        end
    end
    local changes = session.stored_diff_result and session.stored_diff_result.changes
    if not from or not changes or not (to.win and vim.api.nvim_win_is_valid(to.win)) then
        return
    end

    local lnum = vim.api.nvim_win_get_cursor(win)[1]
    local open_here = vim.fn.foldclosed(lnum) == -1
    local target = compact.compute_corresponding_lnum(changes, from.side, to.side, lnum)
    target = math.max(1, math.min(target, vim.api.nvim_buf_line_count(vim.api.nvim_win_get_buf(to.win))))
    vim.api.nvim_win_call(to.win, function()
        pcall(vim.api.nvim_win_set_cursor, to.win, { target, 0 })
        if open_here then
            vim.cmd("silent! normal! zv")
        end
    end)
    -- Opening a fold changes the partner's height above the cursor; re-align
    vim.cmd("syncbind")
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
        { "<leader>gh", "<cmd>CodeDiff history %<cr>", desc = "File history" },
    },
    init = function()
        vim.api.nvim_create_autocmd("CursorMoved", {
            group = vim.api.nvim_create_augroup("codediff_cursor_sync", { clear = true }),
            callback = function() vim.schedule(sync_diff_cursor) end,
        })
        -- :q in a diff pane or the explorer closes the whole codediff tab, like
        -- its `q`, instead of one window at a time. :q still closes this window
        -- first; the scheduled close (queued before codediff's own WinClosed
        -- cleanup) then takes the rest of the tab.
        vim.api.nvim_create_autocmd("QuitPre", {
            group = vim.api.nvim_create_augroup("codediff_quit_tab", { clear = true }),
            callback = function()
                local ok, lifecycle = pcall(require, "codediff.ui.lifecycle")
                local tab = vim.api.nvim_get_current_tabpage()
                local session = ok and lifecycle.get_session and lifecycle.get_session(tab)
                if not session or #vim.api.nvim_list_tabpages() < 2 then
                    return -- the last tab: let :q quit as usual
                end
                local win = vim.api.nvim_get_current_win()
                local panel = session.panel and session.panel.view and session.panel.view.winid
                if win ~= session.original_win and win ~= session.modified_win
                    and win ~= session.result_win and win ~= panel then
                    return -- some other window in the tab, e.g. :help
                end
                vim.schedule(function()
                    if vim.api.nvim_tabpage_is_valid(tab) then
                        lifecycle.close(tab)
                    end
                end)
            end,
        })
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
