return {
  "mfussenegger/nvim-lint",
  event = { "BufWritePre", "BufReadPost", "InsertLeave" },
  config = function()
    local lint = require "lint"

    lint.linters_by_ft = {
      python = { "ruff", "mypy" },
      javascript = { "eslint_d" },
      typescript = { "eslint_d" },
      javascriptreact = { "eslint_d" },
      typescriptreact = { "eslint_d" },
      lua = { "luacheck" },
    }
  end,
}
