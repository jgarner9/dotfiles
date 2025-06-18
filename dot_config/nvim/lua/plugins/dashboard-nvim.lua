-- TODO: make dashboard pretty

return {
	"nvimdev/dashboard-nvim",
	event = "UIEnter",
	config = function()
		require("dashboard").setup {

		}
	end,
	dependecies = { { "nvim-tree/nvim-web-devicons" } }
}
