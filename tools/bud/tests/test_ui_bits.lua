local mentions = require("bud.mentions")
local statusline = require("bud.ui.statusline")

return {
  {
    "mention tokens parse; emails and unknown kinds don't",
    function(T)
      local toks = mentions.parse("look at @file:a/b.lua#L1-4, @diag and @diff. mail me@x.com @sym @foo")
      T.eq(
        vim.tbl_map(function(t)
          return t.raw
        end, toks),
        { "@file:a/b.lua#L1-4", "@diag", "@diff" }
      )
      T.eq(toks[1].arg, "a/b.lua#L1-4")
    end,
  },
  {
    "file mentions respect .bud/ignore and say when a file is missing",
    function(T)
      local root = T.project({ ["a.txt"] = "1\n2\n3\n", [".env"] = "SECRET=x\n" })
      local blocks, chips = mentions.resolve("@file:a.txt @file:.env @file:nope.txt", root, nil)
      T.eq(chips, { "a.txt", ".env (ignored)", "nope.txt (not found)" })
      T.contains(blocks[1], "File: a.txt\n```\n1\n2\n3\n```")
      T.ok(not blocks[2]:find("SECRET", 1, true))
    end,
  },
  {
    "@diff sends uncommitted changes",
    function(T)
      local root = T.project({ ["a.txt"] = "one\n" }, true)
      local f = assert(io.open(root .. "/a.txt", "w"))
      f:write("two\n")
      f:close()
      local blocks, chips = mentions.resolve("@diff", root, nil)
      T.contains(blocks[1], "-one\n+two")
      T.match(chips[1], "^git diff · %d+ lines$")
    end,
  },
  {
    "@buf sends unsaved changes",
    function(T)
      local root = T.project({ ["a.txt"] = "saved\n" })
      vim.cmd.edit(root .. "/a.txt")
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "unsaved" })
      local blocks = mentions.resolve("@buf:a.txt", root, nil)
      T.contains(blocks[1], "unsaved")
      vim.cmd("bwipe!")
    end,
  },
  {
    "statusline: spinner while busy, token counts after",
    function(T)
      local provider = require("bud.provider")
      provider.last = { usage = { input_tokens = 1500, output_tokens = 20 } }
      T.contains(statusline.text(), "1.5k↑ 20↓")
      provider.active = 1
      T.ok(not statusline.text():find("↑", 1, true))
      provider.active = 0
      T.ok(statusline.cond())
    end,
  },
  {
    "highlight groups link to the colorscheme",
    function(T)
      T.eq(vim.api.nvim_get_hl(0, { name = "BudBorder" }).link, "FloatBorder")
      T.ok(next(vim.api.nvim_get_hl(0, { name = "BudBadge" })) ~= nil)
      vim.cmd.colorscheme("habamax")
      T.eq(vim.api.nvim_get_hl(0, { name = "BudPendingAdd" }).link, "DiffAdd")
      vim.cmd.colorscheme("default")
    end,
  },
  {
    "keymaps and commands are registered",
    function(T)
      T.eq(vim.fn.maparg("<leader>aa", "n", false, true).desc, "Chat (toggle)")
      T.eq(vim.fn.maparg("<leader>aj", "x", false, true).desc, "Quick ask")
      T.eq(vim.fn.maparg("<leader>ak", "x", false, true).desc, "Write here")
      for _, c in ipairs({ "BudChat", "BudNew", "BudHistory", "BudSpawn", "BudLog", "BudInstructions", "BudSync" }) do
        T.eq(vim.fn.exists(":" .. c), 2, c)
      end
    end,
  },
}
