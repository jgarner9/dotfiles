-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here
vim.g.lazyvim_check_order = false

-- Disable remote-plugin providers. The stock python ftplugin calls
-- has('python3'), which spawns python interpreters to probe for pynvim and
-- adds ~130ms to opening the first .py file. No configured plugin uses a
-- python/ruby/perl/node host, so skip the detection entirely.
vim.g.loaded_python3_provider = 0
vim.g.loaded_ruby_provider = 0
vim.g.loaded_perl_provider = 0
vim.g.loaded_node_provider = 0
