local options = {
  formatters_by_ft = {
    lua = { "stylua" },
    css = { "prettier", "prettierd" },
    html = { "prettier", "prettierd" },
    javascript = { "prettier", "prettierd" },
    javascriptreact = { "prettier", "prettierd" },
    typescript = { "prettier", "prettierd" },
    typescriptreact = { "prettier", "prettierd" },
    go = { "goimports", "gofmt" },
    python = { "isort", "black" },
    c = { "clang-format" },
    ["*"] = { "codespell" },
    ["_"] = { "trim_whitespace" },
  },

  format_on_save = {
    -- These options will be passed to conform.format()
    timeout_ms = 500,
    lsp_fallback = true,
  },

  default_format_opts = {
    lsp_format = "fallback",
  },

  format_after_save = {
    lsp_format = "fallback",
  },

  notify_on_error = true,

  notify_no_formatters = true,
}

return options
