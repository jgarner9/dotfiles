-- Saving a dotfile copies it into the chezmoi source, so the source never
-- falls behind what you edit in $HOME. A file chezmoi already manages is
-- re-added (templates are left alone; chezmoi skips them); a new file is
-- added when it sits inside a folder chezmoi manages, except the broad ones
-- in config.chezmoi.skip such as ~/.config.
local config = require("bud.config")
local util = require("bud.util")

local M = {}

-- what chezmoi manages, as absolute paths: { [path] = true }
M.managed = nil
local loaded_at = 0
local TTL_MS = 10000 -- `chezmoi add` run in a terminal shows up within this

local queue = {}
local queued = {}
local busy = false

local function notify(msg, level)
  util.notify(msg, level, { title = "chezmoi" })
end

local function err_text(out)
  local e = vim.trim(out.stderr or "")
  return e ~= "" and e or ("exit code %d"):format(out.code)
end

--- Loads the managed paths, then calls cb (with nil when chezmoi failed).
function M.load(cb)
  if M.managed and vim.uv.now() - loaded_at < TTL_MS then
    return cb(M.managed)
  end
  local args = { config.chezmoi.cmd, "managed", "--path-style", "absolute", "--include", "files,dirs,symlinks" }
  local ok, err = pcall(vim.system, args, { text = true }, function(out)
    vim.schedule(function()
      if out.code ~= 0 then
        notify("chezmoi managed failed: " .. err_text(out), vim.log.levels.WARN)
        return cb(nil)
      end
      M.managed = {}
      for _, line in ipairs(vim.split(out.stdout or "", "\n", { trimempty = true })) do
        M.managed[vim.fs.normalize(line)] = true
      end
      loaded_at = vim.uv.now()
      cb(M.managed)
    end)
  end)
  if not ok then
    notify("chezmoi: " .. tostring(err), vim.log.levels.WARN)
    cb(nil)
  end
end

--- "re-add" for a managed file, "add" for a new file inside a managed
--- folder, nil for anything else.
function M.action(path, managed)
  if managed[path] then
    return "re-add"
  end
  local home = vim.fs.normalize(vim.env.HOME or "")
  local skip = {}
  for _, rel in ipairs(config.chezmoi.skip or {}) do
    skip[vim.fs.normalize(home .. "/" .. rel)] = true
  end
  for dir in vim.fs.parents(path) do
    if dir == home or #dir < #home then
      return nil
    end
    if managed[dir] and not skip[dir] then
      return "add"
    end
  end
end

-- one chezmoi at a time: it locks its state, and :wa saves many files at once
local function next_job()
  if busy or #queue == 0 then
    return
  end
  local path = table.remove(queue, 1)
  queued[path] = nil
  busy = true
  M.load(function(managed)
    local action = managed and M.action(path, managed)
    if not action then
      busy = false
      return next_job()
    end
    local ok, err = pcall(vim.system, { config.chezmoi.cmd, action, path }, { text = true }, function(out)
      vim.schedule(function()
        busy = false
        local name = vim.fn.fnamemodify(path, ":~")
        if out.code ~= 0 then
          notify(("chezmoi %s %s failed: %s"):format(action, name, err_text(out)), vim.log.levels.WARN)
        elseif action == "add" then
          if M.managed then
            M.managed[path] = true
          end
          notify(("Added %s to chezmoi"):format(name))
        end
        next_job()
      end)
    end)
    if not ok then
      busy = false
      notify("chezmoi: " .. tostring(err), vim.log.levels.WARN)
      next_job()
    end
  end)
end

--- Queues a saved file; does nothing for files outside chezmoi's folders.
function M.saved(path)
  if not config.chezmoi.enabled or not util.executable(config.chezmoi.cmd) then
    return
  end
  path = vim.fs.normalize(vim.fn.fnamemodify(path, ":p"))
  local home = vim.fs.normalize(vim.env.HOME or "")
  if home == "" or path:sub(1, #home + 1) ~= home .. "/" or queued[path] then
    return
  end
  queued[path] = true
  table.insert(queue, path)
  next_job()
end

--- Drops the cached managed paths, e.g. after dotsync pulled new files.
function M.invalidate()
  M.managed = nil
end

--- True when nothing is running or waiting, for tests.
function M.idle()
  return not busy and #queue == 0
end

return M
