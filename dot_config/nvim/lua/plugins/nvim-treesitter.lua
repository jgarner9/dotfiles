return {
	"nvim-treesitter/nvim-treesitter",
	event = { "BufReadPost", "BufNewFile", "BufWritePre" },
	build = ":TSUpdate",
	config = function()
		require("nvim-treesitter.configs").setup({
			ensure_installed = { "tsx", "c", "lua", "vim", "query", "markdown", "markdown_inline", "python", "go", "gomod", "bash", "javascript", "html", "css", "dockerfile", "editorconfig", "gitignore", "json", "make", "php", "ruby", "sql", "typescript", "yaml", "xml" },
			auto_install = true,
			highlight = {
				enable = true
			},
			indent = { enable = true },
		})
	end
}
