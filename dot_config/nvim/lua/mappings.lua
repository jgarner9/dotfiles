require "nvchad.mappings"

-- add yours here

local keymap = vim.keymap.set
keymap("n", ";", ":", { desc = "CMD enter command mode" })
keymap("i", "jk", "<ESC>")
keymap("n", "<leader>wh", "<C-w>h")
keymap("n", "<leader>wj", "<C-w>j")
keymap("n", "<leader>wk", "<C-w>k")
keymap("n", "<leader>wl", "<C-w>l")
keymap("n", "<leader>wv", "<cmd>vsplit<cr>")
keymap("n", "<leader>ws", "<cmd>split<cr>")
keymap("n", "<cr>", "o<esc>")
keymap("n", "!", ":!")

keymap({ "n", "t" }, "<A-i>", function()
  require("nvchad.term").toggle { pos = "float", id = "floatTerm" }
end)

keymap("n", "<A-c>", function()
  require "nvchad.lsp.renamer"()
end)
