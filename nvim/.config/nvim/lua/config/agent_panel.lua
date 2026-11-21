-- A terminal side panel beside the code for an agent CLI (claude, codex, or
-- anything else run in it): hand it @path:line refs and code blocks from the
-- buffer while writing, and jump from the file refs in its replies back into
-- the code. It is a plain shell, so nothing here depends on one agent: refs go
-- in as a paste, and refs coming out are read from the terminal's text. One
-- panel per Neovim, its shell started in the Git root of the file it was first
-- opened from, so @paths resolve there.
local ref = require("config.ref")

local M = {}

-- Width as a share of the columns, so the panel follows the screen size.
-- Resizing the panel by hand (keys, mouse) sets a new share.
local DEFAULT_SHARE = 0.4
local MIN_PANEL = 30 -- columns the panel keeps on a narrow screen
local MIN_CODE = 60 -- columns the code keeps before the panel gives way
local RESIZE_STEP = 5
local SCAN_LINES = 500 -- panel output searched for refs, newest first
local PICK_LIMIT = 30
-- Text sent before the shell is up is lost, so a new panel waits until its
-- screen stops changing
local READY_POLL_MS = 100
local READY_QUIET_MS = 600
local READY_TIMEOUT_MS = 8000

local term -- the panel's toggleterm Terminal
local ready = false

local share = DEFAULT_SHARE

-- A panel width within the minimums for this screen size
local function clamp(w)
    local columns = vim.o.columns
    local low = math.min(MIN_PANEL, math.floor(columns / 2))
    local high = math.max(low, columns - MIN_CODE - 1) -- 1: the window separator
    return math.max(low, math.min(w, high))
end

local function width()
    return clamp(math.floor(vim.o.columns * share))
end

local function running()
    return term ~= nil and term.job_id ~= nil and vim.api.nvim_buf_is_valid(term.bufnr or -1)
end

-- Run fn once the shell is up
local function when_ready(fn)
    if ready then return fn() end
    local tick, quiet, waited = -1, 0, 0
    local timer = vim.uv.new_timer()
    timer:start(READY_POLL_MS, READY_POLL_MS, vim.schedule_wrap(function()
        waited = waited + READY_POLL_MS
        if not running() then
            timer:close()
            return
        end
        local now = vim.api.nvim_buf_get_changedtick(term.bufnr)
        quiet = (now == tick and now > 2) and quiet + READY_POLL_MS or 0
        tick = now
        if quiet >= READY_QUIET_MS or waited >= READY_TIMEOUT_MS then
            timer:close()
            ready = true
            fn()
        end
    end))
end

-- Window to open a ref in: the current one if it shows a file, else the one
-- used before the panel, else any file window in this tab; nil if none
local function code_window()
    local function usable(win)
        if win == 0 or not vim.api.nvim_win_is_valid(win) then return false end
        if vim.api.nvim_win_get_config(win).relative ~= "" then return false end
        return vim.bo[vim.api.nvim_win_get_buf(win)].buftype == ""
    end
    for _, win in ipairs({ vim.api.nvim_get_current_win(), vim.fn.win_getid(vim.fn.winnr("#")) }) do
        if usable(win) then return win end
    end
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if usable(win) then return win end
    end
    return nil
end

local function open_ref(found)
    local win = code_window()
    if win then
        vim.api.nvim_set_current_win(win)
    else
        vim.cmd("aboveleft vnew")
    end
    vim.cmd.edit(vim.fn.fnameescape(found.file))
    pcall(vim.api.nvim_win_set_cursor, 0, { found.line, 0 })
    vim.cmd("normal! zvzz")
end

local function panel_dir()
    return term and term.dir or vim.uv.cwd()
end

-- The agent writes paths relative to its own directory; others may be relative
-- to Neovim's
local function ref_dirs()
    return { panel_dir(), vim.uv.cwd() }
end

-- Terminal-normal mode in the panel: open the ref under the cursor, or the
-- first one on the line
local function jump_at_cursor()
    local refs = ref.parse(vim.api.nvim_get_current_line(), ref_dirs())
    if #refs == 0 then
        vim.notify("No file reference on this line", vim.log.levels.WARN)
        return
    end
    local col = vim.api.nvim_win_get_cursor(0)[2] + 1
    local pick = refs[1]
    for _, found in ipairs(refs) do
        if col >= found.start and col < found.stop then pick = found end
    end
    open_ref(pick)
end

-- File refs in the panel's recent output, newest first, without repeats
local function recent_refs()
    local count = vim.api.nvim_buf_line_count(term.bufnr)
    local lines = vim.api.nvim_buf_get_lines(term.bufnr, math.max(0, count - SCAN_LINES), -1, false)
    local seen, list = {}, {}
    for i = #lines, 1, -1 do
        local on_line = ref.parse(lines[i], ref_dirs())
        for j = #on_line, 1, -1 do
            local found = on_line[j]
            local key = found.file .. ":" .. found.line
            if not seen[key] then
                seen[key] = true
                table.insert(list, found)
                if #list >= PICK_LIMIT then return list end
            end
        end
    end
    return list
end

local function panel_win()
    return term and term:is_open() and term.window or nil
end

local function resize(delta)
    local win = panel_win()
    if win then vim.api.nvim_win_set_width(win, clamp(vim.api.nvim_win_get_width(win) + delta)) end
end

local function on_open(t)
    local opts = { buffer = t.bufnr, silent = true }
    -- From inside the panel; in normal mode <C-Left>/<C-Right> work as anywhere
    vim.keymap.set("t", "<M-,>", function() resize(RESIZE_STEP) end,
        vim.tbl_extend("force", opts, { desc = "Widen the panel" }))
    vim.keymap.set("t", "<M-.>", function() resize(-RESIZE_STEP) end,
        vim.tbl_extend("force", opts, { desc = "Narrow the panel" }))
    for _, key in ipairs({ "gd", "gf", "<CR>" }) do
        vim.keymap.set("n", key, jump_at_cursor, vim.tbl_extend("force", opts, { desc = "Open the file ref here" }))
    end
    -- toggleterm maps a bare <C-\> in terminals, which hides Vim's own way
    -- out of terminal mode; this longer mapping wins when typed in full
    vim.keymap.set("t", "<C-\\><C-n>", "<C-\\><C-n>", vim.tbl_extend("force", opts, { desc = "Terminal normal mode" }))
    -- Going over (<C-w>l, <C-l>, a click) is to type to the agent; reading
    -- its output with gd is the exception, one <C-\><C-n> away
    -- on_open runs on every show; one autocmd, not one per show
    vim.api.nvim_create_autocmd("BufEnter", {
        group = vim.api.nvim_create_augroup("agent_panel_enter", { clear = true }),
        buffer = t.bufnr,
        callback = function()
            vim.schedule(function()
                -- deliver() opens the panel and steps straight back to the
                -- code; only start insert if we are still in the panel
                if vim.api.nvim_get_current_buf() == t.bufnr then vim.cmd("startinsert") end
            end)
        end,
    })
    vim.cmd("startinsert!")
end

local function ensure()
    if term then return term end
    local here = vim.bo.buftype == "" and vim.fn.expand("%:p:h") or ""
    local dir = (here ~= "" and ref.git_root(here)) or ref.git_root(vim.uv.cwd()) or vim.uv.cwd()
    local Terminal = require("toggleterm.terminal").Terminal
    term = Terminal:new({
        dir = dir, -- no cmd: the user's shell
        direction = "vertical",
        hidden = true, -- keep <C-\> for the floating shell
        display_name = "Agent",
        on_open = on_open,
        on_exit = function() ready = false end,
    })
    return term
end

function M.toggle()
    ensure():toggle(width())
end

-- Paste text into whatever runs in the panel, without submitting it, and
-- stay in the code: collect a few refs, then go over (<M-l>) to write the
-- message. Bracketed paste keeps an @ from opening an agent's file picker and
-- newlines from sending the message early.
local function deliver(text, label)
    if not text then return end
    local t = ensure()
    if not t:is_open() then
        local code = vim.api.nvim_get_current_win()
        t:open(width())
        if vim.api.nvim_win_is_valid(code) then
            vim.api.nvim_set_current_win(code)
            vim.cmd("stopinsert")
        end
    end
    when_ready(function()
        vim.api.nvim_chan_send(t.job_id, "\27[200~" .. text .. "\27[201~")
        vim.notify("Agent panel ← " .. label)
    end)
end

-- Refs are relative to the panel's directory, where the agent runs, even
-- when the file is in another repository (then absolute)
function M.send_ref(range)
    local text = ref.ref(range, ensure().dir)
    deliver(text and text .. " ", text)
end

function M.send_block(range)
    local text = ref.block(range, ensure().dir)
    deliver(text, text and text:match("^(%S+)") .. " (code)")
end

-- Pick one of the file refs in the panel's recent output and open it
function M.pick()
    if not running() then
        vim.notify("The agent panel is not running", vim.log.levels.WARN)
        return
    end
    local list = recent_refs()
    if #list == 0 then
        vim.notify("No file references in the agent panel", vim.log.levels.WARN)
        return
    end
    local dir = panel_dir()
    vim.ui.select(list, {
        prompt = "Open from the agent panel",
        format_item = function(found)
            local shown = vim.startswith(found.file, dir .. "/") and found.file:sub(#dir + 2) or found.file
            return ("%s:%d"):format(shown, found.line)
        end,
    }, function(found)
        if found then open_ref(found) end
    end)
end

function M.setup()
    local group = vim.api.nvim_create_augroup("agent_panel_width", { clear = true })
    -- Screen size changed: back to the share, within the minimums
    vim.api.nvim_create_autocmd("VimResized", {
        group = group,
        callback = function()
            local win = panel_win()
            if win then vim.api.nvim_win_set_width(win, width()) end
        end,
    })
    -- Panel resized by hand (drag, <C-Left>): hold it within the minimums,
    -- then remember the new share. Widths this module set equal width() and
    -- are skipped, so a clamp on a small screen doesn't shrink the share for
    -- when the screen grows again.
    vim.api.nvim_create_autocmd("WinResized", {
        group = group,
        callback = function()
            local win = panel_win()
            if not win or not vim.tbl_contains(vim.v.event.windows, win) then return end
            local w = vim.api.nvim_win_get_width(win)
            if w ~= clamp(w) then
                vim.api.nvim_win_set_width(win, clamp(w))
                w = clamp(w)
            end
            if w ~= width() then share = w / vim.o.columns end
        end,
    })

    local map = vim.keymap.set
    map({ "n", "t" }, "<M-a>", M.toggle, { desc = "Toggle agent panel" })
    map("n", "<leader>aa", M.toggle, { desc = "Toggle agent panel" })
    map("n", "<leader>ar", function() M.send_ref(nil) end, { desc = "Send @path:line to the agent panel" })
    map("x", "<leader>ar", function() M.send_ref(ref.visual_range()) end, { desc = "Send @path:start-end to the agent panel" })
    map("x", "<leader>ac", function() M.send_block(ref.visual_range()) end, { desc = "Send selection to the agent panel" })
    map("n", "<leader>aj", M.pick, { desc = "Open a file ref from the agent panel" })
end

return M
