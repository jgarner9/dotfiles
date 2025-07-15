return {
	"windwp/nvim-ts-autotag",
	dependencies = "nvim-treesitter/nvim-treesitter",
	ft = { "html", "xml", "javascript", "typescript", "javascriptreact", "typescriptreact" },
	config = function()
		require("nvim-ts-autotag").setup({
			filetypes = {
				"html",
				"xml",
				"javascript",
				"javascriptreact",
				"typescript",
				"typescriptreact"
			}
		})
	end
}
