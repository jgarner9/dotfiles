return {
	"stevearc/conform.nvim",
	event = { "BufWritePre" },
	cmd = { "ConformInfo" },
	keys = {
		{
			"<leader>f",
			function()
				require("conform").format({ async = true })
			end,
			mode = "",
			desc = "Format buffer",
		},
		{
			"<leader>F",
			function()
				require("conform").format({
					async = true,
					formatters = { "injected" }
				})
			end,
			mode = "",
			desc = "Format injected languages",
		},
	},
	config = function()
		require("conform").setup({
			formatters_by_ft = {
				lua = { "stylua" },
				python = { "isort", "black" }, -- Run isort first, then black
				javascript = { "prettierd", "prettier" }, -- Use prettierd if available, fallback to prettier
				typescript = { "prettierd", "prettier" },
				javascriptreact = { "prettierd", "prettier" },
				typescriptreact = { "prettierd", "prettier" },
				json = { "prettier" },
				html = { "prettier" },
				css = { "prettier" },
				scss = { "prettier" },
				markdown = { "prettier" },
				yaml = { "prettier" },
				go = { "goimports", "gofmt" }, -- goimports includes gofmt
				c = { "clang_format" },
				cpp = { "clang_format" },
				sh = { "shfmt" },
				bash = { "shfmt" },
				-- You can also use "*" to run formatters on any filetype
				["*"] = { "codespell" }, -- Spell checker
				-- Use "_" to run formatters on filetypes that don't have other formatters
				["_"] = { "trim_whitespace" },
			},
			-- Format on save with conditions
			format_on_save = function(bufnr)
				-- Disable format on save for specific file types
				local disable_filetypes = {}
				if disable_filetypes[vim.bo[bufnr].filetype] then
					return
				end
				return {
					timeout_ms = 500,
					lsp_fallback = true,
				}
			end,
			-- Custom formatters
			formatters = {
				shfmt = {
					prepend_args = { "-i", "2", "-ci" }, -- 2 space indent, switch cases indent
				},
				prettier = {
					prepend_args = { "--tab-width", "2" },
				},
			},
		})

		-- Optional: Show notification when formatting
		vim.api.nvim_create_autocmd("User", {
			pattern = "FormatterPost",
			callback = function()
				vim.notify("Formatted with " .. vim.v.event.data.formatter_name)
			end,
		})
	end,
}
