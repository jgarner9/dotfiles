-- Context tools offered to Claude in the chat float.
--
-- Two kinds:
--   bash: a CLI Claude may run read-only through its Bash tool. `allow` lists
--         the permission rules that let it run without asking.
--   mcp:  an MCP server. `server(root, opts)` returns its launch spec.
--
-- A tool is active only when it is enabled in config.tools and its binary is
-- installed. Only active tools reach Claude, and only their instruction files
-- (bud/instructions/tools/<name>.md) go into the system prompt.
local config = require("bud.config")
local util = require("bud.util")

local M = {}

M.registry = {
  rg = {
    kind = "bash",
    bin = "rg",
    allow = { "Bash(rg *)" },
  },
  ["ast-grep"] = {
    kind = "bash",
    -- not `sg`: on Linux that name belongs to shadow-utils
    bin = "ast-grep",
    allow = { "Bash(ast-grep *)" },
  },
  repomap = {
    kind = "bash",
    bin = "repomap",
    allow = { "Bash(repomap *)" },
  },
  serena = {
    kind = "mcp",
    bin = "serena",
    server = function(root)
      return { command = "serena", args = { "start-mcp-server", "--context", "claude-code", "--project", root } }
    end,
  },
  ["language-server"] = {
    kind = "mcp",
    bin = "mcp-language-server",
    server = function(root, opts)
      local args = { "--workspace", root, "--lsp", opts.lsp or "gopls" }
      if opts.lsp_args and #opts.lsp_args > 0 then
        table.insert(args, "--")
        vim.list_extend(args, opts.lsp_args)
      end
      return { command = "mcp-language-server", args = args }
    end,
  },
  context7 = {
    kind = "mcp",
    bin = "npx",
    server = function(_, opts)
      local args = { "-y", "@upstash/context7-mcp" }
      local key = opts.api_key_env and vim.env[opts.api_key_env]
      if key and key ~= "" then
        vim.list_extend(args, { "--api-key", key })
      end
      return { command = "npx", args = args }
    end,
  },
  headroom = {
    kind = "mcp",
    bin = "headroom",
    server = function()
      return { command = "headroom", args = { "mcp", "serve" }, env = { HEADROOM_BEACON = "off" } }
    end,
  },
}

--- Merged definition (registry + user config) for every configured tool.
function M.all()
  local out = {}
  for name, opts in pairs(config.tools or {}) do
    local def = vim.tbl_extend("force", M.registry[name] or {}, opts)
    def.name = name
    out[name] = def
  end
  return out
end

--- Enabled and installed tools, sorted by name.
function M.active()
  local list = {}
  for name, def in pairs(M.all()) do
    if def.enabled and def.kind and util.executable(def.bin) then
      table.insert(list, def)
    end
  end
  table.sort(list, function(a, b)
    return a.name < b.name
  end)
  return list
end

--- Enabled tools whose binary is missing (for the startup check).
function M.missing()
  local list = {}
  for name, def in pairs(M.all()) do
    if def.enabled and def.bin and not util.executable(def.bin) then
      table.insert(list, { name = name, bin = type(def.bin) == "table" and def.bin[1] or def.bin })
    end
  end
  table.sort(list, function(a, b)
    return a.name < b.name
  end)
  return list
end

--- CLI flags giving the chat its read-only tools and MCP servers.
function M.chat_args(root)
  local allow = { "Read", "Grep", "Glob" }
  local servers = {}
  for _, def in ipairs(M.active()) do
    if def.kind == "bash" then
      vim.list_extend(allow, def.allow or {})
    elseif def.kind == "mcp" and def.server then
      servers[def.name] = def.server(root, def)
      table.insert(allow, "mcp__" .. def.name)
    end
  end
  local mcp_path = util.dir("cache") .. "/mcp.json"
  util.write(mcp_path, vim.json.encode({ mcpServers = vim.tbl_isempty(servers) and vim.empty_dict() or servers }))
  return {
    "--tools",
    "Read,Grep,Glob,Bash",
    "--allowedTools",
    table.concat(allow, ","),
    "--permission-mode",
    "dontAsk",
    "--strict-mcp-config",
    "--mcp-config",
    mcp_path,
  }
end

--- CLI flags for tool-free surfaces (quick ask, write here, spawner).
function M.no_tool_args()
  return { "--tools", "", "--strict-mcp-config", "--permission-mode", "dontAsk" }
end

return M
