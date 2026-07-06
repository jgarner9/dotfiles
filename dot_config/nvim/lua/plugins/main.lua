return {
  {
    "folke/sidekick.nvim",
    keys = {
      -- open Claude Code directly; sidekick runs the `claude` CLI in a
      -- terminal, so this uses the Claude subscription, not API billing
      {
        "<leader>ac",
        function()
          require("sidekick.cli").toggle({ name = "claude", focus = true })
        end,
        desc = "Sidekick Toggle Claude",
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
      -- override the snacks explorer mapping from LazyVim's default
      -- editor.snacks_explorer extra with plain netrw
      { "<leader>e", "<cmd>Explore<cr>", desc = "Explorer netrw (file dir)" },
    },
  },
}
