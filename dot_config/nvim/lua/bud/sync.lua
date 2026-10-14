-- Runs dotsync in the background when Neovim starts and reports the result.
-- dotsync itself (dot_local/bin/executable_dotsync) does the pulling,
-- throttling, locking and drift checks; this only spawns it and listens.
local config = require("bud.config")
local util = require("bud.util")

local M = {}

-- the last result: { status, message, changed, drift, nvim_changed }
M.last = nil
M.running = false

local quiet = { up_to_date = true, skipped_throttle = true, skipped_locked = true }

local function report(res, force)
  local level = vim.log.levels.INFO
  local msg
  if res.status == "synced" then
    msg = ("Dotfiles synced (%d file%s)"):format(#(res.changed or {}), #(res.changed or {}) == 1 and "" or "s")
    if res.nvim_changed then
      msg = msg .. "\nNeovim config changed: restart Neovim to pick it up."
    end
  elseif res.status == "skipped_drift" then
    level = vim.log.levels.WARN
    msg = ("Dotfiles pulled but not applied. Edited outside chezmoi:\n- %s\nRun `chezmoi diff` to review."):format(
      table.concat(res.drift or {}, "\n- ")
    )
  elseif res.status == "error" then
    level = vim.log.levels.WARN
    msg = "Dotfile sync failed: " .. (res.message or "unknown error")
  elseif force or not quiet[res.status] then
    msg = ("Dotfiles: %s"):format(res.message or res.status)
  end
  if msg then
    util.notify(msg, level, { title = "dotsync" })
  end
end

--- Runs dotsync. force skips the throttle and always reports.
function M.run(force)
  if M.running then
    if force then
      util.notify("dotsync is already running", vim.log.levels.INFO, { title = "dotsync" })
    end
    return
  end
  local cmd = config.sync.cmd
  if not util.executable(cmd) then
    if force then
      util.notify(("`%s` is not installed"):format(cmd), vim.log.levels.WARN, { title = "dotsync" })
    end
    return
  end
  local args = { cmd, "--json" }
  if force then
    table.insert(args, "--force")
  end
  M.running = true
  require("bud.ui.statusline").refresh()
  local ok, err = pcall(vim.system, args, { text = true, detach = true }, function(out)
    vim.schedule(function()
      M.running = false
      local decoded, res =
        pcall(vim.json.decode, vim.trim(out.stdout or ""), { luanil = { object = true, array = true } })
      if not decoded or type(res) ~= "table" or not res.status then
        res = { status = "error", message = vim.trim(out.stderr or "") ~= "" and vim.trim(out.stderr) or "no output" }
      end
      M.last = res
      report(res, force)
      require("bud.ui.statusline").refresh()
    end)
  end)
  if not ok then
    M.running = false
    M.last = { status = "error", message = tostring(err) }
    report(M.last, force)
  end
end

--- Called from setup: waits a moment so the first screen draws first.
function M.startup()
  if not config.sync.enabled then
    return
  end
  vim.defer_fn(function()
    M.run(false)
  end, config.sync.delay_ms)
end

return M
