local config = require("bud.config")
local history = require("bud.history")
local log = require("bud.log")

return {
  {
    "log entries come back newest first and render",
    function(T)
      log.add({ mode = "quick", model = "haiku", prompt = "p1", response = "r1", time = 1 })
      log.add({
        mode = "chat",
        model = "sonnet",
        prompt = "p2",
        response = "r2",
        time = 2,
        usage = { input_tokens = 5, output_tokens = 6 },
      })
      local e = log.entries()
      T.eq(e[1].prompt, "p2")
      local text = table.concat(log.render(e[1]), "\n")
      T.contains(text, "# chat · sonnet")
      T.contains(text, "5 in · 6 out")
      T.contains(text, "## Response")
    end,
  },
  {
    "log trims to max_entries once it grows past 120%",
    function(T)
      local saved = config.options.log.max_entries
      config.options.log.max_entries = 10
      os.remove(log.path())
      for i = 1, 13 do
        log.add({ mode = "quick", prompt = "p" .. i })
      end
      log.trim()
      T.eq(#log.entries(), 10)
      T.eq(log.entries()[1].prompt, "p13")
      config.options.log.max_entries = saved
    end,
  },
  {
    "history saves per project and lists newest first",
    function(T)
      local root = T.project({})
      history.save({ id = "a", root = root, title = "first", lines = { "x" } })
      vim.wait(1100)
      history.save({ id = "b", root = root, title = "second", lines = { "y" } })
      history.save({ id = "c", root = T.project({}), title = "elsewhere", lines = { "z" } })
      local list = history.list(root)
      T.eq(#list, 2)
      T.eq(list[1].title, "second")
      history.delete(list[1])
      T.eq(#history.list(root), 1)
    end,
  },
  {
    "empty chats aren't saved",
    function(T)
      local root = T.project({})
      history.save({ id = "e", root = root, lines = {} })
      T.eq(#history.list(root), 0)
    end,
  },
}
