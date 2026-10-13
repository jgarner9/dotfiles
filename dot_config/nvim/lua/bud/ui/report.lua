-- The report float: describe a bug or a feature, choose what context goes
-- with it, and send it to the fixer (lua/bud/report.lua).
--
--   <Tab>      bug ⇄ feature                       (normal mode)
--   1 2 3      attach or drop each context item    (normal mode)
--   gp         preview the issue and what stays local
--   <CR>       send (normal mode); <C-s> in insert mode
--   q  <Esc>   close; the text is kept for next time
local config = require("bud.config")
local report = require("bud.report")
local util = require("bud.util")
local win = require("bud.ui.win")

local M = {}

local ns = vim.api.nvim_create_namespace("bud_report")
local S = {}
-- an unsent report, restored when the float opens again
M.draft = nil

local placeholder = {
  bug = "What happened, and what did you expect?",
  feature = "What should Bud do, and when would you use it?",
}

local function layout(n)
  local width = math.min(76, vim.o.columns - 8)
  local height = 8
  local total = height + n + 4
  local row = math.max(1, math.floor((vim.o.lines - total) / 2) - 1)
  local col = math.floor((vim.o.columns - width) / 2)
  return {
    editor = { relative = "editor", width = width, height = height, row = row, col = col },
    panel = { relative = "editor", width = width, height = n, row = row + height + 2, col = col },
  }
end

local function title()
  local icon = S.kind == "bug" and config.icons.bug or config.icons.feature
  return win.title(icon, "report · " .. S.kind, config.models.fix)
end

local function chrome()
  if win.valid(S.win) then
    vim.api.nvim_win_set_config(S.win, {
      title = title(),
      title_pos = "center",
      footer = { { " <CR> send · <Tab> bug/feature · 1-3 attach · gp preview · q close ", "BudFooter" } },
      footer_pos = "right",
    })
  end
end

local function render_placeholder()
  if not vim.api.nvim_buf_is_valid(S.buf) then
    return
  end
  vim.api.nvim_buf_clear_namespace(S.buf, ns, 0, -1)
  local lines = vim.api.nvim_buf_get_lines(S.buf, 0, -1, false)
  if #lines == 1 and lines[1] == "" then
    vim.api.nvim_buf_set_extmark(S.buf, ns, 0, 0, {
      virt_text = { { placeholder[S.kind], "BudDim" } },
      virt_text_pos = "overlay",
    })
  end
end

local function render_panel()
  if not (S.panel_buf and vim.api.nvim_buf_is_valid(S.panel_buf)) then
    return
  end
  local lines, marks = {}, {}
  for i, a in ipairs(S.atts) do
    local mark = a.empty and "·" or (a.on and config.icons.ok or "✗")
    local text = (" %d %s %-16s %s"):format(i, mark, a.label, a.summary)
    table.insert(lines, text)
    table.insert(marks, (a.on and not a.empty) and "BudNormal" or "BudDim")
  end
  vim.bo[S.panel_buf].modifiable = true
  vim.api.nvim_buf_set_lines(S.panel_buf, 0, -1, false, lines)
  vim.bo[S.panel_buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(S.panel_buf, ns, 0, -1)
  for i, hl in ipairs(marks) do
    vim.api.nvim_buf_set_extmark(S.panel_buf, ns, i - 1, 0, { line_hl_group = hl })
  end
end

function M.is_open()
  return win.valid(S.win)
end

local function text()
  return table.concat(vim.api.nvim_buf_get_lines(S.buf, 0, -1, false), "\n")
end

function M.close()
  if not M.is_open() and not win.valid(S.panel) then
    return
  end
  if S.buf and vim.api.nvim_buf_is_valid(S.buf) and not S.sent then
    local t = vim.trim(text())
    M.draft = t ~= "" and { text = text(), kind = S.kind } or nil
  end
  local w, p = S.win, S.panel
  S.win, S.panel = nil, nil
  win.close(p)
  win.close(w)
  pcall(vim.cmd, "stopinsert")
end

function M.toggle_kind()
  S.kind = S.kind == "bug" and "feature" or "bug"
  chrome()
  render_placeholder()
end

function M.toggle(i)
  local a = S.atts[i]
  if not a then
    return
  end
  if a.empty then
    util.notify(("Nothing to attach: no %s"):format(a.label:lower()))
    return
  end
  a.on = not a.on
  render_panel()
end

function M.preview()
  local desc = vim.trim(text())
  local lines = { "# The issue (GitHub)", "", "## " .. (desc ~= "" and report.title(desc) or "(no title yet)"), "" }
  vim.list_extend(lines, util.split_lines(report.body(desc ~= "" and desc or "…", S.atts)))
  local ctx = report.local_context(S.atts)
  vim.list_extend(lines, { "", "# Only the fixer sees this (stays on this machine)", "" })
  vim.list_extend(lines, ctx ~= "" and util.split_lines(ctx) or { "Nothing else." })
  S.previewing = true
  local w = win.view(lines, { title = "report preview", ft = "markdown" })
  vim.api.nvim_create_autocmd("WinClosed", {
    pattern = tostring(w),
    once = true,
    callback = function()
      S.previewing = false
      vim.schedule(function()
        if M.is_open() then
          vim.api.nvim_set_current_win(S.win)
        end
      end)
    end,
  })
end

function M.send()
  local ok, err = report.submit({ kind = S.kind, description = text(), attachments = S.atts })
  if not ok then
    util.notify(err, vim.log.levels.WARN, { title = "Bud fixer" })
    return
  end
  S.sent = true
  M.draft = nil
  M.close()
end

local function maps()
  local buf = S.buf
  local n = {
    ["<CR>"] = M.send,
    ["<Tab>"] = M.toggle_kind,
    gp = M.preview,
    q = M.close,
    ["<Esc>"] = M.close,
  }
  for i = 1, #S.atts do
    n[tostring(i)] = function()
      M.toggle(i)
    end
  end
  win.map(buf, n)
  win.map(buf, {
    ["<C-s>"] = function()
      vim.cmd.stopinsert()
      M.send()
    end,
  }, "i")
end

--- Opens the report float. kind: "bug" (default) or "feature".
function M.open(kind)
  if M.is_open() then
    vim.api.nvim_set_current_win(S.win)
    return
  end
  local origin = vim.api.nvim_get_current_buf()
  local ft = vim.bo[origin].buftype == "" and vim.bo[origin].filetype or nil
  S = { kind = kind or (M.draft and M.draft.kind) or "bug", atts = report.attachments(ft) }
  report.claude_version() -- cached for the environment section at send time

  S.buf = win.scratch({ ft = "bud_input" })
  if M.draft then
    vim.api.nvim_buf_set_lines(S.buf, 0, -1, false, util.split_lines(M.draft.text))
  end
  S.panel_buf = win.scratch({ ft = "bud_report_panel" })
  local l = layout(#S.atts)
  S.win = win.open(S.buf, vim.tbl_extend("force", l.editor, { zindex = 60 }), true)
  S.panel = win.open(
    S.panel_buf,
    vim.tbl_extend("force", l.panel, {
      zindex = 60,
      focusable = false,
      title = { { " attached ", "BudTitle" } },
      title_pos = "left",
    }),
    false
  )
  vim.wo[S.panel].wrap = false
  chrome()
  render_panel()
  render_placeholder()
  maps()

  local group = vim.api.nvim_create_augroup("bud_report", { clear = true })
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = group,
    buffer = S.buf,
    callback = render_placeholder,
  })
  vim.api.nvim_create_autocmd("WinLeave", {
    group = group,
    buffer = S.buf,
    callback = function()
      vim.schedule(function()
        if M.is_open() and not S.previewing and vim.api.nvim_get_current_win() ~= S.win then
          M.close()
        end
      end)
    end,
  })
  vim.api.nvim_create_autocmd("WinClosed", {
    group = group,
    pattern = tostring(S.win),
    callback = function()
      vim.schedule(M.close)
    end,
  })
  if M.draft then
    vim.api.nvim_win_set_cursor(S.win, { vim.api.nvim_buf_line_count(S.buf), 0 })
    vim.cmd.startinsert({ bang = true })
  else
    vim.cmd.startinsert()
  end
  return S
end

-- for tests
function M._state()
  return S
end

return M
