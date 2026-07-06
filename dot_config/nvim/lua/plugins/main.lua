return {
  {
    "folke/snacks.nvim",
    opts = {
      explorer = {
        enabled = false,
      },
    },
    keys = {
      -- override the snacks explorer mapping from LazyVim's default
      -- editor.snacks_explorer extra with plain netrw
      { "<leader>e", "<cmd>Explore<cr>", desc = "Explorer netrw (file dir)" },
    },
  },
}
