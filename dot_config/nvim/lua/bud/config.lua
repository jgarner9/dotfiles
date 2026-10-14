-- Bud's defaults. Override any of these in lua/config/bud.lua; tables merge
-- deeply, so you only list what you change.
local M = {}

M.defaults = {
  -- the Claude Code CLI; every request goes through it, so it uses your
  -- Claude subscription rather than an API key
  claude = "claude",

  -- model per surface (CLI aliases or full model names)
  models = {
    chat = "sonnet",
    quick = "haiku",
    write = "haiku",
    spawn = "sonnet",
    name = "haiku",
    fix = "sonnet", -- the background fixer behind bug and feature reports
  },

  keys = {
    chat = "<leader>aa",
    new_chat = "<leader>an",
    history = "<leader>ah",
    quick = "<leader>aj",
    write = "<leader>ak",
    spawn = "<leader>as",
    test = "<leader>at",
    log = "<leader>al",
    report = "<leader>ar",
  },

  chat = {
    width = 0.45, -- fraction of the editor width, docked right
    input_height = 4,
    max_view_lines = 400, -- visible lines sent as context, at most
  },

  quick = {
    width = 80,
    max_height = 16,
  },

  write = {
    surrounding_lines = 40, -- lines above and below the cursor sent as context
  },

  -- instruction files every Claude process gets (see bud/instructions/)
  instructions_dir = vim.fn.stdpath("config") .. "/bud/instructions",

  -- context tools for the chat. A tool is offered to Claude only when it is
  -- enabled here and its binary is installed. Add your own with the same
  -- shape (see lua/bud/tools.lua).
  tools = {
    rg = { enabled = true },
    ["ast-grep"] = { enabled = true },
    repomap = { enabled = true },
    serena = { enabled = false },
    ["language-server"] = { enabled = false, lsp = "gopls", lsp_args = {} },
    context7 = { enabled = false, api_key_env = "CONTEXT7_API_KEY" },
    headroom = { enabled = false },
  },

  -- bug reports and feature requests: Bud files the issue and bud-fix
  -- (tools/cmd/bud-fix) works on a pull request in the background
  report = {
    enabled = true,
    cmd = "bud-fix",
    requests = 5, -- recent requests attached to a report
  },

  sync = {
    enabled = true,
    cmd = "dotsync",
    delay_ms = 1500, -- after startup, so it never competes with the first draw
  },

  deps = {
    -- names to never warn about on this machine, e.g. { "go" }
    ignore_missing = {},
  },

  -- keep a Haiku process warm for quick ask and write here
  warm = true,

  log = {
    enabled = true,
    max_entries = 1000,
  },

  icons = {
    bud = "󰚩 ",
    you = "󰀄 ",
    quick = "󱐋 ",
    write = "󰏫 ",
    spawn = "󰆍 ",
    file = "󰈙 ",
    busy = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" },
    ok = "✓",
    warn = "",
    sync = "󰓦",
    bug = "󰃤 ",
    feature = "󰌵 ",
  },
}

M.options = vim.deepcopy(M.defaults)

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
  if vim.g.bud_ignore_missing then
    vim.list_extend(M.options.deps.ignore_missing, vim.g.bud_ignore_missing)
  end
  return M.options
end

return setmetatable(M, {
  __index = function(_, k)
    return M.options[k]
  end,
})
