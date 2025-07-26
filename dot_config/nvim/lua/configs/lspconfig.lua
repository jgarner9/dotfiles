require("nvchad.configs.lspconfig").defaults()

local servers = { "html", "cssls", "ts_ls", "gopls", "clangd", "pyright", "htmx-lsp" }
vim.lsp.enable(servers)

local capabilities = vim.lsp.protocol.make_client_capabilities()
capabilities.textDocument.completion.completionItem.snippetSupport = true

vim.lsp.config("html", {
  capabilities = capabilities
})

vim.lsp.config("cssls", {
  capabilities = capabilities
})
