-- Everything Bud relies on, in one list. The startup warning and
-- :checkhealth bud both read it, so they can't drift apart.
local config = require("bud.config")
local tools = require("bud.tools")
local util = require("bud.util")

local M = {}

local function sync_on()
  return config.sync.enabled
end

local function report_on()
  return config.report.enabled
end

--- { name, bin?, plugin?, needed_by, required?, when? }
M.list = {
  {
    name = "claude",
    bin = function()
      return config.claude
    end,
    needed_by = "every Bud feature",
    required = true,
  },
  { name = "git", bin = "git", needed_by = "dotsync", required = true, when = sync_on },
  { name = "chezmoi", bin = "chezmoi", needed_by = "dotsync", required = true, when = sync_on },
  {
    name = "dotsync",
    bin = function()
      return config.sync.cmd
    end,
    needed_by = "dotfile sync on startup",
    when = sync_on,
  },
  { name = "go", bin = "go", needed_by = "Go tools and Go scripts from the spawner" },
  { name = "shellcheck", bin = "shellcheck", needed_by = "spawner checks on Bash scripts (bash -n still runs)" },
  { name = "gh", bin = "gh", needed_by = "bug and feature reports (issues and pull requests)", when = report_on },
  {
    name = "bud-fix",
    bin = function()
      return config.report.cmd
    end,
    needed_by = "bug and feature reports (chezmoi builds it from tools/ when Go is installed)",
    when = report_on,
  },
  { name = "snacks.nvim", plugin = "snacks", needed_by = "pickers, inputs and notifications", required = true },
  { name = "render-markdown.nvim", plugin = "render-markdown", needed_by = "chat rendering" },
  { name = "lualine.nvim", plugin = "lualine", needed_by = "the statusline segment" },
}

local function bin_of(dep)
  if type(dep.bin) == "function" then
    return dep.bin()
  end
  return dep.bin
end

--- Installed without loading it: lazy.nvim knows every plugin it manages.
local function has_plugin(mod)
  local ok, lazy_config = pcall(require, "lazy.core.config")
  if ok and lazy_config.plugins then
    for name, plugin in pairs(lazy_config.plugins) do
      if name:lower():find(mod, 1, true) and vim.uv.fs_stat(plugin.dir) then
        return true
      end
    end
  end
  return package.loaded[mod] ~= nil or #vim.api.nvim_get_runtime_file("lua/" .. mod .. "/init.lua", false) > 0
end

--- Every dependency with its state: { name, needed_by, required, ok }.
function M.check()
  local out = {}
  for _, dep in ipairs(M.list) do
    if not dep.when or dep.when() then
      local ok
      if dep.plugin then
        ok = has_plugin(dep.plugin)
      else
        ok = util.executable(bin_of(dep)) ~= nil
      end
      table.insert(out, { name = dep.name, needed_by = dep.needed_by, required = dep.required, ok = ok })
    end
  end
  for _, t in ipairs(tools.missing()) do
    table.insert(out, { name = t.bin, needed_by = ("the %s context tool in chat"):format(t.name), ok = false })
  end
  return out
end

--- Missing dependencies, minus the ones this machine opted out of.
function M.missing()
  local ignore = {}
  for _, name in ipairs(config.deps.ignore_missing or {}) do
    ignore[name] = true
  end
  local out = {}
  for _, d in ipairs(M.check()) do
    if not d.ok and not ignore[d.name] then
      table.insert(out, d)
    end
  end
  return out
end

--- Runs `claude auth status` in the background. cb({ ok, logged_in, method, error }).
function M.auth(cb)
  if not util.executable(config.claude) then
    return cb({ ok = false, error = "claude is not installed" })
  end
  local ok, err = pcall(vim.system, { config.claude, "auth", "status" }, { text = true }, function(out)
    vim.schedule(function()
      local decoded, data = pcall(vim.json.decode, out.stdout or "")
      if out.code ~= 0 and not (decoded and type(data) == "table") then
        return cb({ ok = false, error = vim.trim((out.stderr or "") .. (out.stdout or "")) })
      end
      if not decoded or type(data) ~= "table" then
        return cb({ ok = false, error = "could not read `claude auth status`" })
      end
      cb({ ok = true, logged_in = data.loggedIn == true, method = data.authMethod })
    end)
  end)
  if not ok then
    cb({ ok = false, error = tostring(err) })
  end
end

--- True when the CLI bills an API key instead of the subscription.
function M.api_key_auth(method)
  return type(method) == "string" and method:lower():find("api") ~= nil
end

--- One line per missing dependency, naming what it breaks.
function M.describe(missing)
  local lines = {}
  for _, d in ipairs(missing) do
    table.insert(lines, ("- %s: %s%s"):format(d.name, d.needed_by, d.required and " (required)" or ""))
  end
  return table.concat(lines, "\n")
end

--- The startup check: one warning when something is missing, silence
--- otherwise. Never blocks.
function M.startup()
  local missing = M.missing()
  if #missing > 0 then
    local names = vim.tbl_map(function(d)
      return d.name
    end, missing)
    util.notify(
      ("Missing: %s\n%s\nRun :checkhealth bud for details."):format(table.concat(names, ", "), M.describe(missing)),
      vim.log.levels.WARN
    )
  end
  M.auth(function(res)
    if not res.ok then
      if util.executable(config.claude) then
        util.notify("Could not check Claude sign-in: " .. (res.error or "unknown error"), vim.log.levels.WARN)
      end
    elseif not res.logged_in then
      util.notify("The Claude CLI isn't signed in. Run `claude` in a shell and use /login.", vim.log.levels.WARN)
    elseif M.api_key_auth(res.method) then
      util.notify(
        ("Claude is using %s, which bills per token instead of your subscription."):format(res.method),
        vim.log.levels.WARN
      )
    end
  end)
end

return M
