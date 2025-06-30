return {
	"nvim-treesitter/nvim-treesitter",
	event = { "BufReadPost", "BufNewFile" },
	opts = {
		branch = "master",
		lazy = false,
		build = ":TSInstall",
		opts = {
			ensure_installed = { "c", "lua", "vim", "query", "markdown", "markdown_inline", "python", "go", "gomod", "bash", "javascript" },
			auto_install = true,
			highlight = {
				enable = true
			},
			indent = { enable = true }
		}
	}
}
