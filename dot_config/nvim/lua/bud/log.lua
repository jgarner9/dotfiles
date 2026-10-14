-- The request log: every prompt Bud sends and every answer it gets back, one
-- JSON object per line in stdpath("data")/bud/log.jsonl. :BudLog browses it.
local config = require("bud.config")
local util = require("bud.util")

local M = {}

function M.path()
  return util.dir("data") .. "/log.jsonl"
end

--- Appends one entry. Fields: mode, model, root, prompt, response, usage,
--- cost, duration_ms, error, session_id.
function M.add(entry)
  if not config.log.enabled then
    return
  end
  entry.time = entry.time or util.now()
  local ok, line = pcall(vim.json.encode, entry)
  if not ok then
    return
  end
  local f = io.open(M.path(), "a")
  if f then
    f:write(line, "\n")
    f:close()
  end
end

--- All entries, newest first.
function M.entries()
  local data = util.read(M.path())
  local out = {}
  if not data then
    return out
  end
  for line in data:gmatch("[^\n]+") do
    local ok, e = pcall(vim.json.decode, line, { luanil = { object = true, array = true } })
    if ok and type(e) == "table" then
      table.insert(out, 1, e)
    end
  end
  return out
end

--- Keeps the newest max_entries lines once the file grows 20% past that.
function M.trim()
  local data = util.read(M.path())
  if not data then
    return
  end
  local lines = vim.split(data, "\n", { plain = true, trimempty = true })
  local max = config.log.max_entries
  if #lines <= math.floor(max * 1.2) then
    return
  end
  util.write(M.path(), table.concat(vim.list_slice(lines, #lines - max + 1), "\n") .. "\n")
end

local function label(e)
  local first = (e.request or e.prompt or ""):match("[^\n]*") or ""
  return ("%s  %-5s %-7s %s%s"):format(
    os.date("%m-%d %H:%M", e.time or 0),
    e.mode or "?",
    e.model or "",
    e.error and "✗ " or "",
    util.truncate(first, 70)
  )
end

--- Markdown for one entry, as shown by :BudLog.
function M.render(e)
  local lines = {
    ("# %s · %s"):format(e.mode or "request", e.model or ""),
    "",
    ("`%s` · `%s`%s"):format(
      os.date("%Y-%m-%d %H:%M:%S", e.time or 0),
      e.root and vim.fn.fnamemodify(e.root, ":~") or "",
      e.duration_ms and (" · %.1fs"):format(e.duration_ms / 1000) or ""
    ),
  }
  if e.usage then
    table.insert(
      lines,
      ("`%s in · %s out%s`"):format(
        e.usage.input_tokens or 0,
        e.usage.output_tokens or 0,
        e.cost and (" · $%.4f"):format(e.cost) or ""
      )
    )
  end
  vim.list_extend(lines, { "", "## Prompt", "", "````text" })
  vim.list_extend(lines, util.split_lines(e.prompt or ""))
  vim.list_extend(lines, { "````", "", e.error and "## Error" or "## Response", "", "````text" })
  vim.list_extend(lines, util.split_lines(e.error or e.response or ""))
  table.insert(lines, "````")
  return lines
end

function M.open()
  local entries = M.entries()
  if #entries == 0 then
    util.notify("The request log is empty")
    return
  end
  vim.ui.select(entries, {
    prompt = "Bud log",
    format_item = label,
  }, function(e)
    if e then
      require("bud.ui.win").view(M.render(e), { title = "log", ft = "markdown" })
    end
  end)
end

return M
