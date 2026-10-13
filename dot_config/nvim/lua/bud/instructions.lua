-- Builds the instruction file every Claude process gets through
-- --append-system-prompt-file. Order:
--   1. bud/instructions/*.md in name order (00-base.md ships with Bud)
--   2. bud/instructions/tools/<tool>.md for each active tool
--   3. <repo>/.bud/rules.md, when the repo has one
--   4. the mode's own short instructions (lua/bud/prompts.lua)
local config = require("bud.config")
local prompts = require("bud.prompts")
local tools = require("bud.tools")
local util = require("bud.util")

local M = {}

--- Every file that goes in, in order, as { path, label }.
function M.files(root, opts)
  opts = opts or {}
  local dir = config.instructions_dir
  local out = {}
  local base = vim.fn.glob(dir .. "/*.md", false, true)
  table.sort(base)
  for _, p in ipairs(base) do
    table.insert(out, { path = p, label = vim.fn.fnamemodify(p, ":t") })
  end
  if opts.with_tools then
    for _, def in ipairs(tools.active()) do
      local p = def.doc or (dir .. "/tools/" .. def.name .. ".md")
      if vim.fn.filereadable(p) == 1 then
        table.insert(out, { path = p, label = "tools/" .. def.name .. ".md" })
      end
    end
  end
  if root then
    local rules = root .. "/.bud/rules.md"
    if vim.fn.filereadable(rules) == 1 then
      table.insert(out, { path = rules, label = ".bud/rules.md" })
    end
  end
  return out
end

--- The joined text for a kind of process. "chat" and "fix" also get the
--- tool docs; "spawn" and "fix" get their mode sections; "shared" (the warm
--- Haiku process used by quick ask, write here and name suggestions) gets
--- neither, because those modes send their instructions with each message
--- instead.
function M.text(mode, root)
  local parts = {}
  for _, f in ipairs(M.files(root, { with_tools = mode == "chat" or mode == "fix" })) do
    local body = util.read(f.path)
    if body and body:match("%S") then
      table.insert(parts, ("<!-- %s -->\n%s"):format(f.label, vim.trim(body)))
    end
  end
  if prompts.modes[mode] then
    table.insert(parts, ("<!-- mode: %s -->\n%s"):format(mode, vim.trim(prompts.modes[mode])))
  end
  return table.concat(parts, "\n\n") .. "\n"
end

--- Writes the joined text to the cache. Returns its path and a hash of the
--- text, so a warm process built from an older version can be spotted.
function M.path(mode, root)
  local text = M.text(mode, root)
  local name = ("instructions-%s-%s.md"):format(mode, vim.fn.sha256(root or ""):sub(1, 12))
  return util.write(util.dir("cache") .. "/" .. name, text), vim.fn.sha256(text)
end

return M
