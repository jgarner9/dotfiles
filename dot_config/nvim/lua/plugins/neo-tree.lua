return {
	"nvim-neo-tree/neo-tree.nvim",
	branch = "v3.x",
	dependencies = {
		"nvim-lua/plenary.nvim",
		"nvim-tree/nvim-web-devicons",
		"MunifTanjim/nui.nvim",
	},
	lazy = false,
	---@module "neo-tree"
	---@type neotree.Config?
	opts = {
		close_if_last_window = true,
		enable_git_status = true,
		filesystem = {
			hide_dotfiles = false,
			hide_gitignored = false,
			never_show = ".DS_Store"
		},

	},
	config = function()
		require("neo-tree").setup({
			window = {
				position = "current"
			},
			event_handlers = {
				{
					event = "file_opened",
					handler = function()
						-- Only close if filesystem pane was open
						require("neo-tree.command").execute({
							action = "close",
							source =
							"filesystem"
						})
					end,
				},
			},
		})
		vim.keymap.set("n", "<leader>e", "<Cmd>Neotree position=current<CR>")
	end
}
