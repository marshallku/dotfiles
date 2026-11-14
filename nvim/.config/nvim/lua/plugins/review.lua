-- Review annotations on codediff (review.nvim): comment on diff lines, then
-- hand the comments to the Claude Code agent working in the same repository.
-- Agents run in comux panes, outside Neovim; `comux send` types the export
-- into the chosen agent's prompt as one paste and submits it.

-- Claude Code names a project's transcript directory after its launch
-- directory with every non-alphanumeric character turned into "-"
local function project_dir_name(path)
    return (path:gsub("[^%w]", "-"))
end

local function comux_json(args)
    if vim.fn.executable("comux") == 0 then
        return nil
    end
    local result = vim.system(vim.list_extend({ "comux" }, args), { text = true }):wait()
    if result.code ~= 0 then
        return nil
    end
    local ok, data = pcall(vim.json.decode, result.stdout)
    return ok and data or nil
end

-- Agent panes in the tab Neovim is in, when Neovim runs inside comux
local function same_tab_agents()
    local tokens = {}
    local data = comux_json({ "list", "--json" })
    if not data or not vim.env.COPAD_MUX_PANE then
        return tokens
    end
    local here = false
    for _, pane in ipairs(data.panes or {}) do
        here = here or pane.token == vim.env.COPAD_MUX_PANE
    end
    -- `list` shows the focused tab; it is ours only if our pane is in it
    if here then
        for _, pane in ipairs(data.panes or {}) do
            if pane.kind == "agent" then tokens[pane.token] = true end
        end
    end
    return tokens
end

-- The agent's working directory, from the newest transcript entry that has one
local function transcript_cwd(path)
    local file = io.open(path, "rb")
    if not file then
        return nil
    end
    local size = file:seek("end")
    file:seek("set", math.max(0, size - 65536))
    local tail = file:read("*a")
    file:close()
    local lines = vim.split(tail, "\n", { trimempty = true })
    for i = #lines, 1, -1 do
        local ok, entry = pcall(vim.json.decode, lines[i])
        if ok and type(entry) == "table" and type(entry.cwd) == "string" then
            return entry.cwd
        end
    end
    return nil
end

local function git_root(dir)
    local result = vim.system({ "git", "-C", dir, "rev-parse", "--show-toplevel" }, { text = true }):wait()
    return result.code == 0 and vim.trim(result.stdout) or nil
end

-- Claude agents working in this repository, nearest tab first. The transcript
-- directory name is lossy (app and app-tools share the prefix "app-"), so it
-- only narrows the candidates; the agent's own cwd must resolve to this root.
local function claude_agents(root)
    local data = comux_json({ "list-agents", "--json" })
    if not data then
        return nil
    end
    local want = project_dir_name(root)
    local nearby = same_tab_agents()
    local found = {}
    for _, agent in ipairs(data.agents or {}) do
        local dir = agent.transcript_path and vim.fs.basename(vim.fs.dirname(agent.transcript_path))
        local candidate = agent.tool == "claude" and dir and (dir == want or vim.startswith(dir, want .. "-"))
        local cwd = candidate and transcript_cwd(agent.transcript_path)
        if cwd and git_root(cwd) == root then
            agent.nearby = nearby[agent.token] == true
            table.insert(found, agent)
        end
    end
    table.sort(found, function(a, b)
        if a.nearby ~= b.nearby then return a.nearby end
        return (a.for_secs or math.huge) < (b.for_secs or math.huge)
    end)
    return found
end

local function send_to(agent, markdown)
    local result = vim.system({ "comux", "send", agent.token, "--paste", "--enter", "--file", "-" },
        { text = true, stdin = markdown }):wait()
    if result.code ~= 0 then
        vim.notify("Could not send the review: " .. vim.trim(result.stderr) .. " (it is on the clipboard)",
            vim.log.levels.ERROR)
        return
    end
    vim.notify(("Sent the review to Claude in %s %s"):format(agent.space or "", agent.tab_name ~= "" and agent.tab_name or agent.title or ""))
end

local send_pending = false

local function on_export(markdown, comments)
    if not send_pending then
        return
    end
    send_pending = false
    local root = vim.trim(vim.fn.system({ "git", "rev-parse", "--show-toplevel" }))
    local agents = vim.v.shell_error == 0 and claude_agents(root) or nil
    if not agents or #agents == 0 then
        vim.notify("No Claude agent runs in this repository under comux; the review is on the clipboard",
            vim.log.levels.WARN)
        return
    end
    if #agents == 1 then
        send_to(agents[1], markdown)
        return
    end
    vim.ui.select(agents, {
        prompt = "Send the review to",
        format_item = function(agent)
            local where = agent.tab_name ~= "" and agent.tab_name or agent.title or "?"
            return ("%s%s / %s · %s · %s"):format(agent.nearby and "* " or "", agent.space or "?", where,
                agent.status or "?", agent.detail or "")
        end,
    }, function(agent)
        if agent then send_to(agent, markdown) end
    end)
end

return {
    "georgeguimaraes/review.nvim",
    version = "*",
    cond = function() return not vim.g.vscode end,
    dependencies = {
        "esmuellert/codediff.nvim",
        "MunifTanjim/nui.nvim",
    },
    -- Not on a key: notes from earlier sessions show only once it is loaded
    event = "VeryLazy",
    keys = {
        { "<leader>vv", "<cmd>Review<cr>", desc = "Review working tree" },
        { "<leader>vc", "<cmd>Review commits<cr>", desc = "Review commits" },
        { "<leader>vb", "<cmd>Review branch<cr>", desc = "Review branch" },
        -- ":" not <cmd>, so visual mode passes the range
        { "<leader>vn", ":Review note<cr>", mode = { "n", "v" }, desc = "Review: note here" },
        { "<leader>ve", "<cmd>Review edit<cr>", desc = "Review: edit comment" },
        { "<leader>vd", "<cmd>Review delete<cr>", desc = "Review: delete comment" },
        { "<leader>vl", "<cmd>Review list<cr>", desc = "Review: list comments" },
        {
            "<leader>vs",
            function()
                -- :Review close ends with an unconditional :tabclose, so it is
                -- only safe in the review's own codediff tab; elsewhere (notes
                -- on plain files) export without closing anything
                local ok, lifecycle = pcall(require, "codediff.ui.lifecycle")
                local in_review = ok and lifecycle.get_session
                    and lifecycle.get_session(vim.api.nvim_get_current_tabpage()) ~= nil
                send_pending = true
                vim.cmd(in_review and "Review close" or "Review export")
                -- Both export synchronously; on_export clears the flag. Still
                -- set means there were no comments, so nothing was sent.
                if send_pending then
                    send_pending = false
                    vim.notify("No review comments to send", vim.log.levels.WARN)
                end
            end,
            desc = "Review: send to Claude and close",
        },
    },
    opts = {
        export = { on_export = on_export },
    },
}
