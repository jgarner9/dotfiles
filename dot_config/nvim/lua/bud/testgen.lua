-- The test spawner: from a Go source file, pick a function (or the whole
-- file), say what to cover, and Bud writes <file>_test.go next to it, runs
-- go vet and go test, retries once with the errors, and opens the result.
-- An existing test file is extended, never replaced. Generation, checks and
-- the result float are the script spawner's (spawn.lua); only Go for now.
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
  local choices = { { label = "Whole file" } }
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
      local t = M.target(path, root)
      local existing = util.read(t.path)
      local desc = M.describe(util.relpath(path, root), table.concat(lines, "\n"), choice.name, vim.trim(notes), existing)
      spawn.generate(desc, t)
    end)
  end)
end

return M
