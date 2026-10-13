-- Write here: Haiku writes code at the cursor (normal mode) or in place of
-- the selection (visual mode). The output streams in as a pending preview;
-- nothing touches the buffer until <CR> keeps it. <Esc> drops it, and u
-- still undoes a kept change.
local box = require("bud.ui.box")
local config = require("bud.config")
local context = require("bud.context")
local provider = require("bud.provider")
local util = require("bud.util")
local win = require("bud.ui.win")

local M = {}

local ns = vim.api.nvim_create_namespace("bud_write")

-- the pending preview, one at a time
M.pending = nil

--- Display width of a line's indent.
local function indent_width(line, ts)
  local w = 0
  for c in line:match("^[ \t]*"):gmatch(".") do
    if c == "\t" then
      w = w + ts - (w % ts)
    else
      w = w + 1
    end
  end
  return w
end

local function make_indent(width, buf)
  if vim.bo[buf].expandtab then
    return (" "):rep(width)
  end
  local ts = vim.bo[buf].tabstop
  return ("\t"):rep(math.floor(width / ts)) .. (" "):rep(width % ts)
end

--- Shifts lines so their smallest indent is `target`, but only when the
--- model returned them flush left; otherwise its indentation is kept.
function M.reindent(lines, target, buf)
  local ts = vim.bo[buf].tabstop
  local min
  for _, l in ipairs(lines) do
    if l:match("%S") then
      local w = indent_width(l, ts)
      min = min and math.min(min, w) or w
    end
  end
  if not min or min ~= 0 or target == 0 then
    return lines
  end
  local prefix = make_indent(target, buf)
  local out = {}
  for i, l in ipairs(lines) do
    out[i] = l:match("%S") and (prefix .. l) or l
  end
  return out
end

--- The code to insert from a (possibly partial) answer.
function M.extract(text)
  local code = util.strip_fences(text)
  local lines = util.split_lines(code)
  while #lines > 0 and lines[1]:match("^%s*$") do
    table.remove(lines, 1)
  end
  while #lines > 0 and lines[#lines]:match("^%s*$") do
    table.remove(lines)
  end
  return lines
end

local function display(lines, buf)
  local ts = vim.bo[buf].tabstop
  local out = {}
  for i, l in ipairs(lines) do
    local s = l:gsub("\t", (" "):rep(ts))
    out[i] = { { s, "BudPendingAdd" } }
  end
  return out
end

-- indent the filetype expects on an empty line: indentexpr, then cindent,
-- then the line above plus one level when it opens a block
local function expected_indent(buf, row)
  local ie = vim.bo[buf].indentexpr
  if ie ~= "" then
    local ok, v = pcall(vim.api.nvim_buf_call, buf, function()
      vim.v.lnum = row
      return vim.fn.eval(ie)
    end)
    if ok and tonumber(v) and tonumber(v) >= 0 then
      return tonumber(v)
    end
  end
  if vim.bo[buf].cindent then
    return vim.api.nvim_buf_call(buf, function()
      return vim.fn.cindent(row)
    end)
  end
  local prev = vim.fn.prevnonblank(row - 1)
  if prev == 0 then
    return 0
  end
  local line = vim.api.nvim_buf_get_lines(buf, prev - 1, prev, false)[1]
  local base = indent_width(line, vim.bo[buf].tabstop)
  local opens = line:match("[{(%[:]%s*$")
    or line:match("%f[%w]then%s*$")
    or line:match("%f[%w]do%s*$")
    or line:match("%f[%w]else%s*$")
    or line:match("function%s*[%w_.:]*%b()%s*$")
  return base + (opens and vim.fn.shiftwidth() or 0)
end

local function target_indent(buf, p)
  local ts = vim.bo[buf].tabstop
  if p.sel then
    local min
    for _, l in ipairs(vim.api.nvim_buf_get_lines(buf, p.first - 1, p.last, false)) do
      if l:match("%S") then
        local w = indent_width(l, ts)
        min = min and math.min(min, w) or w
      end
    end
    return min or 0
  end
  local line = vim.api.nvim_buf_get_lines(buf, p.row - 1, p.row, false)[1] or ""
  if line:match("%S") or line ~= "" then
    -- a code line, or a blank line that already carries its indent
    return indent_width(line, ts)
  end
  return expected_indent(buf, p.row)
end

local function render(p)
  if not vim.api.nvim_buf_is_valid(p.buf) then
    return
  end
  local virt = display(p.lines, p.buf)
  local hint
  if p.done then
    hint = { { " " .. config.icons.write .. "<CR> keep · <Esc> drop ", "BudPendingHint" } }
  elseif p.error then
    hint = { { " " .. config.icons.warn .. " " .. p.error .. " · <Esc> close ", "BudError" } }
  else
    hint = { { " " .. win.spinner() .. " writing with " .. p.model .. " · <C-c> cancel ", "BudPendingHint" } }
  end
  table.insert(virt, hint)
  local mark = vim.api.nvim_buf_get_extmark_by_id(p.buf, ns, p.anchor, { details = true })
  if not mark or not mark[1] then
    return
  end
  local opts = {
    id = p.anchor,
    virt_lines = virt,
    virt_lines_above = false,
  }
  if p.sel then
    opts.end_row = mark[3].end_row
    opts.end_col = mark[3].end_col
    opts.hl_group = "BudPendingOld"
    opts.hl_eol = true
    -- the preview hangs below the selection's last line
    local end_mark = vim.api.nvim_buf_get_extmark_by_id(p.buf, ns, p.tail, {})
    vim.api.nvim_buf_set_extmark(p.buf, ns, end_mark[1], 0, { id = p.tail, virt_lines = virt })
    opts.virt_lines = nil
  end
  vim.api.nvim_buf_set_extmark(p.buf, ns, mark[1], mark[2], opts)
end

local saved = {}

local function save_maps(buf)
  saved[buf] = {}
  for _, lhs in ipairs({ "<CR>", "<Esc>", "<C-c>" }) do
    local m = vim.fn.maparg(lhs, "n", false, true)
    if m and m.buffer == 1 then
      saved[buf][lhs] = m
    end
  end
end

local function restore_maps(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  for _, lhs in ipairs({ "<CR>", "<Esc>", "<C-c>" }) do
    pcall(vim.keymap.del, "n", lhs, { buffer = buf })
    local m = saved[buf] and saved[buf][lhs]
    if m then
      vim.api.nvim_buf_call(buf, function()
        vim.fn.mapset("n", false, m)
      end)
    end
  end
  saved[buf] = nil
end

local function finish(p)
  if p.finished then
    return
  end
  p.finished = true
  if p.timer and not p.timer:is_closing() then
    p.timer:stop()
    p.timer:close()
  end
  if p.handle and not p.done then
    p.handle.cancel()
  end
  if vim.api.nvim_buf_is_valid(p.buf) then
    vim.api.nvim_buf_clear_namespace(p.buf, ns, 0, -1)
  end
  restore_maps(p.buf)
  if M.pending == p then
    M.pending = nil
  end
end

--- Keeps the preview: one change, so u undoes it.
function M.keep(p)
  p = p or M.pending
  if not p or not p.done then
    return
  end
  local buf = p.buf
  local lines = M.reindent(p.lines, target_indent(buf, p), buf)
  local mark = vim.api.nvim_buf_get_extmark_by_id(buf, ns, p.anchor, { details = true })
  finish(p)
  if not mark or not mark[1] or #lines == 0 then
    return
  end
  if p.sel then
    vim.api.nvim_buf_set_lines(buf, mark[1], mark[3].end_row + 1, false, lines)
  else
    local row = mark[1]
    local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
    if line:match("^%s*$") then
      vim.api.nvim_buf_set_lines(buf, row, row + 1, false, lines)
    else
      vim.api.nvim_buf_set_lines(buf, row + 1, row + 1, false, lines)
    end
  end
end

function M.drop(p)
  p = p or M.pending
  if p then
    finish(p)
  end
end

local function build(p, request)
  local buf = p.buf
  local rel = util.relpath(vim.api.nvim_buf_get_name(buf), p.root)
  local ft = vim.bo[buf].filetype
  local around = context.surrounding(buf, p.row, p.sel and { first = p.first, last = p.last } or nil)
  local task
  if p.sel then
    task = "Replace the code between <<<SELECTION START>>> and <<<SELECTION END>>>. Reply with the full replacement."
  else
    task = "Write code to insert at <<<INSERT HERE>>>."
  end
  return table.concat({
    ("File: %s (%s)"):format(rel, ft ~= "" and ft or "no filetype"),
    "```" .. ft,
    around,
    "```",
    "",
    task,
    "Request: " .. request,
  }, "\n")
end

function M.start(p, request)
  M.pending = p
  save_maps(p.buf)
  local function map(lhs, fn)
    vim.keymap.set("n", lhs, fn, { buffer = p.buf, nowait = true, silent = true, desc = "Bud write here" })
  end
  map("<CR>", function()
    if p.done then
      M.keep(p)
    end
  end)
  map("<Esc>", function()
    M.drop(p)
  end)
  map("<C-c>", function()
    if not p.done then
      M.drop(p)
    end
  end)
  if p.sel then
    local last_line = vim.api.nvim_buf_get_lines(p.buf, p.last - 1, p.last, false)[1] or ""
    p.anchor = vim.api.nvim_buf_set_extmark(p.buf, ns, p.first - 1, 0, {
      end_row = p.last - 1,
      end_col = #last_line,
      right_gravity = false,
      end_right_gravity = false,
    })
    p.tail = vim.api.nvim_buf_set_extmark(p.buf, ns, p.last - 1, 0, {})
  else
    p.anchor = vim.api.nvim_buf_set_extmark(p.buf, ns, p.row - 1, 0, { right_gravity = false })
  end
  p.timer = vim.uv.new_timer()
  p.timer:start(
    80,
    80,
    vim.schedule_wrap(function()
      if not p.done and not p.finished then
        render(p)
      end
    end)
  )
  render(p)
  p.handle = provider.request({
    mode = "write",
    model = p.model,
    root = p.root,
    prompt = build(p, request),
    request = request,
    on_text = function(_, full)
      if p.finished then
        return
      end
      p.lines = M.extract(full)
      render(p)
    end,
    on_done = function(text)
      if p.finished then
        return
      end
      p.done = true
      p.lines = M.extract(text)
      if p.timer and not p.timer:is_closing() then
        p.timer:stop()
        p.timer:close()
      end
      if #p.lines == 0 then
        util.notify("Nothing to write: the answer was empty", vim.log.levels.WARN)
        finish(p)
        return
      end
      render(p)
    end,
    on_error = function(msg, info)
      if p.finished then
        return
      end
      if info and info.cancelled then
        finish(p)
        return
      end
      p.error = msg:gsub("\n", " ")
      render(p)
    end,
  })
end

--- Starts write here. Call from a mapping: in visual mode the selection is
--- read before the prompt opens.
function M.open()
  local sel = context.selection()
  if sel then
    vim.cmd("normal! \27") -- leave visual mode without touching typeahead
  end
  if M.pending then
    M.drop(M.pending)
  end
  local src = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_get_current_buf()
  if not vim.bo[buf].modifiable then
    util.notify("This buffer isn't modifiable", vim.log.levels.WARN)
    return
  end
  local cursor = vim.api.nvim_win_get_cursor(src)
  local p = {
    buf = buf,
    root = util.root(buf),
    model = config.models.write,
    lines = {},
    sel = sel ~= nil,
    first = sel and sel.first,
    last = sel and sel.last,
    row = cursor[1],
  }
  provider.prewarm(p.root, p.model)
  local b = box.new({
    win = src,
    row = sel and sel.last or cursor[1],
    col = sel and 0 or cursor[2],
    icon = config.icons.write,
    label = sel and ("replace · " .. context.chip(sel)) or "write here",
    model = p.model,
    width = config.quick.width,
  })
  b:prompt(function(request)
    b:close()
    M.start(p, request)
  end)
end

return M
