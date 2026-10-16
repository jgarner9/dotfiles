-- Minimal test runner for Bud. Each tests/test_*.lua returns a list of
-- { name, fn } pairs; fn gets the helpers in T. Runs in `nvim -l`, so the
-- whole Neovim API is there, headless.
io.stdout:setvbuf("line")
local repo = os.getenv("BUD_REPO")
local here = os.getenv("BUD_TEST_DIR")
local work = os.getenv("BUD_TEST_WORK")

vim.opt.rtp:prepend(repo .. "/dot_config/nvim")
package.path = here .. "/?.lua;" .. package.path
vim.o.columns, vim.o.lines = 160, 50
vim.o.showmode = false

local T = {}
T.repo, T.here, T.work = repo, here, work

local function fmt(v)
  return type(v) == "string" and ("%q"):format(v) or vim.inspect(v)
end

function T.eq(a, b, msg)
  if not vim.deep_equal(a, b) then
    error(("%sexpected %s, got %s"):format(msg and (msg .. ": ") or "", fmt(b), fmt(a)), 2)
  end
end

function T.ok(v, msg)
  if not v then
    error(msg or "expected a truthy value", 2)
  end
  return v
end

function T.match(s, pat, msg)
  if type(s) ~= "string" or not s:find(pat) then
    error(("%sexpected %s to match %q"):format(msg and (msg .. ": ") or "", fmt(s), pat), 2)
  end
end

function T.contains(s, sub, msg)
  if type(s) ~= "string" or not s:find(sub, 1, true) then
    error(("%sexpected %s to contain %q"):format(msg and (msg .. ": ") or "", fmt(s), sub), 2)
  end
end

--- Waits for fn() to be truthy, processing events. Fails after ms.
function T.wait(fn, ms, msg)
  local ok = vim.wait(ms or 5000, fn, 20)
  if not ok then
    error("timed out waiting" .. (msg and (": " .. msg) or ""), 2)
  end
end

--- Writes the fake Claude's control file.
function T.control(c)
  local f = assert(io.open(os.getenv("FAKE_CLAUDE_CONTROL"), "w"))
  f:write(vim.json.encode(c or {}))
  f:close()
end

--- Every fake Claude process started so far: { args, cwd }.
function T.claude_runs()
  local f = io.open(os.getenv("FAKE_CLAUDE_LOG"), "r")
  if not f then
    return {}
  end
  local out = {}
  for line in f:lines() do
    table.insert(out, vim.json.decode(line))
  end
  f:close()
  return out
end

--- An executable script in the test PATH.
function T.bin(name, body)
  local path = work .. "/bin/" .. name
  local f = assert(io.open(path, "w"))
  f:write(body)
  f:close()
  vim.uv.fs_chmod(path, tonumber("755", 8))
  return path
end

--- Captures vim.notify calls while fn runs (or from now on, if fn is nil).
function T.notifications()
  local list = {}
  vim.notify = function(msg, level, opts)
    table.insert(list, { msg = msg, level = level, opts = opts })
  end
  return list
end

--- A temp directory with files: { ["a/b.lua"] = "text" }. git=true inits a repo.
function T.project(files, git)
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  for path, text in pairs(files or {}) do
    vim.fn.mkdir(vim.fs.dirname(dir .. "/" .. path), "p")
    local f = assert(io.open(dir .. "/" .. path, "w"))
    f:write(text)
    f:close()
  end
  if git then
    vim.fn.system({ "git", "-C", dir, "init", "-q" })
    vim.fn.system({ "git", "-C", dir, "-c", "user.email=t@t", "-c", "user.name=t", "add", "." })
    vim.fn.system({ "git", "-C", dir, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-qm", "init" })
  end
  return vim.uv.fs_realpath(dir)
end

--- Feeds keys as if typed, and processes them.
function T.keys(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "x", false)
end

-- The real prompts read stdin, and at EOF that ends Neovim with status 0,
-- skipping every test after it. A test mocks what it means to answer; any
-- other prompt is a failure.
local function unanswered(kind)
  return function(_, opts)
    error(("unanswered %s: %s"):format(kind, type(opts) == "table" and opts.prompt or "?"), 2)
  end
end

--- Closes every window but one and wipes buffers, between tests.
function T.reset()
  vim.ui.input = function(opts)
    unanswered("vim.ui.input")(nil, opts)
  end
  vim.ui.select = unanswered("vim.ui.select")
  pcall(vim.cmd, "stopinsert")
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_config(w).relative ~= "" then
      pcall(vim.api.nvim_win_close, w, true)
    end
  end
  pcall(vim.cmd, "silent! only!")
  pcall(vim.cmd, "enew!")
  T.control({})
end

-- Bud, set up the way the config does it, pointed at the fake CLI
local notes = T.notifications()
require("bud").setup({
  claude = here .. "/fake-claude",
  instructions_dir = repo .. "/dot_config/nvim/bud/instructions",
  sync = { enabled = false },
  chezmoi = { enabled = false }, -- tests enable it with a fake chezmoi
  warm = true,
})
T.startup_notes = notes

local only = _G.arg and _G.arg[1]
local files = vim.fn.glob(here .. "/tests/test_*.lua", false, true)
table.sort(files)
local passed, failed = 0, {}
for _, file in ipairs(files) do
  local mod = vim.fn.fnamemodify(file, ":t:r")
  if not only or mod == "test_" .. only then
    local ok, tests = pcall(dofile, file)
    if not ok then
      table.insert(failed, mod .. ": " .. tostring(tests))
    else
      for _, t in ipairs(tests) do
        T.reset()
        local tok, err = xpcall(t[2], debug.traceback, T)
        if tok then
          passed = passed + 1
          io.stdout:write(("ok   %s: %s\n"):format(mod, t[1]))
        else
          table.insert(failed, ("%s: %s\n%s"):format(mod, t[1], err))
          io.stdout:write(("FAIL %s: %s\n"):format(mod, t[1]))
        end
      end
    end
  end
end

require("bud.provider").shutdown()
io.stdout:write(("\n%d passed, %d failed\n"):format(passed, #failed))
for _, f in ipairs(failed) do
  io.stdout:write("\n" .. f .. "\n")
end
os.exit(#failed == 0 and 0 or 1)
