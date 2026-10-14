-- :checkhealth bud
local M = {}

function M.check()
  local config = require("bud.config")
  local deps = require("bud.deps")
  local instructions = require("bud.instructions")
  local tools = require("bud.tools")
  local util = require("bud.util")
  local h = vim.health

  h.start("Bud: dependencies")
  local ignore = {}
  for _, name in ipairs(config.deps.ignore_missing or {}) do
    ignore[name] = true
  end
  for _, d in ipairs(deps.check()) do
    local msg = ("%s (needed by %s)"):format(d.name, d.needed_by)
    if d.ok then
      h.ok(msg)
    elseif ignore[d.name] then
      h.info(msg .. " is missing, ignored on this machine")
    elseif d.required then
      h.error(msg .. " is missing")
    else
      h.warn(msg .. " is missing")
    end
  end

  h.start("Bud: Claude CLI")
  if util.executable(config.claude) then
    local res = vim.system({ config.claude, "--version" }, { text = true }):wait(5000)
    h.ok(("%s %s"):format(config.claude, vim.trim(res.stdout or "")))
    local auth = vim.system({ config.claude, "auth", "status" }, { text = true }):wait(10000)
    local ok, data = pcall(vim.json.decode, auth.stdout or "")
    if not ok or type(data) ~= "table" then
      h.warn("Could not read `claude auth status`: " .. vim.trim((auth.stderr or "") .. (auth.stdout or "")))
    elseif not data.loggedIn then
      h.error("Not signed in. Run `claude` in a shell and use /login.")
    elseif deps.api_key_auth(data.authMethod) then
      h.warn(("Signed in with %s, which bills per token instead of your subscription"):format(data.authMethod))
    else
      h.ok(("Signed in (%s)"):format(tostring(data.authMethod)))
    end
  else
    h.error(("`%s` not found in PATH"):format(config.claude))
  end
  h.info(
    ("models: chat %s, quick %s, write %s, spawn %s"):format(
      config.models.chat,
      config.models.quick,
      config.models.write,
      config.models.spawn
    )
  )

  h.start("Bud: context tools (chat)")
  local active = {}
  for _, def in ipairs(tools.active()) do
    active[def.name] = true
  end
  local names = vim.tbl_keys(tools.all())
  table.sort(names)
  for _, name in ipairs(names) do
    local def = tools.all()[name]
    if not def.kind then
      h.warn(("%s: no registry entry; give it kind, bin and allow or server"):format(name))
    elseif active[name] then
      h.ok(("%s (%s)"):format(name, def.kind))
    elseif def.enabled then
      h.warn(("%s is enabled but %s is not installed"):format(name, type(def.bin) == "table" and def.bin[1] or def.bin))
    else
      h.info(("%s is disabled"):format(name))
    end
  end

  h.start("Bud: instructions")
  local root = util.root()
  for _, f in ipairs(instructions.files(root, { with_tools = true })) do
    h.ok(f.label .. "  " .. vim.fn.fnamemodify(f.path, ":~"))
  end
  if #instructions.files(root) == 0 then
    h.warn("No instruction files in " .. config.instructions_dir)
  end

  h.start("Bud: dotfile sync")
  local sync = require("bud.sync")
  if not config.sync.enabled then
    h.info("Disabled")
  elseif sync.last then
    local level = (sync.last.status == "error" or sync.last.status == "skipped_drift") and "warn" or "ok"
    h[level](("%s: %s"):format(sync.last.status, sync.last.message or ""))
  else
    h.info("Not run in this session yet")
  end
end

return M
