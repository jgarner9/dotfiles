return {
	"folke/trouble.nvim",
	dependencies = { "nvim-tree/nvim-web-devicons" },
	opts = {},
	cmd = { "Trouble" },
	keys = {
		{ "<leader>xx", "<cmd>Trouble diagnostics<cr>", desc = "Diagnostics (File)" },
	},
}
