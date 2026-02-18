local autocmd = vim.api.nvim_create_autocmd
local augroup = vim.api.nvim_create_augroup

-- Highlight on yank
autocmd("TextYankPost", {
	group = augroup("highlight_yank", { clear = true }),
	callback = function()
		vim.highlight.on_yank({ timeout = 200 })
	end,
})

-- Remove trailing whitespace on save
autocmd("BufWritePre", {
	group = augroup("trim_whitespace", { clear = true }),
	pattern = "*",
	command = [[%s/\s\+$//e]],
})

-- Auto-close certain filetypes with q
autocmd("FileType", {
	group = augroup("close_with_q", { clear = true }),
	pattern = { "help", "lspinfo", "man", "qf", "query", "checkhealth" },
	callback = function(event)
		vim.bo[event.buf].buflisted = false
		vim.keymap.set("n", "q", "<cmd>close<CR>", { buffer = event.buf, silent = true })
	end,
})

-- Auto-resize splits when window is resized
autocmd("VimResized", {
	group = augroup("resize_splits", { clear = true }),
	callback = function()
		vim.cmd("tabdo wincmd =")
	end,
})

-- Don't auto-comment new lines
autocmd("BufEnter", {
	group = augroup("no_auto_comment", { clear = true }),
	callback = function()
		vim.opt.formatoptions:remove({ "c", "r", "o" })
	end,
})

-- Markdown: gd to follow links
autocmd("FileType", {
	group = augroup("markdown_gd", { clear = true }),
	pattern = "markdown",
	callback = function(event)
		vim.keymap.set("n", "gd", function()
			local line = vim.api.nvim_get_current_line()
			local col = vim.api.nvim_win_get_cursor(0)[2] + 1

			-- Find markdown link [text](path) under cursor
			local start = 1
			while start <= #line do
				local ls, le, path = line:find("%[.-%]%((.-)%)", start)
				if not ls then
					break
				end
				if col >= ls and col <= le then
					path = path:gsub("#.*$", "")
					if path ~= "" then
						local dir = vim.fn.expand("%:p:h")
						local full = vim.fn.resolve(dir .. "/" .. path)
						if vim.fn.filereadable(full) == 1 then
							vim.cmd("edit " .. vim.fn.fnameescape(full))
						else
							vim.notify("File not found: " .. path, vim.log.levels.WARN)
						end
					end
					return
				end
				start = le + 1
			end

			-- Fallback: try gf (go to file under cursor)
			local ok = pcall(vim.cmd, "normal! gf")
			if not ok then
				vim.notify("No link or file path under cursor", vim.log.levels.WARN)
			end
		end, { buffer = event.buf, desc = "Follow markdown link" })
	end,
})

-- Python format on type (matching Cursor's editor.formatOnType for Python)
autocmd("InsertLeave", {
	group = augroup("python_format_on_type", { clear = true }),
	pattern = "*.py",
	callback = function()
		local conform = require("conform")
		if conform then
			conform.format({ async = false, lsp_fallback = true, timeout_ms = 500 })
		end
	end,
})
