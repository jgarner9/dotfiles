return {
	"echasnovski/mini.pairs",
	event = "InsertEnter",
	config = function()
		require("mini.pairs").setup({
			modes = { insert = true, command = false, terminal = false },
			skip_next = [=[[%w%%%'%[%"%.%`%$]]=],
			skip_ts = { "string" },
			skip_unbalanced = true,
			markdown = true,
		})
	end,
}
