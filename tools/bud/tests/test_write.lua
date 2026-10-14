local write = require("bud.ui.write")

local ns = vim.api.nvim_get_namespaces().bud_write

-- the way the real keymaps call it, so startinsert applies
vim.keymap.set({ "n", "x" }, "<F4>", write.open)

local function lines()
  return vim.api.nvim_buf_get_lines(0, 0, -1, false)
end

local function virt_text()
  local out = {}
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, { details = true })) do
    for _, vl in ipairs(m[4].virt_lines or {}) do
      local s = ""
      for _, chunk in ipairs(vl) do
        s = s .. chunk[1]
      end
      table.insert(out, s)
    end
  end
  return out
end

local function wait_done(T)
  T.wait(function()
    return write.pending and write.pending.done
  end, 5000, "write finished")
end

return {
  {
    "normal mode on a blank line: preview, then keep fills the line",
    function(T)
      local root = T.project({ ["a.lua"] = "local function f()\n  \nend\n" })
      vim.cmd.edit(root .. "/a.lua")
      vim.api.nvim_win_set_cursor(0, { 2, 0 })
      T.control({ replies = { "```lua\nreturn 42\n```" } })
      T.keys("<F4>return the answer<CR>")
      wait_done(T)
      T.eq(lines(), { "local function f()", "  ", "end" }, "buffer untouched while pending")
      local virt = virt_text()
      T.eq(virt[1], "return 42")
      T.contains(virt[2], "<CR> keep")
      T.keys("<CR>")
      T.eq(lines(), { "local function f()", "  return 42", "end" }, "reindented to the block")
      T.eq(#vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, {}), 0)
      T.eq(write.pending, nil)
      vim.cmd("silent undo")
      T.eq(lines(), { "local function f()", "  ", "end" }, "u undoes the kept change")
      T.eq(vim.fn.maparg("<CR>", "n", false, true).buffer, nil, "keymaps restored")
    end,
  },
  {
    "an empty line inside a block gets the block's indent",
    function(T)
      local root = T.project({ ["a.lua"] = "local function f()\n\nend\n" })
      vim.cmd.edit(root .. "/a.lua")
      vim.bo.expandtab, vim.bo.shiftwidth = true, 2
      vim.api.nvim_win_set_cursor(0, { 2, 0 })
      T.control({ replies = { "return 42" } })
      T.keys("<F4>answer<CR>")
      wait_done(T)
      T.keys("<CR>")
      T.eq(lines(), { "local function f()", "  return 42", "end" })
    end,
  },
  {
    "normal mode on a code line inserts below it",
    function(T)
      local root = T.project({ ["a.py"] = "x = 1\ny = 2\n" })
      vim.cmd.edit(root .. "/a.py")
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      T.control({ replies = { "z = 3" } })
      T.keys("<F4>add z<CR>")
      wait_done(T)
      T.keys("<CR>")
      T.eq(lines(), { "x = 1", "z = 3", "y = 2" })
    end,
  },
  {
    "visual mode replaces the selection; Esc drops it",
    function(T)
      local root = T.project({ ["a.go"] = "package a\n\nfunc A() {\n\treturn\n}\n" })
      vim.cmd.edit(root .. "/a.go")
      vim.api.nvim_win_set_cursor(0, { 3, 0 })
      T.control({ replies = { "func B() {\n\treturn\n}", "func C() {}" } })
      T.keys("Vjj<F4>rename to B<CR>")
      wait_done(T)
      local prompt = require("bud.log").entries()[1].prompt
      T.contains(prompt, "<<<SELECTION START>>>\nfunc A() {")
      T.contains(prompt, "Replace the code between")
      T.keys("<CR>")
      T.eq(lines(), { "package a", "", "func B() {", "\treturn", "}" })
      -- and once more, dropped
      vim.api.nvim_win_set_cursor(0, { 3, 0 })
      T.keys("Vjj<F4>rename to C<CR>")
      wait_done(T)
      T.keys("<Esc>")
      T.eq(lines(), { "package a", "", "func B() {", "\treturn", "}" })
      T.eq(#vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, {}), 0)
    end,
  },
  {
    "selection on the last line of the buffer",
    function(T)
      local root = T.project({ ["a.txt"] = "one\ntwo" })
      vim.cmd.edit(root .. "/a.txt")
      vim.api.nvim_win_set_cursor(0, { 2, 0 })
      T.control({ replies = { "TWO" } })
      T.keys("V<F4>upper<CR>")
      wait_done(T)
      T.keys("<CR>")
      T.eq(lines(), { "one", "TWO" })
    end,
  },
  {
    "reindent only shifts flush-left output",
    function(T)
      local buf = vim.api.nvim_get_current_buf()
      vim.bo[buf].expandtab = true
      T.eq(write.reindent({ "a", "  b" }, 4, buf), { "    a", "      b" })
      T.eq(write.reindent({ "  a" }, 4, buf), { "  a" })
      T.eq(write.reindent({ "a", "", "b" }, 2, buf), { "  a", "", "  b" })
      vim.bo[buf].expandtab = false
      vim.bo[buf].tabstop = 4
      T.eq(write.reindent({ "a" }, 4, buf), { "\ta" })
    end,
  },
  {
    "extract drops fences and blank edges, even mid-stream",
    function(T)
      T.eq(write.extract("```go\n\nx := 1\n\n```"), { "x := 1" })
      T.eq(write.extract("```go\nx := 1\ny"), { "x := 1", "y" })
      T.eq(write.extract(""), {})
    end,
  },
}
