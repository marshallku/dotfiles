return {
	"rmagatti/auto-session",
	lazy = false,
	cond = function() return not vim.g.vscode end,
	opts = {
		suppressed_dirs = { "~/", "~/Downloads", "/tmp" },
		auto_restore = true,
		auto_save = true,
		use_git_branch = true,
	},
}
