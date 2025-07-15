return {

	-- LSP Configuration
	{
		"neovim/nvim-lspconfig",
		dependencies = {
			"williamboman/mason.nvim",
			"williamboman/mason-lspconfig.nvim",
		},
		config = function()
			local lspconfig = require("lspconfig")

			-- Get capabilities from blink-cmp
			local capabilities = require('blink.cmp').get_lsp_capabilities()

			-- Common on_attach function
			local on_attach = function(client, bufnr)
				-- Disable LSP formatting (assuming you're using conform)
				client.server_capabilities.documentFormattingProvider = false
				client.server_capabilities.documentRangeFormattingProvider = false

				-- Key mappings
				local opts = { noremap = true, silent = true, buffer = bufnr }
				vim.keymap.set("n", "gp", "<cmd>Lspsaga peek_definition<CR>", opts)
				vim.keymap.set("n", "gd", "<cmd>Lspsaga goto_definition<CR>", opts)
				vim.keymap.set("n", "gt", "<cmd>Lspsaga peek_type_definition<CR>", opts)
				vim.keymap.set("n", "gT", "<cmd>Lspsaga goto_type_definition<CR>", opts)
			end

			-- Setup mason-lspconfig handlers
			require("mason-lspconfig").setup({
				-- Default handler for all servers
				function(server_name)
					lspconfig[server_name].setup({
						on_attach = on_attach,
						capabilities = capabilities,
					})
				end,

				-- Lua specific configuration
				["lua_ls"] = function()
					lspconfig.lua_ls.setup({
						on_attach = on_attach,
						capabilities = capabilities,
						settings = {
							Lua = {
								runtime = { version = "LuaJIT" },
								diagnostics = { globals = { "vim" } },
								workspace = {
									library = vim.api.nvim_get_runtime_file("", true),
									checkThirdParty = false,
								},
								telemetry = { enable = false },
								format = { enable = true },
							},
						},
					})
				end,

				-- Python specific configuration
				["pyright"] = function()
					lspconfig.pyright.setup({
						on_attach = on_attach,
						capabilities = capabilities,
						settings = {
							python = {
								analysis = {
									typeCheckingMode = "basic",
									autoSearchPaths = true,
									useLibraryCodeForTypes = true,
								},
							},
						},
					})
				end,

				-- TypeScript specific configuration
				["ts_ls"] = function()
					lspconfig.ts_ls.setup({
						on_attach = on_attach,
						capabilities = capabilities,
						settings = {
							typescript = {
								preferences = {
									disableSuggestions = true,
								},
							},
						},
					})
				end,

				-- Go specific configuration
				["gopls"] = function()
					lspconfig.gopls.setup({
						on_attach = on_attach,
						capabilities = capabilities,
						settings = {
							gopls = {
								analyses = {
									unusedparams = true,
								},
								staticcheck = true,
								gofumpt = true,
							},
						},
					})
				end,

				-- C/C++ specific configuration
				["clangd"] = function()
					lspconfig.clangd.setup({
						on_attach = on_attach,
						capabilities = capabilities,
						cmd = {
							"clangd",
							"--background-index",
							"--clang-tidy",
							"--header-insertion=iwyu",
							"--completion-style=detailed",
							"--function-arg-placeholders",
						},
					})
				end,

				-- Bash specific configuration
				["bashls"] = function()
					lspconfig.bashls.setup({
						on_attach = on_attach,
						capabilities = capabilities,
					})
				end,

				--HTML specific configuration
				["html"] = function()
					lspconfig.html.setup({
						on_attach = on_attach,
						capabilities = capabilities
					})
				end,

				--CSS specific configuration
				["cssls"] = function()
					lspconfig.cssls.setup({
						on_attach = on_attach,
						capabilities = capabilities
					})
				end
			})

			-- Global LSP settings
			vim.diagnostic.config({
				virtual_text = true,
				signs = true,
				underline = true,
				update_in_insert = false,
				severity_sort = false,
			})

			-- LSP diagnostic signs
			local signs = { Error = "󰅚 ", Warn = "󰀪 ", Hint = "󰌶 ", Info = " " }
			for type, icon in pairs(signs) do
				local hl = "DiagnosticSign" .. type
				vim.fn.sign_define(hl, { text = icon, texthl = hl, numhl = hl })
			end
		end,
	},
}
