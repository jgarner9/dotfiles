-- The statusline segment: a spinner while Claude works, the last request's
-- token counts after, and a sync icon when dotsync needs your attention.
local config = require("bud.config")

local M = {}

local timer

local function short(n)
  n = tonumber(n) or 0
  if n >= 1000 then
    return ("%.1fk"):format(n / 1000)
  end
  return tostring(n)
end

local function sync_part()
  local ok, sync = pcall(require, "bud.sync")
  if not ok then
    return nil
  end
  if sync.running then
    return config.icons.sync
  end
  local last = sync.last
  if last and (last.status == "error" or last.status == "skipped_drift") then
    return config.icons.sync .. " " .. config.icons.warn
  end
end

function M.text()
  local provider = require("bud.provider")
  local parts = {}
  if provider.active > 0 then
    table.insert(parts, config.icons.bud .. require("bud.ui.win").spinner())
  elseif provider.last and provider.last.usage then
    local u = provider.last.usage
    local input = (u.input_tokens or 0) + (u.cache_read_input_tokens or 0) + (u.cache_creation_input_tokens or 0)
    table.insert(parts, ("%s%s↑ %s↓"):format(config.icons.bud, short(input), short(u.output_tokens)))
  end
  local s = sync_part()
  if s then
    table.insert(parts, s)
  end
  return table.concat(parts, "  ")
end

function M.cond()
  return M.text() ~= ""
end

--- A lualine component.
function M.lualine()
  return {
    function()
      return M.text()
    end,
    cond = M.cond,
    color = function()
      local provider = require("bud.provider")
      return {
        fg = vim.fn.synIDattr(vim.fn.synIDtrans(vim.fn.hlID(provider.active > 0 and "BudSpinner" or "BudDim")), "fg#"),
      }
    end,
  }
end

--- Redraws now, and keeps redrawing while something is running so the
--- spinner moves.
function M.refresh()
  pcall(vim.cmd.redrawstatus)
  local provider = require("bud.provider")
  local busy = provider.active > 0 or (package.loaded["bud.sync"] and require("bud.sync").running)
  if busy and not timer then
    timer = vim.uv.new_timer()
    timer:start(
      100,
      100,
      vim.schedule_wrap(function()
        pcall(vim.cmd.redrawstatus)
      end)
    )
  elseif not busy and timer then
    timer:stop()
    timer:close()
    timer = nil
  end
end

return M
