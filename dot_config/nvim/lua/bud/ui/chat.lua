-- The chat float: a tall float docked on the right with the transcript on
-- top and a few-line input below. Toggling hides it without losing anything;
-- a new chat starts fresh. Toggling it open snapshots the window you came
-- from, and that view goes along with your next message.
local config = require("bud.config")
local context = require("bud.context")
local history = require("bud.history")
local instructions = require("bud.instructions")
local mentions = require("bud.mentions")
local provider = require("bud.provider")
local tools = require("bud.tools")
local util = require("bud.util")
local win = require("bud.ui.win")

local M = {}

---@class bud.ChatState
local S = {
  buf = nil, -- transcript buffer, kept while hidden
  input = nil, -- input buffer
  win = nil,
  input_win = nil,
  proc = nil, -- the Claude process for this chat
  session_id = nil, -- for --resume after a cancel or from history
  id = nil,
  root = nil,
  title = nil,
  created = nil,
  pending = nil, -- view captured when the float was toggled open
  extra = {}, -- promoted quick asks to include with the next message
  busy = false,
  mapped = false, -- repomap already sent in this chat
  trail = 0, -- newlines at the end of the transcript
  origin_win = nil,
  origin_buf = nil,
  status = nil, -- footer text after a turn
}
M.state = S

local augroup = vim.api.nvim_create_augroup("bud_chat", { clear = true })

local function transcript_lines()
  if S.buf and vim.api.nvim_buf_is_valid(S.buf) then
    return vim.api.nvim_buf_get_lines(S.buf, 0, -1, false)
  end
  return {}
end

local function set_lines(lines)
  vim.bo[S.buf].modifiable = true
  vim.api.nvim_buf_set_lines(S.buf, 0, -1, false, lines)
  vim.bo[S.buf].modifiable = false
  local trail = 0
  for i = #lines, 1, -1 do
    if lines[i] ~= "" then
      break
    end
    trail = trail + 1
  end
  S.trail = trail
end

local function follow()
  if win.valid(S.win) then
    local last = vim.api.nvim_buf_line_count(S.buf)
    pcall(vim.api.nvim_win_set_cursor, S.win, { last, 0 })
  end
end

--- Appends raw text at the end of the transcript. Seams never stack more
--- than one blank line.
local function append(text)
  if text == "" then
    return
  end
  local lead = #(text:match("^\n*"))
  local allowed = math.max(0, 2 - S.trail)
  if S.trail > 0 and lead > allowed then
    text = ("\n"):rep(allowed) .. text:sub(lead + 1)
  end
  if text == "" then
    return
  end
  local following = win.valid(S.win) and vim.api.nvim_win_get_cursor(S.win)[1] >= vim.api.nvim_buf_line_count(S.buf) - 1
  local last = vim.api.nvim_buf_line_count(S.buf) - 1
  local line = vim.api.nvim_buf_get_lines(S.buf, last, last + 1, false)[1] or ""
  vim.bo[S.buf].modifiable = true
  vim.api.nvim_buf_set_text(S.buf, last, #line, last, #line, util.split_lines(text))
  vim.bo[S.buf].modifiable = false
  local tail = #(text:match("\n*$"))
  if tail == #text then
    S.trail = S.trail + tail
  else
    S.trail = tail
  end
  if following then
    follow()
  end
end

-- the transcript starts empty: one empty line
local function is_empty()
  local lines = transcript_lines()
  return #lines == 0 or (#lines == 1 and lines[1] == "")
end

local function ensure_buffers()
  if not (S.buf and vim.api.nvim_buf_is_valid(S.buf)) then
    S.buf = win.scratch({ ft = "bud_chat", bufhidden = "hide", modifiable = false })
    pcall(vim.api.nvim_buf_set_name, S.buf, "bud://chat")
    S.trail = 0
  end
  if not (S.input and vim.api.nvim_buf_is_valid(S.input)) then
    S.input = win.scratch({ ft = "bud_input", bufhidden = "hide" })
    pcall(vim.api.nvim_buf_set_name, S.input, "bud://input")
    M.input_maps()
  end
  if not S.id then
    S.id = util.uuid()
    S.created = util.now()
  end
end

local function model()
  return config.models.chat
end

local function footer()
  local chunks = {}
  if S.busy then
    table.insert(chunks, { " " .. win.spinner() .. " thinking ", "BudSpinner" })
    table.insert(chunks, { " <C-c> cancel ", "BudFooter" })
  elseif S.status then
    table.insert(chunks, { " " .. S.status .. " ", "BudFooter" })
  end
  return chunks
end

local function input_title()
  if S.pending then
    return { { " " .. context.chip(S.pending) .. " ", "BudChip" } }
  end
  return { { " message ", "BudTitle" } }
end

local function layout()
  local columns, lines = vim.o.columns, vim.o.lines
  local width = math.max(40, math.floor(columns * config.chat.width))
  width = math.min(width, columns - 4)
  local top = (vim.o.showtabline == 2 or (vim.o.showtabline == 1 and #vim.api.nvim_list_tabpages() > 1)) and 1 or 0
  local bottom = vim.o.cmdheight + (vim.o.laststatus > 0 and 1 or 0)
  local total = lines - top - bottom
  local ih = config.chat.input_height
  local th = math.max(3, total - ih - 4)
  local col = columns - width - 2
  return {
    transcript = { relative = "editor", row = top, col = col, width = width, height = th },
    input = { relative = "editor", row = top + th + 2, col = col, width = width, height = ih },
  }
end

local function redraw_chrome()
  if win.valid(S.win) then
    local f = footer()
    vim.api.nvim_win_set_config(S.win, {
      title = win.title(config.icons.bud, "Bud", model()),
      title_pos = "left",
      footer = #f > 0 and f or "",
      footer_pos = "right",
    })
  end
  if win.valid(S.input_win) then
    vim.api.nvim_win_set_config(S.input_win, {
      title = input_title(),
      title_pos = "left",
      footer = { { " <CR> send · @ mention · <C-c> cancel · q hide ", "BudFooter" } },
      footer_pos = "right",
    })
  end
end

local spin_timer
local function spin(on)
  if on and not spin_timer then
    spin_timer = vim.uv.new_timer()
    spin_timer:start(80, 80, vim.schedule_wrap(redraw_chrome))
  elseif not on and spin_timer then
    spin_timer:stop()
    spin_timer:close()
    spin_timer = nil
  end
end

function M.is_open()
  return win.valid(S.win) and win.valid(S.input_win)
end

local function is_bud_win(w)
  return w == S.win or w == S.input_win
end

function M.open(opts)
  opts = opts or {}
  local cur = vim.api.nvim_get_current_win()
  if not is_bud_win(cur) and vim.api.nvim_win_get_config(cur).relative == "" then
    S.origin_win = cur
    S.origin_buf = vim.api.nvim_win_get_buf(cur)
    if not opts.no_capture then
      S.pending = context.view(cur)
    end
    S.root = S.root or util.root(S.origin_buf)
  end
  S.root = S.root or util.root()
  ensure_buffers()
  if M.is_open() then
    vim.api.nvim_set_current_win(S.input_win)
    redraw_chrome()
    return
  end
  local l = layout()
  S.win = win.open(S.buf, vim.tbl_extend("force", l.transcript, { zindex = 45 }), false)
  vim.wo[S.win].wrap = true
  vim.wo[S.win].cursorline = false
  vim.wo[S.win].number = false
  vim.wo[S.win].signcolumn = "no"
  vim.wo[S.win].foldenable = false
  S.input_win = win.open(S.input, vim.tbl_extend("force", l.input, { zindex = 46 }), true)
  redraw_chrome()
  follow()
  M.transcript_maps()
  vim.cmd.startinsert({ bang = true })
  -- start the Claude process now so the first answer starts sooner
  if not (S.proc and S.proc:alive()) and util.executable(config.claude) then
    M.ensure_proc()
  end
end

function M.hide()
  win.close(S.input_win)
  win.close(S.win)
  S.win, S.input_win = nil, nil
  if S.origin_win and vim.api.nvim_win_is_valid(S.origin_win) then
    vim.api.nvim_set_current_win(S.origin_win)
  end
  vim.cmd.stopinsert()
end

function M.toggle()
  if M.is_open() then
    M.hide()
  else
    M.open()
  end
end

function M.ensure_proc()
  if S.proc and S.proc:alive() then
    return S.proc
  end
  local root = S.root or util.root()
  S.proc = provider.Proc.spawn({
    model = model(),
    root = root,
    system_file = (instructions.path("chat", root)),
    args = tools.chat_args(root),
    resume = S.session_id,
    persist = true,
  })
  return S.proc
end

local function save()
  history.save({
    id = S.id,
    root = S.root,
    title = S.title,
    created = S.created,
    session_id = S.session_id,
    model = model(),
    lines = transcript_lines(),
  })
end

local function describe_tool(name, input)
  local root = S.root or ""
  if name == "Bash" then
    return input.command or "bash"
  elseif name == "Read" then
    return "read " .. util.relpath(input.file_path or "", root)
  elseif name == "Grep" then
    return ("grep %s%s"):format(input.pattern or "", input.path and (" in " .. util.relpath(input.path, root)) or "")
  elseif name == "Glob" then
    return "glob " .. (input.pattern or "")
  end
  local server, tool = name:match("^mcp__(.-)__(.+)$")
  if server then
    local arg
    for _, v in pairs(input) do
      if type(v) == "string" then
        arg = v
        break
      end
    end
    return ("%s %s%s"):format(server, tool, arg and (" " .. util.truncate(arg, 60)) or "")
  end
  return name
end

--- Sends the input buffer's text (or text) as the next message.
function M.send(text)
  ensure_buffers()
  text = text or vim.trim(table.concat(vim.api.nvim_buf_get_lines(S.input, 0, -1, false), "\n"))
  if text == "" then
    return
  end
  if S.busy then
    util.notify("Bud is still answering. <C-c> cancels.", vim.log.levels.INFO)
    return
  end
  local root = S.root or util.root()
  S.root = root
  local parts, chips = {}, {}
  if not S.mapped then
    local map = context.repomap(root)
    if map then
      table.insert(parts, map)
    end
    S.mapped = true
  end
  if S.pending then
    table.insert(parts, context.format(S.pending))
    table.insert(chips, context.chip(S.pending))
  end
  for _, e in ipairs(S.extra) do
    table.insert(parts, e)
  end
  local blocks, mchips = mentions.resolve(text, root, S.origin_buf)
  vim.list_extend(parts, blocks)
  for _, c in ipairs(mchips) do
    table.insert(chips, config.icons.file .. c)
  end
  table.insert(parts, text)
  local message = table.concat(parts, "\n\n")

  S.title = S.title or util.truncate(text, 60)
  S.pending = nil
  S.extra = {}
  vim.api.nvim_buf_set_lines(S.input, 0, -1, false, { "" })

  local head = {}
  if not is_empty() then
    table.insert(head, "")
  end
  table.insert(head, "## " .. config.icons.you .. "You")
  table.insert(head, "")
  for _, c in ipairs(chips) do
    table.insert(head, "`" .. c .. "`")
  end
  if #chips > 0 then
    table.insert(head, "")
  end
  vim.list_extend(head, util.split_lines(text))
  vim.list_extend(head, { "", "## " .. config.icons.bud .. "Bud", "", "" })
  if is_empty() then
    set_lines(head)
  else
    append("\n" .. table.concat(head, "\n"))
  end
  follow()

  local proc = M.ensure_proc()
  S.busy = true
  S.status = nil
  provider.track(1)
  spin(true)
  redraw_chrome()
  local started = vim.uv.hrtime()
  local function finish()
    S.busy = false
    spin(false)
    redraw_chrome()
  end
  proc:send(message, {
    on_text = function(delta)
      append(delta)
    end,
    on_tool = function(name, input)
      append("\n\n> 󰆍 " .. describe_tool(name, input):gsub("\n", " ") .. "\n\n")
    end,
    on_done = function(answer, ev, ms)
      S.session_id = proc.session_id or S.session_id
      local u = ev.usage or {}
      local input_tokens = (u.input_tokens or 0)
        + (u.cache_read_input_tokens or 0)
        + (u.cache_creation_input_tokens or 0)
      S.status = ("%.1fs · %s in · %s out%s"):format(
        (ms or 0) / 1000,
        input_tokens,
        u.output_tokens or 0,
        ev.total_cost_usd and (" · $%.3f"):format(ev.total_cost_usd) or ""
      )
      provider.track(-1, { model = model(), usage = ev.usage, cost = ev.total_cost_usd })
      require("bud.log").add({
        mode = "chat",
        model = model(),
        root = root,
        request = text,
        prompt = message,
        response = answer,
        usage = ev.usage,
        cost = ev.total_cost_usd,
        duration_ms = ms or (vim.uv.hrtime() - started) / 1e6,
        session_id = S.session_id,
      })
      if ev.permission_denials and #ev.permission_denials > 0 then
        local names = {}
        for _, d in ipairs(ev.permission_denials) do
          table.insert(names, describe_tool(d.tool_name or "?", d.tool_input or {}))
        end
        append("\n\n> " .. config.icons.warn .. " Not allowed: " .. table.concat(names, ", ") .. "\n")
      end
      finish()
      save()
    end,
    on_error = function(msg, info)
      S.session_id = proc.session_id or S.session_id
      provider.track(-1)
      if info and info.cancelled then
        append("\n\n> Cancelled\n")
      else
        append("\n\n> " .. config.icons.warn .. " " .. msg:gsub("\n", " ") .. "\n")
      end
      S.status = info and info.cancelled and "cancelled" or "error"
      require("bud.log").add({
        mode = "chat",
        model = model(),
        root = root,
        request = text,
        prompt = message,
        error = msg,
      })
      finish()
      save()
    end,
  })
end

function M.cancel()
  if S.busy and S.proc then
    S.proc:kill()
  end
end

--- Throws the conversation away (it stays in history) and starts fresh.
function M.new()
  if S.proc then
    S.proc:close()
    S.proc:kill()
  end
  S.proc = nil
  S.session_id = nil
  S.id = nil
  S.title = nil
  S.created = nil
  S.mapped = false
  S.extra = {}
  S.status = nil
  S.busy = false
  S.root = nil
  ensure_buffers()
  set_lines({ "" })
  if M.is_open() then
    local cur = S.origin_win and vim.api.nvim_win_is_valid(S.origin_win) and S.origin_win
    if cur then
      S.pending = context.view(cur)
      S.root = util.root(vim.api.nvim_win_get_buf(cur))
    end
    redraw_chrome()
    vim.api.nvim_set_current_win(S.input_win)
  else
    M.open()
  end
end

--- Loads a saved chat; the next message resumes its Claude session.
function M.load(chat)
  if S.proc then
    S.proc:close()
    S.proc:kill()
  end
  S.proc = nil
  S.id = chat.id
  S.title = chat.title
  S.created = chat.created
  S.session_id = chat.session_id
  S.root = chat.root
  S.mapped = true
  S.extra = {}
  S.status = nil
  S.busy = false
  ensure_buffers()
  set_lines(chat.lines or { "" })
  if M.is_open() then
    if not (S.proc and S.proc:alive()) and util.executable(config.claude) then
      M.ensure_proc()
    end
    follow()
    redraw_chrome()
  else
    M.open()
  end
end

function M.history()
  history.pick(util.root(), M.load)
end

--- Moves a quick ask into the chat: shown in the transcript and sent as
--- context with the next message, since the chat's Claude never saw it.
function M.promote(q)
  M.open({ no_capture = q.ctx ~= nil })
  if q.ctx then
    S.pending = nil
  end
  local head = {}
  if not is_empty() then
    table.insert(head, "")
  end
  table.insert(head, "## " .. config.icons.quick .. "Quick ask")
  table.insert(head, "")
  if q.ctx then
    table.insert(head, "`" .. context.chip(q.ctx) .. "`")
    table.insert(head, "")
  end
  vim.list_extend(head, util.split_lines(q.question))
  vim.list_extend(head, { "", "### " .. q.model, "" })
  vim.list_extend(head, util.split_lines(q.answer))
  table.insert(head, "")
  if is_empty() then
    set_lines(head)
  else
    append("\n" .. table.concat(head, "\n"))
  end
  local extra = { "<earlier-quick-ask>" }
  if q.ctx then
    table.insert(extra, context.format(q.ctx))
  end
  vim.list_extend(
    extra,
    { "Question: " .. q.question, "Answer (" .. q.model .. "): " .. q.answer, "</earlier-quick-ask>" }
  )
  table.insert(S.extra, table.concat(extra, "\n"))
  follow()
  redraw_chrome()
end

--- The fenced code block under the cursor in the transcript, yanked.
function M.yank_block()
  local lines = transcript_lines()
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local start, stop
  for i = row, 1, -1 do
    if lines[i]:match("^%s*```") then
      start = i
      break
    end
  end
  if start then
    for i = math.max(row, start + 1), #lines do
      if lines[i]:match("^%s*```") then
        stop = i
        break
      end
    end
  end
  if not (start and stop) or start == stop then
    util.notify("No code block under the cursor")
    return
  end
  local block = vim.list_slice(lines, start + 1, stop - 1)
  vim.fn.setreg('"', table.concat(block, "\n") .. "\n", "l")
  if vim.fn.has("clipboard") == 1 then
    pcall(vim.fn.setreg, "+", table.concat(block, "\n") .. "\n", "l")
  end
  util.notify(("Yanked %d lines"):format(#block))
end

-- pos: the insert-mode cursor when @ was typed ({ row, byte col })
local function insert_mention(pos)
  local root = S.root or util.root()
  local row, col = pos[1], pos[2]
  mentions.pick(root, S.origin_buf, function(token)
    if not M.is_open() then
      return
    end
    vim.api.nvim_set_current_win(S.input_win)
    token = token or "@"
    local line = vim.api.nvim_buf_get_lines(S.input, row - 1, row, false)[1] or ""
    col = math.min(col, #line)
    local insert = token
    if token ~= "@" then
      local before = line:sub(1, col)
      insert = ((before == "" or before:match("%s$")) and "" or " ") .. token .. " "
    end
    vim.api.nvim_buf_set_text(S.input, row - 1, col, row - 1, col, { insert })
    local new_col = col + #insert
    if new_col >= #line + #insert then
      vim.api.nvim_win_set_cursor(S.input_win, { row, 0 })
      vim.cmd.startinsert({ bang = true })
    else
      vim.api.nvim_win_set_cursor(S.input_win, { row, new_col })
      vim.cmd.startinsert()
    end
  end)
end

function M.input_maps()
  local buf = S.input
  win.map(buf, {
    ["<CR>"] = function()
      M.send()
    end,
    q = M.hide,
    ["<C-c>"] = M.cancel,
    ["<Tab>"] = function()
      if win.valid(S.win) then
        vim.api.nvim_set_current_win(S.win)
      end
    end,
  })
  win.map(buf, {
    ["<C-s>"] = function()
      vim.cmd.stopinsert()
      M.send()
    end,
    ["<C-c>"] = M.cancel,
    ["@"] = function()
      local pos = vim.api.nvim_win_get_cursor(0)
      vim.cmd.stopinsert()
      vim.schedule(function()
        insert_mention(pos)
      end)
    end,
  }, "i")
end

function M.transcript_maps()
  win.map(S.buf, {
    q = M.hide,
    ["<C-c>"] = M.cancel,
    gy = M.yank_block,
    ["<Tab>"] = function()
      if win.valid(S.input_win) then
        vim.api.nvim_set_current_win(S.input_win)
      end
    end,
    i = function()
      if win.valid(S.input_win) then
        vim.api.nvim_set_current_win(S.input_win)
        vim.cmd.startinsert({ bang = true })
      end
    end,
  })
end

vim.api.nvim_create_autocmd("VimResized", {
  group = augroup,
  callback = function()
    if M.is_open() then
      local l = layout()
      vim.api.nvim_win_set_config(S.win, l.transcript)
      vim.api.nvim_win_set_config(S.input_win, l.input)
      redraw_chrome()
    end
  end,
})

-- closing one half (e.g. :q in the input) hides the whole float
vim.api.nvim_create_autocmd("WinClosed", {
  group = augroup,
  callback = function(ev)
    local closed = tonumber(ev.match)
    if closed == S.win or closed == S.input_win then
      vim.schedule(function()
        if not M.is_open() and (win.valid(S.win) or win.valid(S.input_win)) then
          M.hide()
        end
      end)
    end
  end,
})

return M
