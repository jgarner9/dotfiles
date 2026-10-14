local config = require("bud.config")
local instructions = require("bud.instructions")
local tools = require("bud.tools")

return {
  {
    "chat gets base, active tool docs, repo rules and its mode",
    function(T)
      T.bin("repomap", "#!/bin/sh\necho map\n")
      local root = T.project({ [".bud/rules.md"] = "Use tabs.\n" })
      local text = instructions.text("chat", root)
      T.contains(text, "<!-- 00-base.md -->")
      T.contains(text, "# Working with Bud")
      T.contains(text, "<!-- tools/repomap.md -->")
      T.contains(text, "<!-- .bud/rules.md -->\nUse tabs.")
      T.contains(text, "<!-- mode: chat -->")
      -- order: base, tools, rules, mode
      T.ok(text:find("00-base", 1, true) < text:find("tools/repomap", 1, true))
      T.ok(text:find("tools/repomap", 1, true) < text:find(".bud/rules", 1, true))
      T.ok(text:find(".bud/rules", 1, true) < text:find("mode: chat", 1, true))
    end,
  },
  {
    "tool docs only for tools that are enabled and installed",
    function(T)
      local text = instructions.text("chat", T.project({}))
      T.ok(not text:find("tools/serena.md", 1, true), "serena is disabled")
      local saved = vim.deepcopy(config.options.tools)
      config.options.tools.serena = { enabled = true }
      T.ok(not instructions.text("chat", T.project({})):find("tools/serena.md", 1, true), "serena isn't installed")
      T.bin("serena", "#!/bin/sh\n")
      T.contains(instructions.text("chat", T.project({})), "tools/serena.md")
      config.options.tools = saved
    end,
  },
  {
    "shared and spawn processes skip tool docs; shared has no mode",
    function(T)
      local shared = instructions.text("shared", T.project({}))
      T.ok(not shared:find("tools/", 1, true))
      T.ok(not shared:find("mode:", 1, true))
      T.contains(instructions.text("spawn", T.project({})), "<!-- mode: spawn -->")
    end,
  },
  {
    "the fixer gets the tool docs and its own mode, which lifts the read-only rule",
    function(T)
      T.bin("rg", "#!/bin/sh\n")
      local text = instructions.text("fix", T.project({}))
      T.contains(text, "tools/rg.md")
      T.contains(text, "<!-- mode: fix -->")
      T.contains(text, "you may edit\nthe files the task names")
    end,
  },
  {
    "user files join in name order and path() caches with a hash",
    function(T)
      local dir = vim.fn.tempname()
      vim.fn.mkdir(dir, "p")
      for name, body in pairs({ ["50-go.md"] = "go rules", ["00-base.md"] = "base", ["10-me.md"] = "me" }) do
        local f = assert(io.open(dir .. "/" .. name, "w"))
        f:write(body)
        f:close()
      end
      local saved = config.options.instructions_dir
      config.options.instructions_dir = dir
      local text = instructions.text("shared", nil)
      T.ok(text:find("base", 1, true) < text:find("me", 1, true))
      T.ok(text:find("me", 1, true) < text:find("go rules", 1, true))
      local path, hash = instructions.path("shared", nil)
      T.eq(vim.fn.readfile(path)[1], "<!-- 00-base.md -->")
      T.eq(#hash, 64)
      config.options.instructions_dir = saved
    end,
  },
}
