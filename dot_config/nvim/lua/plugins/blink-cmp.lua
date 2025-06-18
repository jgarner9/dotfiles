return {
	"Saghen/blink.cmp",
	event = "InsertEnter",
	dependencies = { "rafamadriz/friendly-snippets" },

	version = "1.*",

	---@module "blink.cmp"
	opts = {
		keymap = { preset = "enter" },

		appearance = {
			nerd_font_variant = "mono"
		},

		completion = { documentation = { auto_show = false } },
		sources = {
			default = { "lsp", "path", "snippets", "buffer" },
		},
		fuzzy = { implementation = "prefer_rust" },
	},
	opts_extend = { "sources.default" },
}
