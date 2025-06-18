return {
	"neovim/nvim-lspconfig",
	event = "BufReadPost",
	dependencies = {
		{ "saghen/blink.cmp" },
		{ "williamboman/mason.nvim",          config = true },
		{ "williamboman/mason-lspconfig.nvim" },
	},

	config = function()
		local servers = { "lua_ls", "pyright", "ts_ls", "gopls", "clangd", "bashls" }
		local serverFileTypes = { "lua", "py", "js", "go", "c", "sh" }

		require("mason").setup()
		require("mason-lspconfig").setup({
			ensure_installed = servers,
			automatic_installation = true,
			automatic_enable = false,
		})

		local lspconfig = require("lspconfig")

		for i, server in ipairs(servers) do
			lspconfig[server].setup({
				filetypes = { serverFileTypes[i] }
			})
		end
	end,
}
