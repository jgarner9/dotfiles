local M = {}

--- Project root: LazyVim's root when available (same as your pickers), else
--- the nearest git root, else the cwd.
function M.root(buf)
  buf = buf or 0
  local ok, lazyvim = pcall(function()
    return _G.LazyVim
  end)
  if ok and lazyvim and lazyvim.root then
    local r = lazyvim.root({ buf = buf })
    if r and r ~= "" then
      return r
    end
  end
  return vim.fs.root(buf, ".git") or vim.uv.cwd()
end

function M.relpath(path, root)
  if not path or path == "" then
    return "[No Name]"
  end
  root = root or M.root()
  local rel = vim.fs.relpath and vim.fs.relpath(root, path)
  if rel then
    return rel
  end
  return vim.fn.fnamemodify(path, ":~:.")
end

-- Bud's recent warnings and errors, newest last, for bug reports
M.recent = {}

function M.notify(msg, level, opts)
  level = level or vim.log.levels.INFO
  opts = vim.tbl_extend("force", { title = "Bud" }, opts or {})
  if level >= vim.log.levels.WARN then
    table.insert(M.recent, { time = os.time(), msg = msg, level = level })
    if #M.recent > 20 then
      table.remove(M.recent, 1)
    end
  end
  vim.notify(msg, level, opts)
end

function M.dir(kind)
  local dir = vim.fn.stdpath(kind) .. "/bud"
  vim.fn.mkdir(dir, "p")
  return dir
end

function M.read(path)
  local f = io.open(path, "r")
  if not f then
    return nil
  end
  local data = f:read("*a")
  f:close()
  return data
end

function M.write(path, data)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  local f = assert(io.open(path, "w"))
  f:write(data)
  f:close()
  return path
end

--- First executable among a name or list of names, or nil.
function M.executable(bins)
  if type(bins) == "string" then
    bins = { bins }
  end
  for _, b in ipairs(bins or {}) do
    if vim.fn.executable(b) == 1 then
      return b
    end
  end
end

function M.truncate(s, n)
  s = (s or ""):gsub("%s+", " ")
  s = vim.trim(s)
  if vim.fn.strchars(s) <= n then
    return s
  end
  return vim.fn.strcharpart(s, 0, n - 1) .. "…"
end

function M.split_lines(text)
  return vim.split(text or "", "\n", { plain = true })
end

--- Content of the first fenced code block, or the whole text trimmed.
--- Write here and the spawner use this so stray markdown never lands in a file.
function M.strip_fences(text)
  text = text or ""
  local body = text:match("```[^\n]*\n(.-)\n```")
  if body then
    return body
  end
  body = text:match("```[^\n]*\n(.*)$") -- unterminated fence (stream cut short)
  if body then
    return (body:gsub("\n?```%s*$", ""))
  end
  text = text:gsub("^%s*\n", ""):gsub("%s+$", "")
  return text
end

function M.filetype_of(path)
  local ft = vim.filetype.match({ filename = path })
  return ft or ""
end

function M.now()
  return os.time()
end

function M.uuid()
  local t = {}
  for i = 1, 16 do
    t[i] = math.random(0, 255)
  end
  t[7] = bit.bor(bit.band(t[7], 0x0f), 0x40)
  t[9] = bit.bor(bit.band(t[9], 0x3f), 0x80)
  local hex = {}
  for i = 1, 16 do
    hex[i] = string.format("%02x", t[i])
  end
  local s = table.concat(hex)
  return ("%s-%s-%s-%s-%s"):format(s:sub(1, 8), s:sub(9, 12), s:sub(13, 16), s:sub(17, 20), s:sub(21, 32))
end

return M
