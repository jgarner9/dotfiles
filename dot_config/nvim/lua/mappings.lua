require "nvchad.mappings"
local keymap = vim.keymap.set
local harpoon = require "harpoon"

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

keymap("n", "<leader>a", function()
  harpoon:list():add()
end)
keymap("n", "<C-e>", function()
  harpoon.ui:toggle_quick_menu(harpoon:list())
end)
keymap("n", "<C-h>", function()
  harpoon:list():select(1)
end)
keymap("n", "<C-j>", function()
  harpoon:list():select(2)
end)
keymap("n", "<C-k>", function()
  harpoon:list():select(3)
end)
keymap("n", "<C-l>", function()
  harpoon:list():select(4)
end)
