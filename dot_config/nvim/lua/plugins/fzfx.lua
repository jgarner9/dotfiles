-- TODO: add some keymaps for fzf

return {
	"linrongbin16/fzfx.nvim",
	event = "VeryLazy",
	cmd = "Fzfx",
	opts = {},
	config = function()
		vim.keymap.set("n", "<leader>ff", "<cmd>FzfxFiles<cr>", { desc = "Fzfx Find Files" })
		vim.keymap.set("n", "<leader>fg", "<cmd>FzfxGrep<cr>", { desc = "Fzfx Grep" })
	end
}
