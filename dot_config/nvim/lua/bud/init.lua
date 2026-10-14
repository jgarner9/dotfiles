-- Bud: LLM help inside Neovim through native floats, on the Claude Code CLI.
--
--   <leader>aa  toggle the chat float (docked right)
--   <leader>an  new chat
--   <leader>ah  earlier chats in this project
--   <leader>aj  quick ask under the cursor (visual: about the selection)
--   <leader>ak  write here (visual: replace the selection), as a preview
--   <leader>as  spawn a script
--   <leader>at  spawn Go tests for the current file
--   <leader>al  the request log
--   <leader>ar  report a bug or ask for a feature; Bud opens a PR for it
--
-- Settings live in lua/config/bud.lua; defaults in lua/bud/config.lua.
local M = {}

local function lazy(mod, fn)
  return function(...)
    return require(mod)[fn](...)
  end
end

M.actions = {
  chat = lazy("bud.ui.chat", "toggle"),
  new_chat = lazy("bud.ui.chat", "new"),
  history = lazy("bud.ui.chat", "history"),
  quick = lazy("bud.ui.quick", "open"),
  write = lazy("bud.ui.write", "open"),
  spawn = lazy("bud.spawn", "open"),
  test = lazy("bud.testgen", "open"),
  log = lazy("bud.log", "open"),
  report = lazy("bud.ui.report", "open"),
}

local keymaps = {
  { "chat", "n", "Chat (toggle)" },
  { "new_chat", "n", "New chat" },
  { "history", "n", "Chat history" },
  { "quick", { "n", "x" }, "Quick ask" },
  { "write", { "n", "x" }, "Write here" },
  { "spawn", "n", "Spawn a script" },
  { "test", "n", "Spawn Go tests" },
  { "log", "n", "Request log" },
  { "report", "n", "Report a bug or feature" },
}

function M.instructions()
  local util = require("bud.util")
  local text = require("bud.instructions").text("chat", util.root())
  require("bud.ui.win").view(util.split_lines(text), { title = "instructions (chat)", ft = "markdown" })
end

local function commands()
  local cmd = vim.api.nvim_create_user_command
  cmd("BudChat", M.actions.chat, { desc = "Bud: toggle the chat float" })
  cmd("BudNew", M.actions.new_chat, { desc = "Bud: new chat" })
  cmd("BudHistory", M.actions.history, { desc = "Bud: earlier chats in this project" })
  cmd("BudSpawn", M.actions.spawn, { desc = "Bud: spawn a script" })
  cmd("BudTest", M.actions.test, { desc = "Bud: spawn Go tests for the current file" })
  cmd("BudLog", M.actions.log, { desc = "Bud: browse the request log" })
  cmd("BudInstructions", M.instructions, { desc = "Bud: show the instructions Claude gets" })
  cmd("BudSync", function()
    require("bud.sync").run(true)
  end, { desc = "Bud: run dotsync now" })
  cmd("BudReport", function(o)
    require("bud.ui.report").open(o.args ~= "" and o.args or nil)
  end, {
    nargs = "?",
    complete = function()
      return { "bug", "feature" }
    end,
    desc = "Bud: report a bug or ask for a feature",
  })
  cmd("BudFix", function(o)
    require("bud.report").fix(o.args)
  end, { nargs = 1, desc = "Bud: work on an existing issue in the background" })
  cmd("BudFixes", function()
    require("bud.report").list()
  end, { desc = "Bud: reports and their pull requests" })
end

local function autocmds()
  local config = require("bud.config")
  local group = vim.api.nvim_create_augroup("bud", { clear = true })
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      require("bud.provider").shutdown()
    end,
  })
  -- saving an instruction file restarts the warm Haiku process so quick ask
  -- and write here pick the change up right away; chats pick it up on the
  -- next new chat
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = group,
    pattern = {
      config.instructions_dir .. "/*",
      "*/dot_config/nvim/bud/instructions/*", -- the chezmoi source copy
      "*/.bud/rules.md",
    },
    callback = function()
      local provider = require("bud.provider")
      provider.drop_spare()
      provider.prewarm()
      require("bud.util").notify("Instructions updated. Open chats keep the old version until a new chat.")
    end,
  })
  vim.api.nvim_create_autocmd("DirChanged", {
    group = group,
    callback = function()
      require("bud.provider").drop_spare()
    end,
  })
end

local function filetypes()
  for _, ft in ipairs({ "bud_chat", "bud_quick", "bud_input" }) do
    pcall(vim.treesitter.language.register, "markdown", ft)
  end
  vim.api.nvim_create_autocmd("FileType", {
    group = vim.api.nvim_create_augroup("bud_filetypes", { clear = true }),
    pattern = { "bud_chat", "bud_quick", "bud_input" },
    callback = function(ev)
      pcall(vim.treesitter.start, ev.buf, "markdown")
      vim.bo[ev.buf].textwidth = 0
    end,
  })
end

function M.setup(opts)
  local config = require("bud.config")
  config.setup(opts)
  require("bud.ui.highlights").setup()
  filetypes()

  for _, k in ipairs(keymaps) do
    local lhs = config.keys[k[1]]
    if lhs and lhs ~= "" then
      vim.keymap.set(k[2], lhs, M.actions[k[1]], { desc = k[3] })
    end
  end
  local ok, wk = pcall(require, "which-key")
  if ok and wk.add then
    wk.add({ { "<leader>a", group = "bud", icon = { icon = vim.trim(config.icons.bud), color = "cyan" } } })
  end

  commands()
  autocmds()

  local provider = require("bud.provider")
  provider.on_change(function()
    require("bud.ui.statusline").refresh()
  end)
  require("bud.log").trim()

  -- after the first screen: dependency warning, dotfile sync, fixes that
  -- finished while Neovim was closed, warm Haiku
  vim.defer_fn(function()
    require("bud.deps").startup()
    require("bud.report").startup()
  end, 300)
  require("bud.sync").startup()
  vim.defer_fn(function()
    provider.prewarm()
  end, 3000)
end

return M
