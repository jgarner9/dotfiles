-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- `;` is left alone so it keeps repeating f/t/F/T (and flash.nvim) motions
vim.keymap.set({ "n", "x" }, "<leader>;", ":", { desc = "Command line" })
vim.keymap.set("i", "jk", "<Esc>")
