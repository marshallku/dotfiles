return {
	"windwp/nvim-autopairs",
	cond = function() return not vim.g.vscode end,
	event = { "InsertEnter" },
	config = function()
		local autopairs = require("nvim-autopairs")

		autopairs.setup({
			check_ts = true, -- Enable treesitter
			ts_config = {
				lua = { "string" }, -- Don't add pairs in lua string treesitter nodes
				javascript = { "template_string" },
				java = false, -- Don't check treesitter on java
			},
		})
	end,
}
