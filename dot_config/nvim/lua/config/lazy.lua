--  Bootstrap lazy.nvim
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
	local lazyrepo = "https://github.com/folke/lazy.nvim.git"
	local out = vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", lazyrepo, lazypath })
	if vim.v.shell_error ~= 0 then
		vim.api.nvim_echo({
			{ "Failed to clone lazy.nvim:\n", "ErrorMsg" },
			{ out,                            "WarningMsg" },
			{ "\nPress any key to exit..." },
		}, true, {})
		vim.fn.getchar()
		os.exit(1)
	end
end

-- set options
vim.diagnostic.config({
	virtual_text = true,
	virutal_text = {
		spacing = 4,
		prefix = '●',
	},
	signs = false,
	underline = true,
	update_in_insert = false,
	severity_sort = true,
})
vim.opt.rtp:prepend(lazypath)

vim.g.mapleader = " "
vim.g.maplocalleader = "\\"
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1
vim.opt.lazyredraw = true
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

-- set line number highlights and colors (after color scheme loads)
vim.api.nvim_create_autocmd("ColorScheme", {
	callback = function()
		vim.api.nvim_set_hl(0, "LineNr", { fg = "#897379", bold = true, bg = "NONE" })
		vim.api.nvim_set_hl(0, "CursorLineNr", { bold = true, bg = "NONE" })
	end,
})

-- include custom keymaps
-- vim.keymap.set("n", "<leader>ttt", "<cmd>echo 'test'<cr>")
-- Window navigation
vim.keymap.set("n", "<leader>wh", "<C-w>h")
vim.keymap.set("n", "<leader>wj", "<C-w>j")
vim.keymap.set("n", "<leader>wk", "<C-w>k")
vim.keymap.set("n", "<leader>wl", "<C-w>l")
-- Window management
vim.keymap.set("n", "<leader>wv", "<cmd>vsplit<cr>")
vim.keymap.set("n", "<leader>ws", "<cmd>split<cr>")
vim.keymap.set("n", "<leader>wq", "<cmd>close<cr>")
vim.keymap.set("n", "<leader>wc", "<cmd>bd<cr>")
-- QoL keymaps
vim.keymap.set("n", "<cr>", "o<esc>")
-- Lspsaga keymaps
vim.keymap.set("n", "<A-d>", "<cmd>Lspsaga term_toggle<cr>")
vim.keymap.set("t", "<A-d>", "<cmd>Lspsaga term_toggle<cr>")
vim.keymap.set("n", "<leader>d", "<cmd>Lspsaga peek_definition<cr>")
vim.keymap.set("n", "<leader>g", "<cmd>Lspsaga goto_definition<cr>")
vim.keymap.set("n", "<leader>lf", "<cmd>Lspsaga finder<cr>")
vim.keymap.set("n", "<leader>r", "<cmd>Lspsaga rename<cr>")
vim.keymap.set("n", "K", "<cmd>Lspsaga hover_doc<cr>")

vim.keymap.set("n", "<leader>c", "gcc")
-- Setup lazy.nvim
require("lazy").setup({
	spec = {
		-- import your plugins
		{ import = "plugins" },
	},
	checker = { enabled = true },
})
