local context = require("bud.context")

local function open(T, files, path)
  local root = T.project(files, true)
  vim.cmd.edit(root .. "/" .. path)
  return root
end

return {
  {
    "ignored: built-in secrets and .bud/ignore patterns",
    function(T)
      local root = T.project({ [".bud/ignore"] = "# secrets\ngenerated/\n*.sqlite\n/top.txt\n" })
      T.ok(context.ignored(root, root .. "/.env"))
      T.ok(context.ignored(root, root .. "/deep/dir/.env.local"))
      T.ok(context.ignored(root, root .. "/certs/server.pem"))
      T.ok(context.ignored(root, root .. "/generated/x.go"))
      T.ok(context.ignored(root, root .. "/a/generated/x.go"))
      T.ok(context.ignored(root, root .. "/db/app.sqlite"))
      T.ok(context.ignored(root, root .. "/top.txt"))
      T.ok(not context.ignored(root, root .. "/sub/top.txt"), "anchored pattern")
      T.ok(not context.ignored(root, root .. "/main.go"))
    end,
  },
  {
    "view captures the visible lines, cursor and diagnostics",
    function(T)
      local lines = {}
      for i = 1, 30 do
        lines[i] = "line " .. i
      end
      open(T, { ["src/a.lua"] = table.concat(lines, "\n") .. "\n" }, "src/a.lua")
      local buf = vim.api.nvim_get_current_buf()
      local ns = vim.api.nvim_create_namespace("test")
      vim.diagnostic.set(
        ns,
        buf,
        { { lnum = 2, col = 0, message = "bad thing", severity = vim.diagnostic.severity.ERROR, source = "lint" } }
      )
      vim.api.nvim_win_set_cursor(0, { 3, 0 })
      local ctx = context.view()
      T.eq(ctx.rel, "src/a.lua")
      T.eq(ctx.first, 1)
      T.ok(ctx.last >= 3)
      T.eq(ctx.cursor, 3)
      T.eq(#ctx.diagnostics, 1)
      T.eq(ctx.diagnostics[1].lnum, 3)
      T.match(context.chip(ctx), "src/a%.lua · L1–%d+ · 1 diagnostic$")
      local text = context.format(ctx)
      T.contains(text, "<context view>")
      T.contains(text, "Cursor on line 3.")
      T.match(text, "\n 3  line 3\n")
      T.contains(text, "- L3 error: bad thing (lint)")
    end,
  },
  {
    "view of an ignored file sends no contents",
    function(T)
      open(T, { [".env"] = "SECRET=1\n" }, ".env")
      local ctx = context.view()
      T.ok(ctx.ignored)
      local text = context.format(ctx)
      T.contains(text, "Contents not sent")
      T.ok(not text:find("SECRET", 1, true))
    end,
  },
  {
    "selection reads the visual range while in visual mode",
    function(T)
      open(T, { ["a.go"] = "package a\n\nfunc A() {}\nfunc B() {}\n" }, "a.go")
      vim.api.nvim_win_set_cursor(0, { 3, 0 })
      local got
      vim.keymap.set("x", "<F2>", function()
        got = context.selection()
      end)
      T.keys("Vj<F2><Esc>")
      T.ok(got, "selection captured")
      T.eq(got.first, 3)
      T.eq(got.last, 4)
      T.eq(got.text, "func A() {}\nfunc B() {}")
      T.eq(context.selection(), nil)
    end,
  },
  {
    "surrounding marks where the output goes",
    function(T)
      open(T, { ["a.txt"] = "one\ntwo\nthree\nfour\n" }, "a.txt")
      local buf = vim.api.nvim_get_current_buf()
      T.eq(context.surrounding(buf, 2), "one\n<<<INSERT HERE>>>\ntwo\nthree\nfour")
      T.eq(
        context.surrounding(buf, 2, { first = 2, last = 3 }),
        "one\n<<<SELECTION START>>>\ntwo\nthree\n<<<SELECTION END>>>\nfour"
      )
    end,
  },
}
