-- The test spawner: from a Go source file, pick a function (or the whole
-- file), say what to cover, and Bud writes <file>_test.go next to it, runs
-- go vet and go test, retries once with the errors, and opens the result.
-- An existing test file is extended, never replaced. Generation, checks and
-- the result float are the script spawner's (spawn.lua); only Go for now.
-- Each run is in the request log as a "test" request and in :BudHistory as a
-- chat with the request and the test file.
local config = require("bud.config")
local history = require("bud.history")
local spawn = require("bud.spawn")
local util = require("bud.util")

local M = {}

--- The funcs and methods in Go source lines: { name, label, line }.
function M.funcs(lines)
  local out = {}
  for i, text in ipairs(lines) do
    local recv, name = text:match("^func%s+(%b())%s*([%w_]+)")
    if not name then
      name = text:match("^func%s+([%w_]+)")
    end
    if name and name ~= "init" then
      local label = recv and (recv:gsub("^%(%s*[%w_]*%s*", ""):gsub("%s*%)$", "") .. "." .. name) or name
      table.insert(out, { name = name, label = label, line = i })
    end
  end
  return out
end

--- Where the tests go: foo.go -> foo_test.go, in the same package directory.
function M.target(path, root)
  local dir = vim.fs.dirname(path)
  local base = vim.fn.fnamemodify(path, ":t:r") .. "_test"
  return {
    path = dir .. "/" .. base .. ".go",
    kind = "go",
    test = true,
    bin = false,
    name = base .. ".go",
    base = base,
    cwd = dir,
    root = root,
  }
end

--- The request: the source, what to cover, and the current tests if any.
function M.describe(src, code, focus, notes, existing)
  local lines = {
    "Write Go tests for " .. (focus and ("the function `" .. focus .. "` in") or "the code in") .. " " .. src .. ":",
    "```go",
    code,
    "```",
  }
  if notes and notes ~= "" then
    vim.list_extend(lines, { "", "Cover in particular: " .. notes })
  end
  if existing then
    vim.list_extend(lines, {
      "",
      "The test file already exists. Keep every test in it and add the new ones; reply with the whole file:",
      "```go",
      existing,
      "```",
    })
  end
  return table.concat(lines, "\n")
end

local function say(msg, level)
  util.notify(msg, level, { id = "bud_spawn", title = "Bud spawner" })
end

--- The user's own words for the log and the chat history.
function M.request(src, focus, notes)
  local text = ("Tests for %s in %s"):format(focus and ("`" .. focus .. "`") or "the whole file", src)
  if notes and notes ~= "" then
    text = text .. ": " .. notes
  end
  return text
end

--- A run as a chat in :BudHistory: what was asked, what was written.
function M.save_history(t, request, ok, results)
  local code = util.read(t.path)
  if not code then
    return
  end
  local summary = vim.tbl_map(function(r)
    return (r.ok and config.icons.ok or "✗") .. " " .. r.name
  end, results or {})
  local lines = { "## " .. config.icons.you .. "You", "" }
  vim.list_extend(lines, util.split_lines(request))
  vim.list_extend(lines, { "", "## " .. config.icons.bud .. "Bud", "" })
  table.insert(
    lines,
    ("%s `%s`%s"):format(
      ok and config.icons.ok or config.icons.warn,
      util.relpath(t.path, t.root),
      #summary > 0 and (" · " .. table.concat(summary, " · ")) or ""
    )
  )
  vim.list_extend(lines, { "", "```go" })
  vim.list_extend(lines, util.split_lines(vim.trim(code)))
  vim.list_extend(lines, { "```", "" })
  history.save({
    id = util.uuid(),
    root = t.root,
    title = request,
    model = config.models.spawn,
    lines = lines,
  })
end

--- Function picker, prompts, then generation.
function M.open()
  local buf = vim.api.nvim_get_current_buf()
  local path = vim.api.nvim_buf_get_name(buf)
  if not path:match("%.go$") or path:match("_test%.go$") then
    return say("Open a Go source file (not a _test.go) to write tests for it", vim.log.levels.WARN)
  end
  local root = util.root(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local funcs = M.funcs(lines)
  local cursor = vim.api.nvim_win_get_cursor(0)[1]
  local choices = {}
  local near
  for _, f in ipairs(funcs) do
    if f.line <= cursor then
      near = f
    end
  end
  if near then
    table.insert(choices, 1, near)
  end
  for _, f in ipairs(funcs) do
    if f ~= near then
      table.insert(choices, f)
    end
  end
  table.insert(choices, { label = "Whole file" })
  vim.ui.select(choices, {
    prompt = "Write tests for",
    format_item = function(c)
      return c.label
    end,
  }, function(choice)
    if not choice then
      return
    end
    vim.ui.input({ prompt = "Cover (Enter = normal cases, edges and errors) " }, function(notes)
      if notes == nil then
        return
      end
      notes = vim.trim(notes)
      local src = util.relpath(path, root)
      local t = M.target(path, root)
      t.request = M.request(src, choice.name, notes)
      local existing = util.read(t.path)
      local desc = M.describe(src, table.concat(lines, "\n"), choice.name, notes, existing)
      spawn.generate(desc, t, function(ok, results)
        M.save_history(t, t.request, ok, results)
      end)
    end)
  end)
end

return M
