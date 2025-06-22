--  wjootstrap lazy.nvim
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
	local lazyrepo = "https://github.com/folke/lazy.nvim.git"
	local out = vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", lazyrepo, lazypath })
	if wjim.v.shell_error ~= 0 then
		vim.api.nvim_echo({
			{ "Failed to clone lazy.nvim:\n", "ErrorMsg" },
			{ out,                            "WarningMsg" },
			{ "\nPress any key to exit..." },
		}, true, {})
		vim.fn.getchar()
		os.exit(1)
	end
end
vim.opt.rtp:prepend(lazypath)

vim.g.mapleader = " "
vim.g.maplocalleader = "\\"
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1
vim.opt.lazyredraw = true
vim.opt.updatetime = 300
vim.opt.number = false
vim.opt.relativenumber = false
vim.opt.signcolumn = "no"
vim.loader.enable()

-- Enable line numbers only for code-like filetypes
vim.api.nvim_create_autocmd("FileType", {
	pattern = {
		"c", "cpp", "python", "javascript", "typescript", "lua", "go", "rust",
		"java", "sh", "bash", "zsh", "php", "ruby", "html", "css", "scss", "json",
		"yaml", "toml", "markdown"
	},
	callback = function()
		vim.wo.number = true
		vim.wo.relativenumber = true
	end,
})

-- include custom keymaps
-- vim.keymap.set("n", "<leader>ttt", "<cmd>echo 'test'<cr>")
vim.keymap.set("n", "<leader>wh", "<C-w>h")
vim.keymap.set("n", "<leader>wj", "<C-w>j")
vim.keymap.set("n", "<leader>wk", "<C-w>k")
vim.keymap.set("n", "<leader>wl", "<C-w>l")
vim.keymap.set("n", "<leader>wv", "<cmd>vsplit<cr>")
vim.keymap.set("n", "<leader>ws", "<cmd>split<cr>")
vim.keymap.set("n", "<leader>wq", "<cmd>close<cr>")
vim.keymap.set("n", "<leader>w", "<cmd>w<cr>")
vim.keymap.set("n", "<leader>ww", "<cmd>wq<cr>")
vim.keymap.set("n", "<leader>qq", "<cmd>q!<cr>")
vim.keymap.set("n", "<cr>", "o<esc>")
vim.keymap.set("n", "<leader>\\", "<cmd>split<cr><C-w>j<cmd>terminal<cr>a")

-- Setup lazy.nvim
require("lazy").setup({
	spec = {
		-- import your plugins
		{ import = "plugins" },
	},
	checker = { enabled = true },
})
