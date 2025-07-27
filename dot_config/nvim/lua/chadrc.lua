-- This file needs to have same structure as nvconfig.lua
-- https://github.com/NvChad/ui/blob/v3.0/lua/nvconfig.lua
-- Please read that file to know all available options :(

---@type ChadrcConfig
local M = {}

M.base46 = {
  theme = "gruvbox",
}

M.ui = {
  cmp = {
    lspkind_text = true,
    style = "default",
    format_colors = {
      lsp = true,
    },
  },
  telescope = { style = "bordered" },
}

M.colorify = {
  enabled = true,
  mode = "virtual",
  virt_text = "󱓻 ",
  highlight = { hex = true, lspvars = true },
}

M.lsp = {
  signature = true,
}

M.nvdash = {
  load_on_startup = true,
  header = {
    " █     █░ ██░ ██▓██   ██▓    ██░ ██ ▓█████  ██▀███   ██▀███   ▒█████  ",
    "▓█░ █ ░█░▓██░ ██▒▒██  ██▒   ▓██░ ██▒▓█   ▀ ▓██ ▒ ██▒▓██ ▒ ██▒▒██▒  ██▒",
    "▒█░ █ ░█ ▒██▀▀██░ ▒██ ██░   ▒██▀▀██░▒███   ▓██ ░▄█ ▒▓██ ░▄█ ▒▒██░  ██▒",
    "░█░ █ ░█ ░▓█ ░██  ░ ▐██▓░   ░▓█ ░██ ▒▓█  ▄ ▒██▀▀█▄  ▒██▀▀█▄  ▒██   ██░",
    "░░██▒██▓ ░▓█▒░██▓ ░ ██▒▓░   ░▓█▒░██▓░▒████▒░██▓ ▒██▒░██▓ ▒██▒░ ████▓▒░",
    "░ ▓░▒ ▒   ▒ ░░▒░▒  ██▒▒▒     ▒ ░░▒░▒░░ ▒░ ░░ ▒▓ ░▒▓░░ ▒▓ ░▒▓░░ ▒░▒░▒░ ",
    "  ▒ ░ ░   ▒ ░▒░ ░▓██ ░▒░     ▒ ░▒░ ░ ░ ░  ░  ░▒ ░ ▒░  ░▒ ░ ▒░  ░ ▒ ▒░ ",
    "  ░   ░   ░  ░░ ░▒ ▒ ░░      ░  ░░ ░   ░     ░░   ░   ░░   ░ ░ ░ ░ ▒  ",
    "    ░     ░  ░  ░░ ░         ░  ░  ░   ░  ░   ░        ░         ░ ░  ",
    "                 ░ ░                                                  ",
    "                                                                      ",
  },
}

return M
