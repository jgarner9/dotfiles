local config = require("bud.config")
local tools = require("bud.tools")

return {
  {
    "chat args allow read tools plus active bash tools, nothing else",
    function(T)
      T.bin("repomap", "#!/bin/sh\n")
      local args = tools.chat_args(T.project({}))
      local i = vim.fn.index(args, "--allowedTools")
      local allow = vim.split(args[i + 2], ",")
      T.ok(vim.tbl_contains(allow, "Read"))
      T.ok(vim.tbl_contains(allow, "Bash(repomap *)"))
      T.ok(not vim.tbl_contains(allow, "Bash"), "no unrestricted Bash")
      T.eq(args[vim.fn.index(args, "--permission-mode") + 2], "dontAsk")
      T.eq(args[vim.fn.index(args, "--tools") + 2], "Read,Grep,Glob,Bash")
      T.ok(vim.tbl_contains(args, "--strict-mcp-config"))
    end,
  },
  {
    "enabled MCP servers land in mcp.json and the allow list",
    function(T)
      local saved = vim.deepcopy(config.options.tools)
      config.options.tools.headroom = { enabled = true }
      T.bin("headroom", "#!/bin/sh\n")
      local args = tools.chat_args("/proj")
      local mcp = vim.json.decode(table.concat(vim.fn.readfile(args[vim.fn.index(args, "--mcp-config") + 2]), "\n"))
      T.eq(mcp.mcpServers.headroom.command, "headroom")
      T.eq(mcp.mcpServers.headroom.env.HEADROOM_BEACON, "off")
      T.contains(args[vim.fn.index(args, "--allowedTools") + 2], "mcp__headroom")
      config.options.tools = saved
    end,
  },
  {
    "language-server passes extra args after --",
    function(T)
      local spec = tools.registry["language-server"].server("/p", { lsp = "rust-analyzer", lsp_args = { "--x" } })
      T.eq(spec.args, { "--workspace", "/p", "--lsp", "rust-analyzer", "--", "--x" })
    end,
  },
  {
    "missing lists enabled tools without a binary",
    function(T)
      local saved = vim.deepcopy(config.options.tools)
      config.options.tools = { nothere = { enabled = true, kind = "bash", bin = "definitely-not-installed-xyz" } }
      T.eq(tools.missing(), { { name = "nothere", bin = "definitely-not-installed-xyz" } })
      T.eq(#tools.active(), 0)
      config.options.tools = saved
    end,
  },
  {
    "tool-free surfaces get no tools and no MCP",
    function(T)
      local args = tools.no_tool_args()
      T.eq(args, { "--tools", "", "--strict-mcp-config", "--permission-mode", "dontAsk" })
    end,
  },
}
