-- Quick ask: a fast Haiku answer in a small box under the cursor.
-- Normal mode sends just the question; visual mode sends the selection too.
local box = require("bud.ui.box")
local config = require("bud.config")
local context = require("bud.context")
local provider = require("bud.provider")
local util = require("bud.util")
local win = require("bud.ui.win")

local M = {}

M.current = nil

local function build(question, sel)
  if not sel then
    return question
  end
  return context.format(sel) .. "\n\nQuestion about the selected code: " .. question
end

--- Starts a quick ask. Call from a mapping: in visual mode the selection is
--- read before the box opens.
function M.open()
  local sel = context.selection()
  if sel then
    vim.cmd("normal! \27") -- leave visual mode without touching typeahead
  end
  local src = vim.api.nvim_get_current_win()
  local cursor = vim.api.nvim_win_get_cursor(src)
  local row = sel and sel.last or cursor[1]
  local col = sel and 0 or cursor[2]
  local root = util.root()
  local model = config.models.quick
  local b = box.new({
    win = src,
    row = row,
    col = col,
    icon = config.icons.quick,
    label = sel and ("ask · " .. context.chip(sel)) or "ask",
    model = model,
    width = config.quick.width,
  })
  M.box = b
  provider.prewarm(root, model)
  b:prompt(function(question)
    M.ask(b, question, sel, root, model)
  end)
  return b
end

function M.ask(b, question, sel, root, model)
  local state = { question = question, answer = "", done = false, ctx = sel, model = model }
  M.current = state
  local handle
  local timer = vim.uv.new_timer()
  local function stop_timer()
    if timer and not timer:is_closing() then
      timer:stop()
      timer:close()
    end
  end
  local function busy_footer()
    b:set_footer({ { " " .. win.spinner() .. " ", "BudSpinner" }, { "<C-c> cancel ", "BudFooter" } })
  end
  local function close()
    if handle and not state.done then
      handle.cancel()
    end
    stop_timer()
    b:close()
  end
  local function yank()
    vim.fn.setreg('"', state.answer)
    if vim.fn.has("clipboard") == 1 then
      pcall(vim.fn.setreg, "+", state.answer)
    end
    util.notify("Answer yanked")
  end
  local function promote()
    if not state.done then
      util.notify("Wait for the answer, or <C-c> to cancel it first")
      return
    end
    b.leave_ok = true
    b:close()
    require("bud.ui.chat").promote(state)
  end
  b:answer(question, {
    q = close,
    ["<Esc>"] = close,
    ["<C-c>"] = function()
      if handle and not state.done then
        handle.cancel()
      end
    end,
    y = yank,
    ["<Tab>"] = promote,
  })
  b.on_leave = function()
    if handle and not state.done then
      handle.cancel()
    end
    stop_timer()
  end
  busy_footer()
  timer:start(
    80,
    80,
    vim.schedule_wrap(function()
      if not state.done and not b.closed then
        busy_footer()
      end
    end)
  )
  handle = provider.request({
    mode = "quick",
    model = model,
    root = root,
    prompt = build(question, sel),
    request = question,
    on_text = function(_, full)
      state.answer = full
      b:set_text(full)
    end,
    on_done = function(text, ev)
      state.done = true
      state.answer = vim.trim(text)
      stop_timer()
      b:set_text(state.answer)
      local u = ev.usage or {}
      b:set_footer({
        { (" %s out "):format(u.output_tokens or "?"), "BudDim" },
        { "y yank · <Tab> chat · q close ", "BudFooter" },
      })
    end,
    on_error = function(msg, info)
      state.done = true
      stop_timer()
      if info and info.cancelled then
        b:set_footer({ { " cancelled · q close ", "BudFooter" } })
      else
        b:set_text((state.answer ~= "" and state.answer .. "\n\n" or "") .. config.icons.warn .. " " .. msg)
        b:set_footer({ { " error · q close ", "BudError" } })
      end
    end,
  })
end

return M
