-- Bug reports and feature requests that turn into pull requests.
--
-- <leader>ar opens the report float (lua/bud/ui/report.lua). Sending hands
-- the report to bud-fix (tools/cmd/bud-fix), started detached so quitting
-- Neovim doesn't stop it. bud-fix files a GitHub issue, runs Claude Code in a
-- worktree of your dotfiles with edits limited to Bud's own files, runs
-- tools/test.sh itself and opens a pull request, a draft when the tests fail.
-- It never merges. Bud follows each run through its state file, shows it in
-- the statusline and tells you when the PR is up.
--
-- What goes where:
--   the issue (GitHub): your description, versions, recent errors, and which
--     requests ran (mode, model, time), never their prompts or answers
--   the fixer only (local): those requests' prompts and answers, so Claude
--     can see what went wrong
local config = require("bud.config")
local log = require("bud.log")
local util = require("bud.util")

local M = {}

local notify_id = "bud_fix"

local function say(msg, level, id)
  util.notify(msg, level, { id = id and (notify_id .. "_" .. id) or notify_id, title = "Bud fixer" })
end

function M.state_dir()
  local base = vim.env.XDG_STATE_HOME
  if not base or base == "" then
    base = vim.fn.expand("~/.local/state")
  end
  return base .. "/bud/fixes"
end

function M.reports_dir()
  return util.dir("state") .. "/reports"
end

-- Attachments

--- `claude --version`, fetched once in the background.
function M.claude_version(cb)
  if M._claude_version ~= nil then
    return cb and cb(M._claude_version)
  end
  if not util.executable(config.claude) then
    M._claude_version = false
    return cb and cb(false)
  end
  pcall(vim.system, { config.claude, "--version" }, { text = true }, function(out)
    vim.schedule(function()
      M._claude_version = out.code == 0 and vim.trim(out.stdout or ""):match("^%S+") or false
      if cb then
        cb(M._claude_version)
      end
    end)
  end)
end

--- Bud's commit in the dotfiles repo, with a note when it has local edits.
local function revision()
  local src = require("bud.spawn").chezmoi_source()
  if not src then
    return nil
  end
  local res = vim.system({ "git", "-C", src, "rev-parse", "--short", "HEAD" }, { text = true }):wait(3000)
  if res.code ~= 0 then
    return nil
  end
  local rev = vim.trim(res.stdout)
  local dirty = vim
    .system({ "git", "-C", src, "status", "--porcelain", "--", "dot_config/nvim" }, { text = true })
    :wait(3000)
  if dirty.code == 0 and vim.trim(dirty.stdout or "") ~= "" then
    rev = rev .. " (with local edits)"
  end
  return rev
end

--- Versions, platform and Bud's setup, for the issue. ft is the filetype of
--- the buffer the report was opened from.
function M.environment(ft)
  local uname = vim.uv.os_uname()
  local lines = {
    "- Neovim " .. tostring(vim.version()),
    ("- %s %s %s"):format(uname.sysname, uname.release, uname.machine),
  }
  if M._claude_version then
    table.insert(lines, "- Claude Code " .. M._claude_version)
  end
  local rev = revision()
  if rev then
    table.insert(lines, "- Bud at " .. rev)
  end
  if ft and ft ~= "" then
    table.insert(lines, ("- Reported from a `%s` buffer"):format(ft))
  end
  local tools = vim.tbl_map(function(d)
    return d.name
  end, require("bud.tools").active())
  table.insert(lines, "- Context tools: " .. (#tools > 0 and table.concat(tools, ", ") or "none"))
  local missing = vim.tbl_map(function(d)
    return d.name
  end, require("bud.deps").missing())
  if #missing > 0 then
    table.insert(lines, "- Missing: " .. table.concat(missing, ", "))
  end
  local sync = package.loaded["bud.sync"] and require("bud.sync").last
  if sync then
    table.insert(lines, ("- Dotfile sync: %s"):format(sync.status))
  end
  return lines
end

--- Bud's recent warnings and errors: its own notifications this session, Lua
--- errors from Bud's files in :messages, and failed requests in the last day.
function M.errors()
  local out, seen = {}, {}
  local function add(text)
    text = vim.trim(text or "")
    if text ~= "" and not seen[text] and #out < 10 then
      seen[text] = true
      table.insert(out, text)
    end
  end
  for i = #util.recent, 1, -1 do
    add(util.recent[i].msg)
  end
  local ok, messages = pcall(vim.fn.execute, "messages")
  if ok then
    local lines = vim.split(messages, "\n", { plain = true })
    local i = 1
    while i <= #lines do
      local line = lines[i]
      if line:find("lua/bud/", 1, true) and line:find("rror") then
        local chunk = { line }
        while lines[i + 1] and (lines[i + 1]:match("^%s") or lines[i + 1]:match("^stack traceback")) and #chunk < 8 do
          i = i + 1
          table.insert(chunk, lines[i])
        end
        add(table.concat(chunk, "\n"))
      end
      i = i + 1
    end
  end
  local now = os.time()
  for _, e in ipairs(log.entries()) do
    if e.error and now - (e.time or 0) < 86400 then
      add(("%s %s: %s"):format(os.date("%H:%M", e.time), e.mode or "request", e.error))
    end
  end
  return out
end

--- The newest log entries.
function M.requests(n)
  local out = {}
  for i, e in ipairs(log.entries()) do
    if i > n then
      break
    end
    table.insert(out, e)
  end
  return out
end

local function took(e)
  return e.duration_ms and ("%.1fs"):format(e.duration_ms / 1000) or ""
end

local function fenced(lines_or_text, ft)
  local text = type(lines_or_text) == "table" and table.concat(lines_or_text, "\n") or lines_or_text
  local fence = "```"
  while text:find(fence, 1, true) do
    fence = fence .. "`"
  end
  return ("%s%s\n%s\n%s"):format(fence, ft or "text", text, fence)
end

local function clip(text, n)
  text = text or ""
  if #text > n then
    return text:sub(1, n) .. ("\n… %d more bytes"):format(#text - n)
  end
  return text
end

--- Everything a report can carry, each with its issue section and its
--- local-only section. on = attached by default.
function M.attachments(ft)
  local env = M.environment(ft)
  local errors = M.errors()
  local requests = M.requests(config.report.requests)
  local atts = {
    {
      key = "env",
      label = "Environment",
      summary = env[1]:sub(3) .. ", " .. env[2]:sub(3),
      on = true,
      issue = function()
        return "### Environment\n\n" .. table.concat(M.environment(ft), "\n")
      end,
    },
    {
      key = "errors",
      label = "Recent errors",
      summary = #errors == 0 and "none" or (#errors == 1 and "1 error" or (#errors .. " errors")),
      on = #errors > 0,
      empty = #errors == 0,
      issue = function()
        return "### Recent errors\n\n" .. fenced(table.concat(errors, "\n\n"))
      end,
    },
    {
      key = "requests",
      label = "Recent requests",
      summary = #requests == 0 and "none" or ("last %d; prompts and answers go to the fixer only"):format(#requests),
      on = #requests > 0,
      empty = #requests == 0,
      issue = function()
        local rows =
          { "### Recent requests", "", "| When | Mode | Model | Took | Result |", "| --- | --- | --- | --- | --- |" }
        for _, e in ipairs(requests) do
          table.insert(
            rows,
            ("| %s | %s | %s | %s | %s |"):format(
              os.date("%m-%d %H:%M", e.time or 0),
              e.mode or "?",
              e.model or "",
              took(e),
              e.error and "error" or "ok"
            )
          )
        end
        return table.concat(rows, "\n")
      end,
      ["local"] = function()
        local parts = { "## Recent requests, newest first" }
        for i, e in ipairs(requests) do
          table.insert(
            parts,
            ("### %d. %s · %s · %s · %s"):format(
              i,
              os.date("%m-%d %H:%M", e.time or 0),
              e.mode or "?",
              e.model or "",
              e.error and "error" or took(e)
            )
          )
          if e.request then
            table.insert(parts, "What they asked:\n\n" .. fenced(clip(e.request, 2000)))
          end
          table.insert(parts, "Prompt Bud sent:\n\n" .. fenced(clip(e.prompt, 6000)))
          if e.error then
            table.insert(parts, "Error:\n\n" .. fenced(clip(e.error, 2000)))
          else
            table.insert(parts, "Answer:\n\n" .. fenced(clip(e.response, 4000)))
          end
        end
        return table.concat(parts, "\n\n")
      end,
    },
  }
  return atts
end

--- A title from the description: its first line, cut at a word near 72.
function M.title(desc)
  local first = vim.trim((desc or ""):match("^%s*([^\n]*)") or "")
  first = first:gsub("[%.:]$", "")
  if vim.fn.strchars(first) <= 72 then
    return first
  end
  local cut = vim.fn.strcharpart(first, 0, 71)
  local at = cut:match("^(.*%S)%s+%S*$")
  return (at and #at > 40 and at or cut) .. "…"
end

--- The issue body: the description, then each attached section.
function M.body(desc, atts)
  local parts = { vim.trim(desc) }
  for _, a in ipairs(atts) do
    if a.on and not a.empty then
      table.insert(parts, a.issue())
    end
  end
  table.insert(parts, "<sub>Filed from Neovim with Bud's reporter. bud-fix is working on a pull request for it.</sub>")
  return table.concat(parts, "\n\n") .. "\n"
end

--- What only the fixer sees.
function M.local_context(atts)
  local parts = {}
  for _, a in ipairs(atts) do
    if a.on and not a.empty and a["local"] then
      table.insert(parts, a["local"]())
    end
  end
  return table.concat(parts, "\n\n")
end

-- Running bud-fix

--- Flags every bud-fix run gets from Bud's config.
function M.common_args(src)
  local args = {
    "-repo",
    src,
    "-state",
    M.state_dir(),
    "-model",
    config.models.fix,
    "-claude",
    config.claude,
    "-system-file",
    (require("bud.instructions").path("fix", src)),
  }
  for _, def in ipairs(require("bud.tools").active()) do
    if def.kind == "bash" then
      for _, rule in ipairs(def.allow or {}) do
        vim.list_extend(args, { "-allow", rule })
      end
    end
  end
  return args
end

local function ready()
  if not config.report.enabled then
    return nil, "Reports are off (report.enabled in lua/config/bud.lua)"
  end
  if not util.executable(config.report.cmd) then
    return nil,
      ("%s isn't installed. chezmoi builds it from tools/ when Go is installed: run `chezmoi apply`."):format(
        config.report.cmd
      )
  end
  if not util.executable("gh") then
    return nil, "gh isn't installed, so Bud can't file the issue or open the PR"
  end
  local src = require("bud.spawn").chezmoi_source()
  if not src then
    return nil, "Can't find your dotfiles repo (`chezmoi source-path` failed)"
  end
  return src
end

--- Starts bud-fix detached: it outlives Neovim and reports through its
--- state file, so nothing is read from its output.
function M.spawn(args)
  local ok, err = pcall(vim.system, args, { detach = true, stdout = false, stderr = false }, function(out)
    if out.code == 2 then
      vim.schedule(function()
        say(
          ("bud-fix refused its arguments. Run `%s` in a shell to see why."):format(table.concat(args, " ")),
          vim.log.levels.ERROR
        )
      end)
    end
  end)
  if not ok then
    return nil, tostring(err)
  end
  M.started = os.time()
  M.watch()
  return true
end

--- Files a report. r = { kind, description, attachments }.
function M.submit(r)
  local desc = vim.trim(r.description or "")
  if desc == "" then
    return nil, r.kind == "bug" and "Describe the bug first" or "Describe the feature first"
  end
  local src, err = ready()
  if not src then
    return nil, err
  end
  local atts = r.attachments or {}
  local stamp = os.date("%Y%m%d-%H%M%S")
  local dir = M.reports_dir()
  local args = {
    config.report.cmd,
    "report",
    "-kind",
    r.kind,
    "-title",
    M.title(desc),
    "-body-file",
    util.write(("%s/%s-issue.md"):format(dir, stamp), M.body(desc, atts)),
  }
  local ctx = M.local_context(atts)
  if ctx ~= "" then
    vim.list_extend(args, { "-context-file", util.write(("%s/%s-local.md"):format(dir, stamp), ctx) })
  end
  vim.list_extend(args, M.common_args(src))
  local ok, spawn_err = M.spawn(args)
  if not ok then
    return nil, spawn_err
  end
  say(("Filing “%s”. Bud will work on it in the background."):format(M.title(desc)))
  return true
end

--- Runs the fixer on an issue that already exists.
function M.fix(issue)
  issue = tonumber(tostring(issue or ""):match("%d+"))
  if not issue then
    util.notify("Usage: :BudFix {issue number}", vim.log.levels.WARN)
    return
  end
  local src, err = ready()
  if not src then
    say(err, vim.log.levels.ERROR)
    return
  end
  local args = { config.report.cmd, "issue" }
  vim.list_extend(args, M.common_args(src))
  table.insert(args, tostring(issue))
  local ok, spawn_err = M.spawn(args)
  if not ok then
    say(spawn_err, vim.log.levels.ERROR)
    return
  end
  say(("Working on #%d in the background."):format(issue))
end

-- Following runs

local terminal = { done = true, no_change = true, failed = true }

local function alive(pid)
  if not pid or pid <= 0 then
    return false
  end
  local ok = vim.uv.kill(pid, 0)
  return ok == 0
end

--- Every recorded run, newest first. A run whose process died before it
--- finished reads as failed.
function M.runs()
  local out = {}
  for _, path in ipairs(vim.fn.glob(M.state_dir() .. "/*.json", false, true)) do
    local data = util.read(path)
    local ok, run = pcall(vim.json.decode, data or "", { luanil = { object = true, array = true } })
    if ok and type(run) == "table" and run.id then
      if not terminal[run.phase] and not alive(run.pid) then
        run.phase, run.error = "failed", "stopped before it finished"
      end
      table.insert(out, run)
    end
  end
  table.sort(out, function(a, b)
    return a.id > b.id
  end)
  return out
end

function M.active()
  return vim.tbl_filter(function(r)
    return not terminal[r.phase]
  end, M.runs())
end

local function seen_path()
  return util.dir("state") .. "/fixes-seen.json"
end

local function load_seen()
  local ok, seen = pcall(vim.json.decode, util.read(seen_path()) or "{}")
  return ok and type(seen) == "table" and seen or {}
end

local function mark_seen(id)
  local seen = load_seen()
  if seen[id] then
    return false
  end
  seen[id] = true
  util.write(seen_path(), vim.json.encode(seen))
  return true
end

function M.label(run)
  if run.issue then
    return ("#%d"):format(run.issue)
  end
  return "“" .. util.truncate(run.title or "report", 30) .. "”"
end

--- The message for a finished run.
function M.outcome(run)
  local what = M.label(run)
  if run.phase == "done" and run.pr_url then
    if run.draft then
      return ("Draft PR #%d for %s: the tests fail, so it needs a look.\n%s"):format(run.pr, what, run.pr_url),
        vim.log.levels.WARN
    end
    return ("PR #%d for %s is ready for review.\n%s"):format(run.pr, what, run.pr_url), vim.log.levels.INFO
  elseif run.phase == "done" then
    return ("%s: %s"):format(what, run.detail or "done"), vim.log.levels.INFO
  elseif run.phase == "no_change" then
    return ("Bud looked into %s and changed nothing. Its notes are on the issue."):format(what), vim.log.levels.INFO
  end
  return ("The fix for %s failed: %s\n:BudFixes has the log."):format(what, run.error or "unknown error"),
    vim.log.levels.ERROR
end

M.known = {}
-- runs with an id from here on started while this Neovim was open
M.since = os.date("%Y%m%d-%H%M%S")
local timer

--- Compares every run with what Bud saw last time and says what changed.
--- Returns true while any run is still going.
function M.poll()
  local any_active = false
  for _, run in ipairs(M.runs()) do
    local prev = M.known[run.id]
    local recent = run.id >= M.since
    if not terminal[run.phase] then
      any_active = true
      if run.issue and not (prev and prev.issue) and (prev or recent) then
        say(("Filed %s. Bud is working on it in the background."):format(M.label(run)))
      end
    elseif (prev and not terminal[prev.phase] or not prev and recent) and mark_seen(run.id) then
      local msg, level = M.outcome(run)
      say(msg, level, run.id)
    end
    M.known[run.id] = { id = run.id, phase = run.phase, issue = run.issue }
  end
  require("bud.ui.statusline").refresh()
  return any_active
end

--- Polls once a second while a run is going, then stops.
function M.watch()
  if timer then
    return
  end
  timer = vim.uv.new_timer()
  timer:start(
    200,
    1000,
    vim.schedule_wrap(function()
      -- a run's state file can take a moment to appear after the spawn
      if not M.poll() and timer and (not M.started or os.time() - M.started > 10) then
        timer:stop()
        timer:close()
        timer = nil
      end
    end)
  )
end

--- On startup: follow runs still going, and mention (up to three) runs from
--- the last week that finished while Neovim was closed.
function M.startup()
  if not config.report.enabled then
    return
  end
  local week = os.date("%Y%m%d", os.time() - 7 * 86400)
  local told = 0
  local any_active = false
  for _, run in ipairs(M.runs()) do
    if terminal[run.phase] then
      if told < 3 and run.id >= week and mark_seen(run.id) then
        told = told + 1
        local msg, level = M.outcome(run)
        say(msg, level, run.id)
      end
    else
      any_active = true
    end
    M.known[run.id] = { id = run.id, phase = run.phase, issue = run.issue }
  end
  if any_active then
    M.watch()
  end
end

--- Statusline text for the newest run in progress, or nil.
function M.status()
  if not config.report.enabled then
    return nil
  end
  local run
  for _, r in pairs(M.known) do
    if not terminal[r.phase] and (not run or r.id > run.id) then
      run = r
    end
  end
  if not run then
    return nil
  end
  return config.icons.bug .. (run.issue and ("#%d "):format(run.issue) or "") .. run.phase
end

--- Stops a run in progress.
function M.cancel(run)
  if run and run.pid and not terminal[run.phase] then
    vim.uv.kill(run.pid, "sigterm")
    say(("Cancelling the fix for %s"):format(M.label(run)))
  end
end

local function view_lines(run)
  local lines = { "# " .. (run.title or "report"), "" }
  local function add(k, v)
    if v and v ~= "" then
      table.insert(lines, ("- **%s:** %s"):format(k, v))
    end
  end
  add("Status", run.phase .. (run.detail and run.detail ~= "" and (" · " .. run.detail) or ""))
  add("Issue", run.issue_url)
  add("Pull request", run.pr_url and (run.pr_url .. (run.draft and " (draft)" or "")))
  add("Tests", run.tests)
  add("Branch", run.branch)
  add("Worktree", run.worktree)
  add("Error", run.error)
  add("Claude session", run.session_id)
  if run.summary and run.summary ~= "" then
    vim.list_extend(lines, { "", "## Claude's notes", "" })
    vim.list_extend(lines, util.split_lines(run.summary))
  end
  local data = run.log and util.read(run.log)
  if data then
    local log_lines = util.split_lines(vim.trim(data))
    vim.list_extend(lines, { "", "## Log", "", "```text" })
    vim.list_extend(lines, vim.list_slice(log_lines, math.max(1, #log_lines - 59)))
    table.insert(lines, "```")
  end
  return lines
end

--- :BudFixes, a picker of recent runs. In a run's view: o opens the PR (or
--- the issue), c cancels a run in progress.
function M.list()
  local runs = M.runs()
  if #runs == 0 then
    util.notify("No reports yet. <leader>ar files one.")
    return
  end
  vim.ui.select(runs, {
    prompt = "Bud fixes",
    format_item = function(r)
      local where = r.issue and ("#%d"):format(r.issue) or ""
      if r.pr then
        where = where .. (" → PR #%d%s"):format(r.pr, r.draft and " draft" or "")
      end
      return ("%s  %-9s %-18s %s"):format(r.id:sub(5, 8) .. " " .. r.id:sub(10, 13), r.phase, where, r.title or "")
    end,
  }, function(run)
    if not run then
      return
    end
    local w, buf = require("bud.ui.win").view(view_lines(run), { title = "fix " .. M.label(run), ft = "markdown" })
    require("bud.ui.win").map(buf, {
      o = function()
        local url = run.pr_url or run.issue_url
        if url then
          vim.ui.open(url)
        end
      end,
      c = function()
        M.cancel(run)
        require("bud.ui.win").close(w)
      end,
    })
  end)
end

return M
