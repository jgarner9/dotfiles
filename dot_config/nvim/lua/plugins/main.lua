return {
  -- second colorscheme shipped by LazyVim; tokyonight is the one in use
  { "catppuccin/nvim", name = "catppuccin", enabled = false },
  -- html/css language servers; no LazyVim extra exists for plain html/css
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        html = {},
        cssls = {},
      },
    },
  },
  {
    "folke/snacks.nvim",
    opts = {
      explorer = {
        enabled = false,
      },
    },
    keys = {
      -- override the snacks explorer mappings from LazyVim's default
      -- editor.snacks_explorer extra with plain netrw
      { "<leader>e", "<cmd>Explore<cr>", desc = "Explorer netrw (file dir)" },
      { "<leader>E", "<cmd>Explore .<cr>", desc = "Explorer netrw (cwd)" },
      { "<leader>fe", false },
      { "<leader>fE", false },
    },
  },
}
