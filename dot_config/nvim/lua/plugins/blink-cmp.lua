return {
	"saghen/blink.cmp",
	event = "InsertEnter",
	dependencies = "rafamadriz/friendly-snippets",
	version = "*",
	build = "cargo build --release",
	opts = {
		keymap = { preset = "enter" },
		appearance = { use_nvim_cmp_as_default = true },
		sources = { default = { "lsp", "path", "snippets", "buffer" } },
		completion = {
			documentation = { auto_show = true },
			ghost_text = { enabled = true },
		},
	},
}
