-- The small box under the cursor used by quick ask and write here. It starts
-- as a one-line prompt; quick ask then turns it into the answer box, which
-- grows downward as the answer streams in.
local config = require("bud.config")
local util = require("bud.util")
local win = require("bud.ui.win")

local M = {}

---@class bud.Box
local Box = {}
Box.__index = Box

--- opts: win (source window), row (1-based buffer line), col (0-based byte),
--- icon, label, model, width
function M.new(opts)
  local self = setmetatable({ opts = opts, closed = false }, Box)
  local src = opts.win or vim.api.nvim_get_current_win()
  self.src = src
  local info = vim.fn.getwininfo(src)[1]
  local textoff = info and info.textoff or 0
  local avail = vim.api.nvim_win_get_width(src) - textoff - 2
  self.width = math.max(24, math.min(opts.width or config.quick.width, avail))
  self.row, self.col = opts.row, opts.col or 0
  return self
end

--- Where the box goes: below the anchor line, or above it when the window
--- has no room below.
function Box:position(height)
  local pos = vim.fn.screenpos(self.src, self.row, 1)
  local below = vim.o.lines - vim.o.cmdheight - 1 - (pos.row or 0)
  local cfg = {
    relative = "win",
    win = self.src,
    bufpos = { self.row - 1, self.col },
    width = self.width,
    height = height,
  }
  if pos.row ~= 0 and below < height + 2 and pos.row > height + 2 then
    cfg.anchor, cfg.row, cfg.col = "SW", 0, 0
  else
    cfg.anchor, cfg.row, cfg.col = "NW", 1, 0
  end
  return cfg
end

function Box:title(extra)
  local o = self.opts
  return win.title(o.icon, o.label .. (extra or ""), o.model)
end

--- Opens the one-line prompt. on_submit(text) on <CR>; on_cancel() on <Esc>.
function Box:prompt(on_submit, on_cancel)
  self.buf = win.scratch({ ft = "bud_input" })
  local cfg = self:position(1)
  cfg.title = self:title()
  cfg.footer = { { " <CR> send · <Esc> cancel ", "BudFooter" } }
  cfg.footer_pos = "right"
  cfg.zindex = 60
  self.win = win.open(self.buf, cfg, true)
  vim.wo[self.win].wrap = false
  vim.cmd.startinsert()
  local done = false
  local function submit()
    if done then
      return
    end
    done = true
    local text = vim.trim(table.concat(vim.api.nvim_buf_get_lines(self.buf, 0, -1, false), " "))
    vim.cmd.stopinsert()
    if text == "" then
      self:close()
      if on_cancel then
        on_cancel()
      end
      return
    end
    on_submit(text)
  end
  local function cancel()
    if done then
      return
    end
    done = true
    vim.cmd.stopinsert()
    self:close()
    if on_cancel then
      on_cancel()
    end
  end
  win.map(self.buf, { ["<CR>"] = submit, ["<Esc>"] = cancel, ["<C-c>"] = cancel }, "i")
  win.map(self.buf, { ["<CR>"] = submit, ["<Esc>"] = cancel, q = cancel, ["<C-c>"] = cancel }, "n")
  vim.api.nvim_create_autocmd("WinLeave", {
    buffer = self.buf,
    once = true,
    callback = function()
      vim.schedule(cancel)
    end,
  })
end

--- Turns the prompt into the answer box. header: the question, shown dim.
function Box:answer(header, maps)
  self.answering = true
  self.header = header
  self.text = ""
  if not (self.buf and vim.api.nvim_buf_is_valid(self.buf)) then
    self.buf = win.scratch({})
  end
  vim.bo[self.buf].filetype = "bud_quick"
  self.ns = vim.api.nvim_create_namespace("bud_box")
  self:render()
  vim.bo[self.buf].modifiable = false
  vim.wo[self.win].wrap = true
  win.map(self.buf, maps or {}, "n")
  vim.api.nvim_create_autocmd({ "WinLeave", "BufLeave" }, {
    buffer = self.buf,
    callback = function()
      vim.schedule(function()
        if self.leave_ok then
          return
        end
        if self.on_leave then
          self.on_leave()
        end
        self:close()
      end)
    end,
  })
end

function Box:lines()
  local lines = { config.icons.you .. self.header }
  if self.text ~= "" then
    vim.list_extend(lines, util.split_lines(self.text))
  end
  return lines
end

--- Visual height of the lines at the box's width (wrapping counts).
local function visual_height(lines, width)
  local h = 0
  for _, l in ipairs(lines) do
    h = h + math.max(1, math.ceil(vim.fn.strdisplaywidth(l) / width))
  end
  return h
end

function Box:render()
  if self.closed or not (self.buf and vim.api.nvim_buf_is_valid(self.buf)) then
    return
  end
  local lines = self:lines()
  vim.bo[self.buf].modifiable = true
  vim.api.nvim_buf_set_lines(self.buf, 0, -1, false, lines)
  vim.bo[self.buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(self.buf, self.ns, 0, -1)
  vim.api.nvim_buf_set_extmark(self.buf, self.ns, 0, 0, { end_row = 0, end_col = #lines[1], hl_group = "BudDim" })
  if win.valid(self.win) then
    local height = math.min(config.quick.max_height, visual_height(lines, self.width))
    local cfg = self:position(height)
    cfg.title = self:title()
    cfg.footer = self.footer or ""
    cfg.footer_pos = "right"
    vim.api.nvim_win_set_config(self.win, cfg)
  end
end

function Box:set_text(text)
  self.text = text
  self:render()
end

function Box:set_footer(chunks)
  self.footer = chunks
  if win.valid(self.win) and not self.closed then
    vim.api.nvim_win_set_config(self.win, { footer = chunks or "", footer_pos = "right" })
  end
end

function Box:close()
  if self.closed then
    return
  end
  self.closed = true
  win.close(self.win)
  if vim.api.nvim_win_is_valid(self.src) then
    pcall(vim.api.nvim_set_current_win, self.src)
  end
end

return M
