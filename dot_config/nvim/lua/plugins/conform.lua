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
	},
	---@module "conform"
	---@type conform.setupOpts
	opts = {
		formatters_by_ft = {
			c = { "clang-format" },
			cmake = { "cmake_format" },
			go = { "gofmt" },
			lua = { "stylelua" },
			python = { "isort", "black" },
			javascript = { "prettierd", "prettier", stop_after_first = true },
			bash = { "beautysh" },
			["_"] = { "trim_whitespace" }
		},
		default_format_opts = {
			lsp_format = "fallback",
		},
		format_on_save = { lsp_format = "fallback", timeout_ms = 500 },
	},
}
