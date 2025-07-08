return {
	'nvimdev/lspsaga.nvim',
	event = "LspAttach",
	config = function()
		require('lspsaga').setup({
			ui = {
				border = "rounded",
				code_action = ""
			}
		})
	end,
	dependencies = {
		'nvim-treesitter/nvim-treesitter', -- optional
		'nvim-tree/nvim-web-devicons', -- optional
	}
}
