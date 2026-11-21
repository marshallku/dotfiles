-- @path:line references to code, the form Claude Code reads (@ mentions) and
-- writes back in its replies. Paths are relative to the file's Git root.
local M = {}

-- Git root of dir, or nil outside a repository. No shell, so any path works.
function M.git_root(dir)
    local result = vim.system({ "git", "-C", dir, "rev-parse", "--show-toplevel" }, { text = true }):wait()
    return result.code == 0 and vim.trim(result.stdout) or nil
end

-- Current file's path for a ref, or nil for no file. With base, relative to
-- base when the file is inside it, else absolute (a ref read by an agent
-- running in base); without, relative to the file's Git root (or cwd).
function M.path(base)
    local abs = vim.fn.expand("%:p")
    if abs == "" or vim.bo.buftype ~= "" then
        vim.notify("No file in this buffer", vim.log.levels.WARN)
        return nil
    end
    if base then
        return vim.startswith(abs, base .. "/") and abs:sub(#base + 2) or abs
    end
    local root = M.git_root(vim.fn.expand("%:p:h"))
    if root then
        return abs:sub(#root + 2) -- strip "<root>/"
    end
    return vim.fn.fnamemodify(abs, ":.")
end

-- Visual selection's line range, leaving visual mode
function M.visual_range()
    local s, e = vim.fn.line("v"), vim.fn.line(".")
    if s > e then s, e = e, s end
    vim.cmd("normal! \27")
    return { s, e }
end

-- @path:line for the cursor, or @path:start-end for a range; nil for no file.
-- base as in M.path.
function M.ref(range, base)
    local path = M.path(base)
    if not path then return nil end
    if range then
        return ("@%s:%d-%d"):format(path, range[1], range[2])
    end
    return ("@%s:%d"):format(path, vim.fn.line("."))
end

-- The range's lines as a fenced code block headed by their @path:start-end
function M.block(range, base)
    local head = M.ref(range, base)
    if not head then return nil end
    local block = { head, "```" .. vim.bo.filetype }
    vim.list_extend(block, vim.api.nvim_buf_get_lines(0, range[1] - 1, range[2], false))
    table.insert(block, "```")
    return table.concat(block, "\n") .. "\n"
end

-- Reading refs back: path:line, path:line-end, path:line:col and the
-- path#L42 targets of Markdown links. Candidates are only kept when the path
-- is an existing file, so times ("14:22") and prose never match.
-- A path is any run of characters but whitespace, the ":" and "#" that end
-- it, and the brackets, quotes and separators prose wraps it in
local PATH = "[^%s:#%[%]()<>\"'`|,;]+"
local PATTERNS = {
    "()(" .. PATH .. "):(%d+)()",
    "()(" .. PATH .. ")#L(%d+)()",
}

local function is_file(path)
    local stat = vim.uv.fs_stat(path)
    return stat ~= nil and stat.type == "file"
end

local function resolve(path, dirs)
    path = vim.fs.normalize((path:gsub("^@", ""))) -- an @ mention's @
    if path:sub(1, 1) == "/" then
        return is_file(path) and path or nil
    end
    for _, dir in ipairs(dirs) do
        local full = vim.fs.joinpath(dir, path)
        if is_file(full) then return full end
    end
    return nil
end

-- How far back a path may reach past the delimiters and spaces that end
-- the pattern's match
local MAX_LOOKBACK_SPACES = 4
local MAX_LOOKBACK_BYTES = 200
-- Where a path may start: after one of these, or at the start of the line
local PATH_BOUNDARY = "[%s%[%]()<>\"'`|,;@]"

-- The longest existing file the matched path can be the end of. The pattern
-- stops at spaces, brackets and parens, which real paths can still hold:
-- "src/my file.ts:42", Next.js "app/(auth)/login/page.tsx:42",
-- "app/[id]/page.tsx". So each earlier start after a boundary is tried too,
-- and the longest that exists wins over the bare match (which might name an
-- unrelated file). Returns the file and where its text starts.
local function resolve_widened(line, start, path, dirs)
    local best, best_start = resolve(path, dirs), start
    local spaces = 0
    local floor = math.max(1, start - MAX_LOOKBACK_BYTES)
    for pos = start - 1, floor, -1 do
        local before = pos > 1 and line:sub(pos - 1, pos - 1) or " "
        if before:match(PATH_BOUNDARY) then
            local file = resolve(line:sub(pos, start - 1) .. path, dirs)
            if file then best, best_start = file, pos end
        end
        if line:sub(pos, pos):match("%s") then
            spaces = spaces + 1
            if spaces > MAX_LOOKBACK_SPACES then break end
        end
    end
    return best, best_start
end

-- File refs in one line of text, in order, each with the byte span it covers
-- (start inclusive, stop exclusive); a relative path resolves against the
-- first of dirs that has it
function M.parse(line, dirs)
    local found = {}
    for _, pattern in ipairs(PATTERNS) do
        for start, path, lnum, stop in line:gmatch(pattern) do
            local file
            file, start = resolve_widened(line, start, path, dirs)
            if file then
                table.insert(found, { start = start, stop = stop, file = file, line = tonumber(lnum) })
            end
        end
    end
    table.sort(found, function(a, b) return a.start < b.start end)
    return found
end

return M
