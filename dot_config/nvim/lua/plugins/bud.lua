-- Bud lives in this config (lua/bud/); this spec loads it after startup and
-- hooks it into lualine and render-markdown.
return {
  {
    name = "bud",
    dir = vim.fn.stdpath("config") .. "/bud",
    event = "VeryLazy",
    opts = function()
      return require("config.bud")
    end,
    config = function(_, opts)
      require("bud").setup(opts)
    end,
  },
  {
    "nvim-lualine/lualine.nvim",
    optional = true,
    opts = function(_, opts)
      opts.sections = opts.sections or {}
      opts.sections.lualine_x = opts.sections.lualine_x or {}
      table.insert(opts.sections.lualine_x, 1, require("bud.ui.statusline").lualine())
    end,
  },
  {
    "MeanderingProgrammer/render-markdown.nvim",
    optional = true,
    ft = { "bud_chat" },
    opts = function(_, opts)
      opts.file_types = opts.file_types or { "markdown" }
      if not vim.tbl_contains(opts.file_types, "bud_chat") then
        table.insert(opts.file_types, "bud_chat")
      end
    end,
  },
}
