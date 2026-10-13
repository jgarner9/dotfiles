local quick = require("bud.ui.quick")

-- the way the real keymaps call it, so startinsert applies
vim.keymap.set("n", "<F5>", quick.open)
vim.keymap.set("x", "<F3>", quick.open)

local function lines_of(win)
  return vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false)
end

return {
  {
    "normal mode: a box under the cursor, question only",
    function(T)
      local root = T.project({ ["a.lua"] = "local x = 1\nlocal y = 2\n" })
      vim.cmd.edit(root .. "/a.lua")
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      local src = vim.api.nvim_get_current_win()
      T.keys("<F5>how are you<CR>")
      local b = quick.box
      T.ok(b.win ~= src, "box has its own window")
      local cfg = vim.api.nvim_win_get_config(b.win)
      T.eq(cfg.relative, "win")
      T.eq(cfg.bufpos[1], 0)
      T.wait(function()
        return quick.current and quick.current.done
      end)
      T.eq(quick.current.answer, "echo: how are you")
      local shown = lines_of(b.win)
      T.eq(shown[1], "󰀄 how are you")
      T.eq(shown[2], "echo: how are you")
      local prompt = require("bud.log").entries()[1].prompt
      T.ok(not prompt:find("<context", 1, true), "no file context in normal mode")
      T.keys("y")
      T.eq(vim.fn.getreg('"'), "echo: how are you")
      T.keys("q")
      T.ok(not vim.api.nvim_win_is_valid(b.win))
      T.eq(vim.api.nvim_get_current_win(), src)
    end,
  },
  {
    "visual mode: the selection goes along",
    function(T)
      local root = T.project({ ["a.lua"] = "local x = 1\nlocal y = 2\nlocal z = 3\n" })
      vim.cmd.edit(root .. "/a.lua")
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      T.keys("Vj<F3>what<CR>")
      local b = quick.box
      T.eq(vim.api.nvim_win_get_config(b.win).bufpos[1], 1, "anchored under the selection")
      T.wait(function()
        return quick.current and quick.current.done
      end)
      local prompt = require("bud.log").entries()[1].prompt
      T.contains(prompt, "<context selection>")
      T.contains(prompt, "1  local x = 1")
      T.contains(prompt, "Question about the selected code: what")
      T.keys("q")
    end,
  },
  {
    "the box grows with the answer, up to max_height",
    function(T)
      local root = T.project({ ["a.txt"] = "x\n" })
      vim.cmd.edit(root .. "/a.txt")
      T.control({ replies = { table.concat(vim.split(string.rep("line\n", 30), "\n"), "\n") } })
      T.keys("<F5>long<CR>")
      local b = quick.box
      T.wait(function()
        return quick.current and quick.current.done
      end)
      T.eq(vim.api.nvim_win_get_height(b.win), require("bud.config").quick.max_height)
      T.keys("q")
    end,
  },
  {
    "Esc on the empty prompt closes without asking",
    function(T)
      local root = T.project({ ["a.txt"] = "x\n" })
      vim.cmd.edit(root .. "/a.txt")
      local before = #require("bud.log").entries()
      T.keys("<F5><Esc>")
      local b = quick.box
      vim.wait(100)
      T.ok(not vim.api.nvim_win_is_valid(b.win))
      T.eq(#require("bud.log").entries(), before)
    end,
  },
  {
    "Tab moves the finished answer into the chat",
    function(T)
      local root = T.project({ ["a.txt"] = "x\n" })
      vim.cmd.edit(root .. "/a.txt")
      T.keys("<F5>promote me<CR>")
      T.wait(function()
        return quick.current and quick.current.done
      end)
      T.keys("<Tab>")
      local chat = require("bud.ui.chat")
      T.ok(chat.is_open())
      local text = table.concat(vim.api.nvim_buf_get_lines(chat.state.buf, 0, -1, false), "\n")
      T.contains(text, "promote me")
      T.contains(text, "echo: promote me")
      chat.hide()
      chat.new()
      chat.hide()
    end,
  },
}
