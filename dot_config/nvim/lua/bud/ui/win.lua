-- Float helpers shared by every Bud surface, so they all look the same:
-- rounded border, Bud's highlight groups, an icon and a model badge.
local config = require("bud.config")

local M = {}

M.winhighlight = table.concat({
  "Normal:BudNormal",
  "NormalNC:BudNormal",
  "FloatBorder:BudBorder",
  "FloatTitle:BudTitle",
  "FloatFooter:BudFooter",
}, ",")

--- Title chunks: " <icon><text> " followed by a model badge.
function M.title(icon, text, model)
  local chunks = { { " " .. (icon or "") .. (text or "") .. " ", "BudTitle" } }
  if model then
    table.insert(chunks, { " " .. model .. " ", "BudBadge" })
    table.insert(chunks, { " ", "BudBorder" })
  end
  return chunks
end

--- A scratch buffer. opts: ft, name, modifiable.
function M.scratch(opts)
  opts = opts or {}
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = opts.bufhidden or "wipe"
  vim.bo[buf].swapfile = false
  if opts.ft then
    vim.bo[buf].filetype = opts.ft
  end
  if opts.lines then
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, opts.lines)
  end
  if opts.modifiable == false then
    vim.bo[buf].modifiable = false
  end
  return buf
end

--- Opens a float with Bud's look. cfg is passed to nvim_open_win.
function M.open(buf, cfg, enter)
  cfg = vim.tbl_extend("force", { border = "rounded", style = "minimal", zindex = 50 }, cfg)
  if cfg.title and type(cfg.title) == "table" and #cfg.title == 0 then
    cfg.title = nil
  end
  if cfg.footer and type(cfg.footer) == "table" and #cfg.footer == 0 then
    cfg.footer = nil
  end
  local win = vim.api.nvim_open_win(buf, enter ~= false, cfg)
  vim.wo[win].winhighlight = M.winhighlight
  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true
  vim.wo[win].cursorline = false
  vim.wo[win].conceallevel = 2
  vim.wo[win].concealcursor = "nc"
  return win
end

function M.valid(win)
  return win ~= nil and vim.api.nvim_win_is_valid(win)
end

function M.close(win)
  if M.valid(win) then
    pcall(vim.api.nvim_win_close, win, true)
  end
end

--- Buffer-local normal-mode maps in one call.
function M.map(buf, maps, modes)
  for lhs, rhs in pairs(maps) do
    vim.keymap.set(modes or "n", lhs, rhs, { buffer = buf, nowait = true, silent = true })
  end
end

--- A centered read-only float for viewing text (the log, the instructions).
function M.view(lines, opts)
  opts = opts or {}
  local buf = M.scratch({ ft = opts.ft or "markdown", lines = lines, modifiable = false })
  local width = math.min(math.max(60, math.floor(vim.o.columns * 0.7)), vim.o.columns - 4)
  local height = math.min(math.max(5, #lines), math.floor((vim.o.lines - 2) * 0.8))
  local win = M.open(buf, {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2) - 1,
    col = math.floor((vim.o.columns - width) / 2),
    title = M.title(config.icons.bud, opts.title or "Bud", opts.model),
    title_pos = "center",
    footer = { { " q close ", "BudFooter" } },
    footer_pos = "right",
  })
  M.map(buf, {
    q = function()
      M.close(win)
    end,
    ["<Esc>"] = function()
      M.close(win)
    end,
  })
  return win, buf
end

--- A spinner frame for the current time.
function M.spinner()
  local frames = config.icons.busy
  return frames[math.floor(vim.uv.hrtime() / 1e6 / 80) % #frames + 1]
end

return M
