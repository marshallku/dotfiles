-- Claude Code IDE bridge: implements the same WebSocket+MCP protocol the
-- Cursor VSC extension uses, so `claude` running in the embedded terminal
-- sees the buffer/selection/diagnostics in real time.
-- Native terminal provider (no snacks dep) — the repo already has toggleterm.
return {
    "coder/claudecode.nvim",
    cond = function() return not vim.g.vscode end,
    cmd = {
        "ClaudeCode",
        "ClaudeCodeFocus",
        "ClaudeCodeOpen",
        "ClaudeCodeSend",
        "ClaudeCodeAdd",
        "ClaudeCodeDiffAccept",
        "ClaudeCodeDiffDeny",
    },
    keys = {
        { "<leader>cc", "<cmd>ClaudeCode<cr>", desc = "Toggle Claude Code" },
        -- Terminal-mode-friendly toggle: leader keys don't fire while focused
        -- inside the Claude terminal buffer. Alt+c works reliably across
        -- ghostty/kitty on Linux. On macOS Terminal.app, set the terminal's
        -- option-as-meta setting (ghostty.app: `macos-option-as-alt = true`).
        { "<M-c>", "<cmd>ClaudeCode<cr>", mode = { "n", "t" }, desc = "Toggle Claude Code" },
        { "<leader>cf", "<cmd>ClaudeCodeFocus<cr>", desc = "Focus Claude Code" },
        { "<leader>cs", "<cmd>ClaudeCodeSend<cr>", mode = "v", desc = "Send selection to Claude" },
        { "<leader>cb", "<cmd>ClaudeCodeAdd %<cr>", desc = "Add buffer to Claude" },
        { "<leader>cda", "<cmd>ClaudeCodeDiffAccept<cr>", desc = "Accept Claude diff" },
        { "<leader>cdd", "<cmd>ClaudeCodeDiffDeny<cr>", desc = "Deny Claude diff" },
    },
    opts = function()
        -- Prefer PATH discovery; fall back to common local install dirs only if
        -- nothing is on PATH. Avoids hardcoding a single install layout.
        local cmd = vim.fn.exepath("claude")
        if cmd == "" then
            for _, candidate in ipairs({ "~/.claude/local/claude", "~/.local/bin/claude" }) do
                local expanded = vim.fn.expand(candidate)
                if vim.uv.fs_stat(expanded) then
                    cmd = expanded
                    break
                end
            end
        end
        -- Auto-enable --dangerously-skip-permissions: this nvim instance is
        -- already a trusted, interactive editing session, so the per-tool
        -- permission prompts add friction without buying meaningful safety.
        local terminal_cmd = nil
        if cmd ~= "" then
            terminal_cmd = cmd .. " --dangerously-skip-permissions"
        end
        return {
            terminal_cmd = terminal_cmd,
            terminal = { provider = "native" },
        }
    end,
}
