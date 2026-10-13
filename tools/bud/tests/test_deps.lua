local config = require("bud.config")
local deps = require("bud.deps")

local function names(list)
  return vim.tbl_map(function(d)
    return d.name
  end, list)
end

return {
  {
    "missing names what breaks; ignore_missing silences it",
    function(T)
      local saved = config.options.claude
      config.options.claude = "no-such-claude-xyz"
      local missing = deps.missing()
      T.ok(vim.tbl_contains(names(missing), "claude"))
      T.contains(deps.describe(missing), "- claude: every Bud feature (required)")
      table.insert(config.options.deps.ignore_missing, "claude")
      T.ok(not vim.tbl_contains(names(deps.missing()), "claude"))
      table.remove(config.options.deps.ignore_missing)
      config.options.claude = saved
    end,
  },
  {
    "sync deps only count when sync is on",
    function(T)
      T.ok(not vim.tbl_contains(names(deps.check()), "chezmoi"))
      config.options.sync.enabled = true
      T.ok(vim.tbl_contains(names(deps.check()), "chezmoi"))
      config.options.sync.enabled = false
    end,
  },
  {
    "startup warns once for missing deps",
    function(T)
      local saved = config.options.tools
      config.options.tools = { ["ast-grep"] = { enabled = true } }
      local notes = T.notifications()
      deps.startup()
      T.wait(function()
        return #notes > 0
      end)
      vim.wait(300)
      config.options.tools = saved
      local warn = notes[1]
      if vim.fn.executable("ast-grep") == 0 then
        T.contains(warn.msg, "Missing:")
        T.contains(warn.msg, "ast-grep")
        T.contains(warn.msg, ":checkhealth bud")
        T.eq(warn.level, vim.log.levels.WARN)
      end
    end,
  },
  {
    "auth: signed out and API-key logins warn",
    function(T)
      local cases = {
        { env = { FAKE_CLAUDE_LOGGED_IN = "0" }, want = "isn't signed in" },
        { env = { FAKE_CLAUDE_AUTH = "api_key" }, want = "bills per token" },
      }
      for _, c in ipairs(cases) do
        for k, v in pairs(c.env) do
          vim.env[k] = v
        end
        local res
        deps.auth(function(r)
          res = r
        end)
        T.wait(function()
          return res
        end)
        local notes = T.notifications()
        local saved = config.options.tools
        config.options.tools = {}
        deps.startup()
        T.wait(function()
          for _, n in ipairs(notes) do
            if n.msg:find(c.want, 1, true) then
              return true
            end
          end
        end, 5000, c.want)
        config.options.tools = saved
        for k in pairs(c.env) do
          vim.env[k] = nil
        end
      end
      T.ok(deps.api_key_auth("api_key"))
      T.ok(not deps.api_key_auth("claude.ai"))
      T.ok(not deps.api_key_auth("oauth_token"))
    end,
  },
  {
    "the health check reports against the fake CLI",
    function(T)
      -- :checkhealth itself needs a UI, so capture what the check reports
      local out = {}
      local saved = vim.health
      vim.health = setmetatable({}, {
        __index = function(_, level)
          return function(msg)
            table.insert(out, level .. ": " .. msg)
          end
        end,
      })
      local ok, err = pcall(require("bud.health").check)
      vim.health = saved
      T.ok(ok, err)
      local text = table.concat(out, "\n")
      T.contains(text, "start: Bud: Claude CLI")
      T.contains(text, "9.9.9 (Fake Claude)")
      T.contains(text, "ok: Signed in (claude.ai)")
      T.contains(text, "00-base.md")
      T.contains(text, "info: serena is disabled")
    end,
  },
}
