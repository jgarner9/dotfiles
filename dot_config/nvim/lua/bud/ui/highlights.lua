-- Bud's highlight groups. Most link to the colorscheme's own groups, so a
-- colorscheme change carries through; the badge is derived from them on
-- every ColorScheme event. All are `default`, so your overrides win.
local M = {}

M.links = {
  BudNormal = "NormalFloat",
  BudBorder = "FloatBorder",
  BudTitle = "FloatTitle",
  BudFooter = "FloatFooter",
  BudDim = "Comment",
  BudChip = "DiagnosticVirtualTextInfo",
  BudTool = "Comment",
  BudSpinner = "DiagnosticInfo",
  BudError = "DiagnosticError",
  BudOk = "DiagnosticOk",
  BudWarn = "DiagnosticWarn",
  BudPendingAdd = "DiffAdd",
  BudPendingOld = "DiffDelete",
  BudPendingHint = "DiagnosticVirtualTextHint",
  BudQuestion = "Title",
}

local function color(name, key)
  local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = name, link = false })
  return ok and hl[key] or nil
end

function M.apply()
  for group, link in pairs(M.links) do
    vim.api.nvim_set_hl(0, group, { link = link, default = true })
  end
  -- a pill for model names: the float background on the title color
  local fg = color("NormalFloat", "bg") or color("Normal", "bg")
  local bg = color("FloatTitle", "fg") or color("Function", "fg")
  if fg and bg then
    vim.api.nvim_set_hl(0, "BudBadge", { fg = fg, bg = bg, bold = true, default = true })
  else
    vim.api.nvim_set_hl(0, "BudBadge", { link = "IncSearch", default = true })
  end
  vim.api.nvim_set_hl(0, "BudGhost", { link = "Comment", default = true })
end

function M.setup()
  M.apply()
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = vim.api.nvim_create_augroup("bud_highlights", { clear = true }),
    callback = function()
      -- `default` links don't replace themselves, so clear the derived one
      pcall(vim.api.nvim_set_hl, 0, "BudBadge", {})
      M.apply()
    end,
  })
end

return M
