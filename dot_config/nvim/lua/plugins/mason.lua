return {
	{
		"williamboman/mason.nvim",
		config = function()
			require("mason").setup({
				ui = {
					icons = {
						package_installed = "✓",
						package_pending = "➜",
						package_uninstalled = "✗",
					},
				},
				ensure_installed = {
					"prettier",
					"prettierd",
					"stylua",
					"isort",
					"black",
					"goimports",
					"gofumpt",
					"shfmt",
					"clang_format",
				},
				automatic_installation = true,
			})
		end,
	},
	{
		"williamboman/mason-lspconfig.nvim",
		dependencies = { "williamboman/mason.nvim" },
		config = function()
			require("mason-lspconfig").setup({
				ensure_installed = {
					"lua_ls",
					"pyright",
					"ts_ls",
					"gopls",
					"clangd",
					"bashls",
					"html",
					"cssls",
				},
				automatic_installation = true,
			})
		end,
	},
}
