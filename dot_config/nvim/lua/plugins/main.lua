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
    "folke/sidekick.nvim",
    -- run CLI sessions inside zellij so they survive nvim restarts
    opts = {
      cli = {
        mux = {
          enabled = true,
        },
      },
    },
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
      -- override the snacks explorer mappings from LazyVim's default
      -- editor.snacks_explorer extra with plain netrw
      { "<leader>e", "<cmd>Explore<cr>", desc = "Explorer netrw (file dir)" },
      { "<leader>E", "<cmd>Explore .<cr>", desc = "Explorer netrw (cwd)" },
      { "<leader>fe", false },
      { "<leader>fE", false },
    },
  },
}
