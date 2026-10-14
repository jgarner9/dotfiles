local config = require("bud.config")
local log = require("bud.log")
local report = require("bud.report")
local spawn = require("bud.spawn")
local statusline = require("bud.ui.statusline")
local ui = require("bud.ui.report")
local util = require("bud.util")

-- the way the real keymap calls it, so startinsert applies
vim.keymap.set("n", "<F6>", ui.open)

-- records its arguments and copies the files it was handed
local fake_bud_fix = [=[#!/usr/bin/env bash
out="$BUD_TEST_WORK/budfix"
printf '%s\n' "$@" >"$out.args.tmp"
prev=""
for a in "$@"; do
	case "$prev" in
	-body-file) cp "$a" "$out-body.md" ;;
	-context-file) cp "$a" "$out-local.md" ;;
	esac
	prev=$a
done
mv "$out.args.tmp" "$out.args"
exit "${FAKE_BUDFIX_EXIT:-0}"
]=]

local function setup(T)
  ui.draft = nil
  report.known = {}
  T.bin("bud-fix", fake_bud_fix)
  T.bin("gh", "#!/bin/sh\nexit 0\n")
  spawn._source = T.project({ ["README.md"] = "dotfiles\n" }, true)
  for _, f in ipairs({ "budfix.args", "budfix-body.md", "budfix-local.md" }) do
    os.remove(T.work .. "/" .. f)
  end
  os.remove(log.path())
  log.add({
    mode = "quick",
    model = "haiku",
    request = "what is this",
    prompt = "SECRET-PROMPT",
    response = "SECRET-ANSWER",
    duration_ms = 1200,
  })
  log.add({ mode = "write", model = "haiku", request = "fill", prompt = "p", error = "Claude exited with code 1" })
  util.recent = {}
  util.notify("Bud boom", vim.log.levels.ERROR)
  vim.fn.mkdir(report.state_dir(), "p")
  for _, f in ipairs(vim.fn.glob(report.state_dir() .. "/*", false, true)) do
    os.remove(f)
  end
  os.remove(util.dir("state") .. "/fixes-seen.json")
  vim.fn.delete(report.reports_dir() .. "/chats", "rf")
end

local execute = vim.fn.execute

local function cleanup()
  vim.fn.execute = execute
  spawn._source = nil
  config.options.report.cmd = "bud-fix"
  vim.env.FAKE_BUDFIX_EXIT = nil
  ui.close()
end

local function case(name, fn)
  return {
    name,
    function(T)
      setup(T)
      local ok, err = xpcall(fn, debug.traceback, T)
      cleanup()
      if not ok then
        error(err, 0)
      end
    end,
  }
end

local function title_of(win)
  return table.concat(vim.tbl_map(function(c)
    return c[1]
  end, vim.api.nvim_win_get_config(win).title or {}))
end

local function wait_args(T)
  local path = T.work .. "/budfix.args"
  T.wait(function()
    return vim.uv.fs_stat(path) ~= nil
  end, 5000, "bud-fix started")
  return vim.split(vim.trim(util.read(path)), "\n", { plain = true })
end

local function flag(args, name)
  for i, a in ipairs(args) do
    if a == name then
      return args[i + 1]
    end
  end
end

local function write_run(run)
  run.log = run.log or (report.state_dir() .. "/" .. run.id .. ".log")
  util.write(report.state_dir() .. "/" .. run.id .. ".json", vim.json.encode(run))
end

local function messages(notes)
  return table.concat(
    vim.tbl_map(function(n)
      return n.msg
    end, notes),
    "\n---\n"
  )
end

return {
  case("the float: bug or feature, attachments to keep or drop, a kept draft", function(T)
    T.keys("<F6>")
    T.ok(ui.is_open())
    local S = ui._state()
    T.eq(S.kind, "bug")
    T.contains(title_of(S.win), "report · bug")
    T.contains(title_of(S.win), config.models.fix)
    local panel = vim.api.nvim_buf_get_lines(S.panel_buf, 0, -1, false)
    T.eq(#panel, 3)
    T.contains(panel[1], "Environment")
    T.contains(panel[1], "Neovim")
    T.contains(panel[2], "Recent errors")
    T.contains(panel[2], "2 errors")
    T.contains(panel[3], "prompts and answers go to the fixer only")

    T.keys("<Tab>")
    T.eq(S.kind, "feature")
    T.contains(title_of(S.win), "report · feature")
    T.keys("2")
    T.eq(S.atts[2].on, false)
    T.contains(vim.api.nvim_buf_get_lines(S.panel_buf, 1, 2, false)[1], "✗")
    T.keys("2")
    T.eq(S.atts[2].on, true)

    T.keys("ithe chat footer shows nil")
    T.keys("q")
    T.ok(not ui.is_open())
    T.eq(ui.draft, { text = "the chat footer shows nil", kind = "feature" })
    T.keys("<F6>")
    T.eq(vim.api.nvim_buf_get_lines(ui._state().buf, 0, -1, false), { "the chat footer shows nil" })
    T.eq(ui._state().kind, "feature")
  end),

  case("sending hands the report to bud-fix; prompts and answers stay off the issue", function(T)
    -- :messages, as Neovim keeps it after a Lua error in one of Bud's callbacks
    vim.fn.execute = function(cmd, ...)
      if cmd == "messages" then
        return table.concat({
          "",
          "some other plugin said hi",
          "Error executing lua callback: /x/lua/bud/ui/chat.lua:12: attempt to index nil",
          "stack traceback:",
          "\t/x/lua/bud/ui/chat.lua:12: in function 'send'",
          "next message",
        }, "\n")
      end
      return execute(cmd, ...)
    end
    local notes = T.notifications()
    T.keys("<F6>")
    T.keys("iWrite here put fences in my Go file<CR><CR>It happened twice.")
    T.keys("<CR>")
    local args = wait_args(T)
    T.ok(not ui.is_open())
    T.eq(ui.draft, nil)
    T.eq(args[1], "report")
    T.eq(flag(args, "-kind"), "bug")
    T.eq(flag(args, "-title"), "Write here put fences in my Go file")
    T.eq(flag(args, "-repo"), spawn._source)
    T.eq(flag(args, "-state"), report.state_dir())
    T.eq(flag(args, "-model"), "sonnet")
    T.eq(flag(args, "-claude"), config.claude)
    local system = util.read(flag(args, "-system-file"))
    T.contains(system, "# Working with Bud")
    T.contains(system, "You are Bud's fixer")
    T.contains(messages(notes), "Filing “Write here put fences in my Go file”")

    local body = util.read(T.work .. "/budfix-body.md")
    T.contains(body, "Write here put fences in my Go file\n\nIt happened twice.")
    T.contains(body, "### Environment")
    T.contains(body, "- Neovim " .. tostring(vim.version()))
    T.contains(body, "- Bud at ")
    T.contains(body, "### Recent errors")
    T.contains(body, "Bud boom")
    T.contains(
      body,
      "lua/bud/ui/chat.lua:12: attempt to index nil\nstack traceback:\n\t/x/lua/bud/ui/chat.lua:12: in function 'send'\n"
    )
    T.ok(not body:find("other plugin", 1, true))
    T.ok(not body:find("next message", 1, true))
    T.contains(body, "Claude exited with code 1")
    T.contains(body, "| quick | haiku | 1.2s | ok |")
    T.ok(not body:find("SECRET", 1, true), "prompts and answers stay local")
    local loc = util.read(T.work .. "/budfix-local.md")
    T.contains(loc, "SECRET-PROMPT")
    T.contains(loc, "SECRET-ANSWER")
    T.contains(loc, "what is this")
  end),

  case("dropped attachments are left out of both", function(T)
    T.keys("<F6>")
    T.keys("123")
    T.keys("iJust the words")
    T.keys("<CR>")
    wait_args(T)
    local body = util.read(T.work .. "/budfix-body.md")
    T.ok(not body:find("### ", 1, true), body)
    T.eq(vim.uv.fs_stat(T.work .. "/budfix-local.md"), nil)
  end),

  case("an empty report isn't sent; a missing bud-fix is explained", function(T)
    local notes = T.notifications()
    T.keys("<F6>")
    T.keys("<CR>")
    T.ok(ui.is_open(), "still open")
    T.contains(messages(notes), "Describe the bug first")
    T.keys("q")
    config.options.report.cmd = "bud-fix-nowhere"
    local ok, err = report.submit({ kind = "feature", description = "x", attachments = {} })
    T.eq(ok, nil)
    T.contains(err, "bud-fix-nowhere isn't installed")
  end),

  case("titles come from the first line, cut at a word", function(T)
    T.eq(report.title("Chat footer shows nil.\nMore here"), "Chat footer shows nil")
    local long = report.title(("word "):rep(30))
    T.ok(vim.fn.strchars(long) <= 72, long)
    T.match(long, "word…$")
  end),

  case(":BudFix works on an existing issue", function(T)
    vim.cmd("BudFix 7")
    local args = wait_args(T)
    T.eq(args[1], "issue")
    T.eq(args[#args], "7")
    T.eq(flag(args, "-repo"), spawn._source)
  end),

  case("the watcher follows a run into the statusline and says when the PR is up", function(T)
    local notes = T.notifications()
    local id = os.date("%Y%m%d-%H%M%S") .. "-abcd"
    local run = { id = id, pid = vim.fn.getpid(), kind = "bug", title = "Chat footer shows nil", phase = "filing" }
    write_run(run)
    T.ok(report.poll(), "active")
    T.contains(statusline.text(), config.icons.bug .. "filing")

    run.phase, run.issue, run.detail = "fixing", 12, "editing ui/chat.lua"
    write_run(run)
    report.poll()
    T.contains(messages(notes), "Filed #12")
    T.contains(statusline.text(), "#12 fixing")

    run.phase, run.pr, run.pr_url = "done", 14, "https://github.com/o/r/pull/14"
    write_run(run)
    T.ok(not report.poll(), "nothing active")
    T.contains(messages(notes), "PR #14 for #12 is ready for review.\nhttps://github.com/o/r/pull/14")
    T.ok(not statusline.text():find("#12", 1, true))
    local count = #notes
    report.poll()
    T.eq(#notes, count, "said once")
  end),

  case("drafts warn; a dead process reads as failed", function(T)
    local notes = T.notifications()
    local id = os.date("%Y%m%d-%H%M%S")
    local draft = { id = id .. "-aaaa", pid = vim.fn.getpid(), phase = "testing", issue = 3, title = "t" }
    local dead = { id = id .. "-bbbb", pid = 999999999, phase = "fixing", issue = 4, title = "u" }
    write_run(draft)
    report.poll()
    draft.phase, draft.pr, draft.pr_url, draft.draft = "done", 5, "https://github.com/o/r/pull/5", true
    write_run(draft)
    write_run(dead)
    report.poll()
    local text = messages(notes)
    T.contains(text, "Draft PR #5 for #3: the tests fail")
    T.contains(text, "The fix for #4 failed: stopped before it finished")
    local levels = vim.tbl_map(function(n)
      return n.level
    end, notes)
    T.ok(vim.tbl_contains(levels, vim.log.levels.WARN))
    T.ok(vim.tbl_contains(levels, vim.log.levels.ERROR))
  end),

  case("startup mentions runs that finished while Neovim was closed, once", function(T)
    local notes = T.notifications()
    write_run({
      id = os.date("%Y%m%d-%H%M%S") .. "-cccc",
      pid = 1,
      phase = "no_change",
      issue = 9,
      title = "Already works",
    })
    write_run({ id = "20200101-000000-dddd", pid = 1, phase = "done", issue = 1, pr = 2, pr_url = "u", title = "old" })
    report.startup()
    local text = messages(notes)
    T.contains(text, "Bud looked into #9 and changed nothing")
    T.ok(not text:find("PR #2", 1, true), "older than a week stays quiet")
    local count = #notes
    report.known = {}
    report.startup()
    T.eq(#notes, count, "said once")
  end),

  case("a report and its outcome land in the request log and the chat history", function(T)
    local history = require("bud.history")
    local root = util.root()
    for _, c in ipairs(history.list(root)) do
      history.delete(c)
    end
    T.keys("<F6>")
    T.keys("<Tab>")
    T.keys("iA test spawner for Go<CR><CR>Pick a function first.")
    T.keys("<CR>")
    wait_args(T)
    local e = log.entries()[1]
    T.eq(e.mode, "report")
    T.eq(e.request, "A test spawner for Go\n\nPick a function first.")
    T.contains(e.prompt, "### Environment")
    T.contains(e.response, "Filing “A test spawner for Go”")
    T.eq(#report.requests(10), 2, "the reporter's own entries aren't sent as requests")

    local chats = history.list(root)
    T.eq(#chats, 1)
    T.eq(chats[1].title, config.icons.feature .. "A test spawner for Go")
    T.contains(table.concat(chats[1].lines, "\n"), "feature request\n\nA test spawner for Go")

    local id = os.date("%Y%m%d-%H%M%S") .. "-eeee"
    local run = { id = id, pid = vim.fn.getpid(), kind = "feature", title = "A test spawner for Go", phase = "fixing" }
    write_run(run)
    report.poll()
    run.phase, run.issue, run.issue_url = "done", 14, "https://github.com/o/r/issues/14"
    run.pr, run.pr_url, run.summary = 15, "https://github.com/o/r/pull/15", "Added testgen.lua."
    write_run(run)
    report.poll()
    report.poll()
    local fixes = vim.tbl_filter(function(x)
      return x.mode == "fix"
    end, log.entries())
    T.eq(#fixes, 1, "logged once")
    T.eq(fixes[1].request, "A test spawner for Go")
    T.contains(fixes[1].prompt, "Pull request: https://github.com/o/r/pull/15")
    T.contains(fixes[1].response, "PR #15 for #14 is ready for review.")
    T.contains(fixes[1].response, "Added testgen.lua.")

    local chat = history.list(root)[1]
    local transcript = table.concat(chat.lines, "\n")
    T.contains(transcript, "PR #15 for #14 is ready for review.\nhttps://github.com/o/r/pull/15")
    T.contains(transcript, "### Claude's notes\n\nAdded testgen.lua.")
    history.delete(chat)
  end),

  case("a failed run is logged as an error", function(T)
    local id = os.date("%Y%m%d-%H%M%S") .. "-ffff"
    write_run({ id = id, pid = 999999999, phase = "fixing", issue = 4, title = "u" })
    report.poll()
    local e = log.entries()[1]
    T.eq(e.mode, "fix")
    T.contains(e.error, "The fix for #4 failed: stopped before it finished")
  end),
}
