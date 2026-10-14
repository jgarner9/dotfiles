-- @ mentions in the chat input. Typing @ opens a picker; the choice goes into
-- the message as a plain token, and tokens are expanded when it's sent:
--   @file:path           the file's contents (respecting .bud/ignore)
--   @file:path#L10-40    just those lines (what @sym inserts)
--   @buf:path            an open buffer, unsaved changes included
--   @diag  @diag:path    diagnostics for the file you came from (or path)
--   @diff                uncommitted changes (git diff HEAD)
-- Tokens are the source of truth, so what you see in the input is what goes.
local context = require("bud.context")
local util = require("bud.util")

local M = {}

M.max_bytes = 200 * 1024

M.kinds = {
  { key = "file", desc = "a file from the project" },
  { key = "sym", desc = "a symbol in the file you came from" },
  { key = "buf", desc = "an open buffer, unsaved changes included" },
  { key = "diag", desc = "diagnostics for the file you came from" },
  { key = "diff", desc = "uncommitted changes" },
  { key = "@", desc = "just type @" },
}

local known = { file = true, buf = true, diag = true, diff = true }

--- Every token in text: { kind, arg, raw }.
function M.parse(text)
  local out = {}
  for pos, kind, colon, arg in text:gmatch("()@(%a+)(:?)(%S*)") do
    local before = pos > 1 and text:sub(pos - 1, pos - 1) or " "
    arg = arg:gsub("[%.,;:!?%)]+$", "")
    if known[kind] and before:match("%s") and (colon == ":" or arg == "") then
      table.insert(out, { kind = kind, arg = arg ~= "" and arg or nil, raw = "@" .. kind .. colon .. arg })
    end
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

local function block(tag, header, lines, ft)
  local f = fence(lines)
  local out = { ("<context %s>"):format(tag), header, f .. (ft or "") }
  vim.list_extend(out, lines)
  vim.list_extend(out, { f, "</context>" })
  return table.concat(out, "\n")
end

local function abs(root, path)
  if path:sub(1, 1) == "/" then
    return path
  end
  if path:sub(1, 1) == "~" then
    return vim.fn.expand(path)
  end
  return root .. "/" .. path
end

local function file_block(root, arg, from_buffer)
  local path, first, last = arg:match("^(.-)#L(%d+)%-?L?(%d*)$")
  path = path or arg
  first, last = tonumber(first), tonumber(last)
  last = last or first
  local full = abs(root, path)
  local rel = util.relpath(full, root)
  if context.ignored(root, full) then
    return ("<context file>\n%s matches .bud/ignore; contents not sent.\n</context>"):format(rel), rel .. " (ignored)"
  end
  local lines
  if from_buffer then
    local buf = vim.fn.bufnr(full)
    if buf ~= -1 and vim.api.nvim_buf_is_loaded(buf) then
      lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    end
  end
  if not lines then
    local data = util.read(full)
    if not data then
      return nil, rel .. " (not found)"
    end
    if data:find("\0", 1, true) then
      return ("<context file>\n%s is binary; contents not sent.\n</context>"):format(rel), rel .. " (binary)"
    end
    local note
    if #data > M.max_bytes then
      data = data:sub(1, M.max_bytes)
      note = true
    end
    lines = vim.split(data, "\n", { plain = true })
    if lines[#lines] == "" then
      table.remove(lines)
    end
    if note then
      table.insert(lines, ("… truncated at %d KB"):format(M.max_bytes / 1024))
    end
  end
  local header = ("File: %s"):format(rel)
  local chip = rel
  if first then
    lines = vim.list_slice(lines, first, last)
    header = ("File: %s, lines %d–%d"):format(rel, first, last)
    chip = ("%s · L%d–%d"):format(rel, first, last)
  end
  return block(from_buffer and "buffer" or "file", header, lines, util.filetype_of(full)), chip
end

local function diag_block(root, arg, origin)
  local buf = origin
  if arg then
    buf = vim.fn.bufnr(abs(root, arg))
  end
  if not buf or buf == -1 or not vim.api.nvim_buf_is_valid(buf) then
    return nil, "diagnostics (no buffer)"
  end
  local rel = util.relpath(vim.api.nvim_buf_get_name(buf), root)
  local diags = context.diagnostics(buf)
  local lines = { "<context diagnostics>", ("Diagnostics for %s:"):format(rel) }
  if #diags == 0 then
    table.insert(lines, "(none)")
  end
  for _, d in ipairs(diags) do
    table.insert(
      lines,
      ("- L%d %s: %s%s"):format(d.lnum, d.severity, d.message, d.source and (" (" .. d.source .. ")") or "")
    )
  end
  table.insert(lines, "</context>")
  return table.concat(lines, "\n"), ("%d diagnostic%s in %s"):format(#diags, #diags == 1 and "" or "s", rel)
end

local function diff_block(root)
  local res = vim.system({ "git", "-C", root, "diff", "HEAD" }, { text = true }):wait(5000)
  if res.code ~= 0 then
    res = vim.system({ "git", "-C", root, "diff" }, { text = true }):wait(5000)
  end
  local out = res.stdout or ""
  if out == "" then
    return "<context diff>\nNo uncommitted changes.\n</context>", "git diff (clean)"
  end
  if #out > M.max_bytes then
    out = out:sub(1, M.max_bytes) .. "\n… truncated"
  end
  local lines = vim.split(out, "\n", { plain = true })
  return block("diff", "Uncommitted changes (git diff HEAD):", lines, "diff"), ("git diff · %d lines"):format(#lines)
end

--- Expands every token in text. Returns the context blocks and their chips.
function M.resolve(text, root, origin)
  local blocks, chips, seen = {}, {}, {}
  for _, t in ipairs(M.parse(text)) do
    if not seen[t.raw] then
      seen[t.raw] = true
      local b, chip
      if t.kind == "file" and t.arg then
        b, chip = file_block(root, t.arg, false)
      elseif t.kind == "buf" and t.arg then
        b, chip = file_block(root, t.arg, true)
      elseif t.kind == "diag" then
        b, chip = diag_block(root, t.arg, origin)
      elseif t.kind == "diff" then
        b, chip = diff_block(root)
      end
      if b then
        table.insert(blocks, b)
      end
      if chip then
        table.insert(chips, chip)
      end
    end
  end
  return blocks, chips
end

local function snacks()
  local ok, s = pcall(require, "snacks")
  return ok and s and s.picker and s or nil
end

local function item_path(item)
  local ok, putil = pcall(require, "snacks.picker.util")
  if ok and putil.path then
    return putil.path(item)
  end
  return item.file
end

local function pick_file(root, cb)
  local S = snacks()
  if S then
    S.picker.files({
      cwd = root,
      confirm = function(picker, item)
        picker:close()
        if item then
          cb("@file:" .. util.relpath(item_path(item), root))
        end
      end,
    })
  else
    vim.ui.input({ prompt = "File: ", completion = "file" }, function(p)
      if p and p ~= "" then
        cb("@file:" .. util.relpath(vim.fn.fnamemodify(p, ":p"), root))
      end
    end)
  end
end

local function pick_buf(root, cb)
  local S = snacks()
  if S then
    S.picker.buffers({
      confirm = function(picker, item)
        picker:close()
        if item then
          cb("@buf:" .. util.relpath(item_path(item), root))
        end
      end,
    })
    return
  end
  local items = {}
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    local name = vim.api.nvim_buf_get_name(b)
    if vim.bo[b].buflisted and name ~= "" then
      table.insert(items, util.relpath(name, root))
    end
  end
  vim.ui.select(items, { prompt = "Buffer" }, function(choice)
    if choice then
      cb("@buf:" .. choice)
    end
  end)
end

local function pick_sym(root, origin, cb)
  local S = snacks()
  if not S then
    util.notify("@sym needs snacks.nvim", vim.log.levels.WARN)
    return
  end
  local win = vim.fn.bufwinid(origin)
  local function open()
    S.picker.lsp_symbols({
      confirm = function(picker, item)
        picker:close()
        if item and item.pos then
          local first = item.pos[1]
          local last = item.end_pos and item.end_pos[1] or first
          cb(("@file:%s#L%d-%d"):format(util.relpath(item_path(item), root), first, last))
        end
      end,
    })
  end
  if win ~= -1 then
    vim.api.nvim_win_call(win, open)
  else
    open()
  end
end

--- Asks which kind of mention, then opens that picker. cb(token) gets the
--- text to insert (without a trailing space); cb(nil) on cancel.
function M.pick(root, origin, cb)
  vim.ui.select(M.kinds, {
    prompt = "Mention",
    format_item = function(k)
      return k.key == "@" and "@  just type @" or ("@%-5s %s"):format(k.key, k.desc)
    end,
  }, function(kind)
    if not kind then
      return cb(nil)
    end
    if kind.key == "@" then
      cb("@")
    elseif kind.key == "file" then
      pick_file(root, cb)
    elseif kind.key == "buf" then
      pick_buf(root, cb)
    elseif kind.key == "sym" then
      pick_sym(root, origin, cb)
    elseif kind.key == "diag" then
      cb("@diag")
    elseif kind.key == "diff" then
      cb("@diff")
    end
  end)
end

return M
