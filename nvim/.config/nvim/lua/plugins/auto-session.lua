return {
	"rmagatti/auto-session",
	lazy = false,
	cond = function() return not vim.g.vscode end,
	opts = {
		suppressed_dirs = { "~/", "~/Downloads", "/tmp" },
		auto_restore = true,
		auto_save = true,
		use_git_branch = true,
		bypass_save_filetypes = { "neo-tree" },
		pre_save_cmds = {
			function()
				for _, buf in ipairs(vim.api.nvim_list_bufs()) do
					if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].filetype == "neo-tree" then
						pcall(vim.api.nvim_buf_delete, buf, { force = true })
					end
				end
			end,
		},
	},
}
