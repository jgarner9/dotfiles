local chat = require("bud.ui.chat")
local history = require("bud.history")

local function setup(T)
  local root = T.project({ ["src/main.go"] = 'package main\n\nfunc main() {\n\tprintln("hi")\n}\n' }, true)
  vim.cmd.edit(root .. "/src/main.go")
  vim.api.nvim_win_set_cursor(0, { 3, 0 })
  return root
end

local function transcript()
  return table.concat(vim.api.nvim_buf_get_lines(chat.state.buf, 0, -1, false), "\n")
end

local function send(T, text)
  vim.api.nvim_buf_set_lines(chat.state.input, 0, -1, false, { text })
  chat.send()
  T.wait(function()
    return not chat.state.busy
  end, 8000, "answer")
end

return {
  {
    "toggle opens a float docked right and hides it again",
    function(T)
      setup(T)
      chat.new()
      chat.hide()
      local origin = vim.api.nvim_get_current_win()
      chat.toggle()
      T.ok(chat.is_open())
      local cfg = vim.api.nvim_win_get_config(chat.state.win)
      T.eq(cfg.relative, "editor")
      T.eq(cfg.col + cfg.width + 2, vim.o.columns, "docked to the right edge")
      T.ok(math.abs(cfg.width - math.floor(vim.o.columns * 0.45)) <= 1, "about 45% wide")
      T.eq(vim.api.nvim_get_current_win(), chat.state.input_win)
      T.eq(vim.bo[chat.state.buf].filetype, "bud_chat")
      chat.toggle()
      T.ok(not chat.is_open())
      T.eq(vim.api.nvim_get_current_win(), origin)
    end,
  },
  {
    "the view you came from goes with the next message, shown as a chip",
    function(T)
      local root = setup(T)
      chat.new()
      T.ok(chat.state.pending, "view captured on open")
      T.eq(chat.state.pending.rel, "src/main.go")
      send(T, "what does this do?")
      local text = transcript()
      T.contains(text, "## 󰀄 You")
      T.contains(text, "`󰈙 src/main.go · L1–")
      T.contains(text, "what does this do?")
      T.contains(text, "## 󰚩 Bud")
      T.contains(text, "echo: what does this do?")
      T.eq(chat.state.pending, nil, "sent once")
      local e = require("bud.log").entries()[1]
      T.eq(e.mode, "chat")
      T.contains(e.prompt, "<context view>")
      T.contains(e.prompt, "func main() {")
      local run = T.claude_runs()[#T.claude_runs()]
      T.eq(run.cwd, root)
      local args = table.concat(run.args, " ")
      T.contains(args, "--model sonnet")
      T.match(args, "instructions%-chat%-")
      T.contains(args, "--permission-mode dontAsk")
      -- the second message has no view: the chat already has it
      send(T, "and then?")
      T.ok(not require("bud.log").entries()[1].prompt:find("<context view>", 1, true))
      chat.hide()
    end,
  },
  {
    "the repomap goes once at the start of a chat",
    function(T)
      T.bin("repomap", "#!/bin/sh\necho 'src/main.go'\necho '  func main'\n")
      setup(T)
      chat.new()
      send(T, "one")
      T.contains(require("bud.log").entries()[1].prompt, "<repomap>\nsrc/main.go")
      send(T, "two")
      T.ok(not require("bud.log").entries()[1].prompt:find("<repomap>", 1, true))
      chat.hide()
      os.remove(T.work .. "/bin/repomap")
    end,
  },
  {
    "tool calls show up in the transcript",
    function(T)
      setup(T)
      chat.new()
      T.control({ tool = { name = "Bash", input = { command = "rg -n main" } } })
      send(T, "find main")
      T.contains(transcript(), "> 󰆍 rg -n main")
      chat.hide()
    end,
  },
  {
    "history keeps one turn after another, and new starts fresh",
    function(T)
      local root = setup(T)
      chat.new()
      send(T, "first question")
      send(T, "second question")
      local text = transcript()
      T.ok(text:find("first question", 1, true) < text:find("second question", 1, true))
      local saved = history.list(root)[1]
      T.eq(saved.title, "first question")
      T.match(saved.session_id, "^fake%-")
      chat.new()
      T.eq(transcript(), "")
      T.eq(chat.state.session_id, nil)
      chat.hide()
    end,
  },
  {
    "loading a saved chat resumes its Claude session",
    function(T)
      local root = setup(T)
      chat.new()
      send(T, "remember this")
      local sid = chat.state.session_id
      local saved = history.list(root)[1]
      chat.new()
      chat.load(saved)
      T.contains(transcript(), "remember this")
      send(T, "follow up")
      local args = table.concat(T.claude_runs()[#T.claude_runs()].args, " ")
      T.contains(args, "--resume " .. sid)
      chat.hide()
    end,
  },
  {
    "cancel stops the answer and the next message resumes",
    function(T)
      setup(T)
      chat.new()
      send(T, "warm up")
      local sid = chat.state.session_id
      T.control({ delay_ms = 100, replies = { string.rep("y", 300) } })
      vim.api.nvim_buf_set_lines(chat.state.input, 0, -1, false, { "long one" })
      chat.send()
      T.wait(function()
        return transcript():find("yyyyy", 1, true)
      end)
      chat.cancel()
      T.wait(function()
        return not chat.state.busy
      end)
      T.contains(transcript(), "> Cancelled")
      T.control({})
      send(T, "after cancel")
      T.contains(table.concat(T.claude_runs()[#T.claude_runs()].args, " "), "--resume " .. sid)
      T.contains(transcript(), "echo: after cancel")
      chat.hide()
    end,
  },
  {
    "@ mentions expand into context and chips",
    function(T)
      local root = setup(T)
      chat.new()
      send(T, "compare with @file:src/main.go#L3-5 please")
      local text = transcript()
      T.contains(text, "`󰈙 src/main.go · L3–5`")
      local prompt = require("bud.log").entries()[1].prompt
      T.contains(prompt, "<context file>\nFile: src/main.go, lines 3–5")
      chat.hide()
    end,
  },
  {
    "promote moves a quick ask into the chat",
    function(T)
      setup(T)
      chat.new()
      chat.hide()
      chat.promote({ question = "what is x?", answer = "x is 1", model = "haiku" })
      T.ok(chat.is_open())
      T.contains(transcript(), "## 󱐋 Quick ask")
      T.contains(transcript(), "x is 1")
      send(T, "why?")
      T.contains(require("bud.log").entries()[1].prompt, "<earlier-quick-ask>")
      chat.hide()
    end,
  },
  {
    "gy yanks the code block under the cursor",
    function(T)
      setup(T)
      chat.new()
      T.control({ replies = { "Try:\n\n```lua\nlocal a = 1\nlocal b = 2\n```\n" } })
      send(T, "code please")
      vim.api.nvim_set_current_win(chat.state.win)
      local lines = vim.api.nvim_buf_get_lines(chat.state.buf, 0, -1, false)
      for i, l in ipairs(lines) do
        if l == "local a = 1" then
          vim.api.nvim_win_set_cursor(0, { i, 0 })
        end
      end
      chat.yank_block()
      T.eq(vim.fn.getreg('"'), "local a = 1\nlocal b = 2\n")
      chat.hide()
    end,
  },
}
