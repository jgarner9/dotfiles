require "nvchad.options"

vim.opt.lazyredraw = true
vim.opt.number = false
vim.opt.relativenumber = false
vim.api.nvim_set_hl(0, "@tag.tsx", { fg = "#61dafb", bold = true })
vim.api.nvim_set_hl(0, "@tag.jsx", { fg = "#61dafb", bold = true })
