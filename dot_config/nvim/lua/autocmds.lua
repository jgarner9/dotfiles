require "nvchad.autocmds"

vim.api.nvim_create_autocmd("FileType", {
  pattern = {
    "c",
    "cpp",
    "python",
    "javascript",
    "javascriptreact",
    "typescript",
    "typescriptreact",
    "lua",
    "go",
    "rust",
    "java",
    "sh",
    "bash",
    "zsh",
    "php",
    "ruby",
    "html",
    "css",
    "scss",
    "json",
    "yaml",
    "toml",
    "markdown",
  },
  callback = function()
    vim.wo.number = true
    vim.wo.relativenumber = true
  end,
})
