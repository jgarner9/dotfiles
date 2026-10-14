-- Deterministic context: what Bud sends about the code you're looking at.
-- Nothing here calls the model; every block is built from buffer state.
local config = require("bud.config")
local util = require("bud.util")

local M = {}

-- never sent, in any repo; add more per repo in .bud/ignore
M.default_ignore = { ".env", ".env.*", "*.pem", "*.key", "*.p12", "id_rsa*", "id_ed25519*", ".netrc" }

local severity = { "error", "warn", "info", "hint" }

local function patterns(root)
  local list = vim.deepcopy(M.default_ignore)
  local data = root and util.read(root .. "/.bud/ignore")
  for line in (data or ""):gmatch("[^\n]+") do
    line = vim.trim(line)
    if line ~= "" and not line:match("^#") then
      table.insert(list, line)
    end
  end
  return list
end

--- True when path (absolute or root-relative) matches .bud/ignore or the
--- built-in secret patterns. Patterns follow .gitignore loosely: no slash
--- matches the name anywhere, a trailing slash matches a directory.
function M.ignored(root, path)
  if not path or path == "" then
    return false
  end
  local rel = path
  if root and vim.startswith(path, root .. "/") then
    rel = path:sub(#root + 2)
  end
  for _, pat in ipairs(patterns(root)) do
    local anchored = pat:sub(1, -2):find("/", 1, true) ~= nil
    local p = pat:gsub("^/", "")
    if p:sub(-1) == "/" then
      p = p .. "**"
    end
    if not anchored then
      p = "**/" .. p
    end
    local ok, lpeg = pcall(vim.glob.to_lpeg, p)
    if ok and (lpeg:match(rel) or lpeg:match("/" .. rel)) then
      return true
    end
  end
  return false
end

function M.diagnostics(buf, first, last)
  local out = {}
  for _, d in ipairs(vim.diagnostic.get(buf)) do
    local lnum = d.lnum + 1
    if (not first or lnum >= first) and (not last or lnum <= last) then
      table.insert(out, {
        lnum = lnum,
        severity = severity[d.severity] or "info",
        message = (d.message or ""):gsub("\n", " "),
        source = d.source,
      })
    end
  end
  table.sort(out, function(a, b)
    return a.lnum < b.lnum
  end)
  return out
end

local function file_info(buf, root)
  local path = vim.api.nvim_buf_get_name(buf)
  return {
    buf = buf,
    path = path,
    rel = util.relpath(path, root),
    ft = vim.bo[buf].filetype,
    root = root,
  }
end

--- What the window shows: the visible lines, cursor and diagnostics in view.
function M.view(win)
  win = win or vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_win_get_buf(win)
  local root = util.root(buf)
  local ctx = file_info(buf, root)
  ctx.kind = "view"
  local top, bot = unpack(vim.api.nvim_win_call(win, function()
    return { vim.fn.line("w0"), vim.fn.line("w$") }
  end))
  local max = config.chat.max_view_lines
  if bot - top + 1 > max then
    bot = top + max - 1
  end
  ctx.first, ctx.last = top, bot
  ctx.cursor = vim.api.nvim_win_get_cursor(win)[1]
  ctx.lines = vim.api.nvim_buf_get_lines(buf, top - 1, bot, false)
  ctx.diagnostics = M.diagnostics(buf, top, bot)
  ctx.ignored = M.ignored(root, ctx.path)
  return ctx
end

--- The current visual selection, read while still in visual mode.
--- Returns nil outside visual mode.
function M.selection()
  local mode = vim.fn.mode()
  if not mode:match("^[vV\22]") then
    return nil
  end
  local buf = vim.api.nvim_get_current_buf()
  local a, b = vim.fn.getpos("v"), vim.fn.getpos(".")
  if a[2] > b[2] or (a[2] == b[2] and a[3] > b[3]) then
    a, b = b, a
  end
  local ctx = file_info(buf, util.root(buf))
  ctx.kind = "selection"
  ctx.vmode = mode
  ctx.first, ctx.last = a[2], b[2]
  ctx.lines = vim.fn.getregion(a, b, { type = mode })
  ctx.full_lines = vim.api.nvim_buf_get_lines(buf, ctx.first - 1, ctx.last, false)
  ctx.text = table.concat(ctx.lines, "\n")
  ctx.diagnostics = M.diagnostics(buf, ctx.first, ctx.last)
  ctx.ignored = M.ignored(ctx.root, ctx.path)
  return ctx
end

local function range(first, last)
  if first == last then
    return ("L%d"):format(first)
  end
  return ("L%d–%d"):format(first, last)
end

--- One-line summary of a context, shown in the UI exactly as sent.
function M.chip(ctx)
  local parts = { config.icons.file .. ctx.rel, range(ctx.first, ctx.last) }
  local n = #(ctx.diagnostics or {})
  if n > 0 then
    table.insert(parts, ("%d diagnostic%s"):format(n, n == 1 and "" or "s"))
  end
  if ctx.ignored then
    table.insert(parts, "ignored")
  end
  return table.concat(parts, " · ")
end

local function numbered(lines, first)
  local out = {}
  local width = #tostring(first + #lines - 1)
  for i, l in ipairs(lines) do
    out[i] = ("%" .. width .. "d  %s"):format(first + i - 1, l)
  end
  return out
end

local function fence(lines)
  local longest = 2
  for _, l in ipairs(lines) do
    for run in l:gmatch("`+") do
      longest = math.max(longest, #run)
    end
  end
  return ("`"):rep(longest + 1)
end

--- The context block for a view or selection, as Markdown.
function M.format(ctx)
  local out = {}
  local what = ctx.kind == "view" and "visible in the editor" or "selected"
  table.insert(out, ("<context %s>"):format(ctx.kind))
  table.insert(
    out,
    ("File: %s (%s), lines %d–%d %s."):format(
      ctx.rel,
      ctx.ft ~= "" and ctx.ft or "no filetype",
      ctx.first,
      ctx.last,
      what
    )
  )
  if ctx.cursor then
    table.insert(out, ("Cursor on line %d."):format(ctx.cursor))
  end
  if ctx.ignored then
    table.insert(out, "Contents not sent: the file matches .bud/ignore.")
  else
    local body = numbered(ctx.full_lines or ctx.lines, ctx.first)
    local f = fence(body)
    table.insert(out, f .. (ctx.ft or ""))
    vim.list_extend(out, body)
    table.insert(out, f)
  end
  if ctx.diagnostics and #ctx.diagnostics > 0 then
    table.insert(out, "Diagnostics:")
    for _, d in ipairs(ctx.diagnostics) do
      table.insert(
        out,
        ("- L%d %s: %s%s"):format(d.lnum, d.severity, d.message, d.source and (" (" .. d.source .. ")") or "")
      )
    end
  end
  table.insert(out, "</context>")
  return table.concat(out, "\n")
end

--- Code around a row for write here, with a marker where the output goes.
--- sel: { first, last } (1-based, inclusive) when replacing a selection.
function M.surrounding(buf, row, sel)
  local n = config.write.surrounding_lines
  local count = vim.api.nvim_buf_line_count(buf)
  local first = sel and sel.first or row
  local last = sel and sel.last or row
  local from = math.max(1, first - n)
  local to = math.min(count, last + n)
  local out = {}
  for i, l in ipairs(vim.api.nvim_buf_get_lines(buf, from - 1, to, false)) do
    local lnum = from + i - 1
    if sel and lnum == first then
      table.insert(out, "<<<SELECTION START>>>")
    end
    if not sel and lnum == row then
      table.insert(out, "<<<INSERT HERE>>>")
    end
    table.insert(out, l)
    if sel and lnum == last then
      table.insert(out, "<<<SELECTION END>>>")
    end
  end
  return table.concat(out, "\n")
end

--- The repo map for the top of a new chat, or nil when repomap is missing.
function M.repomap(root)
  local tools = config.tools or {}
  if not (tools.repomap and tools.repomap.enabled) or not util.executable("repomap") then
    return nil
  end
  local ok, res = pcall(function()
    return vim.system({ "repomap", "-root", root, "-max", "40" }, { text = true }):wait(3000)
  end)
  if not ok or res.code ~= 0 or not res.stdout or res.stdout == "" then
    return nil
  end
  return ("<repomap>\n%s</repomap>"):format(res.stdout)
end

return M
