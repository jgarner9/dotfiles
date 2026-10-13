local spawn = require("bud.spawn")

local good_bash = [=[#!/usr/bin/env bash
set -euo pipefail
if [[ ${1:-} == -h || ${1:-} == --help ]]; then
	echo "usage: hello [name]"
	exit 0
fi
echo "hello ${1:-world}"
]=]

local function wait_result(T)
  local res
  return function(ok, results)
    res = { ok = ok, results = results }
  end, function()
    T.wait(function()
      return res
    end, 15000, "spawner finished")
    return res
  end
end

return {
  {
    "names: suggestions are cleaned, slugs are the fallback",
    function(T)
      T.eq(spawn.clean_name("`git-prune-merged`\n"), "git-prune-merged")
      T.eq(spawn.clean_name("Port Check.sh"), "port-check")
      T.eq(spawn.clean_name("json-fmt.go"), "json-fmt.go")
      T.eq(spawn.clean_name("  "), nil)
      T.eq(spawn.slug("A script that lists the largest files in a directory"), "lists-largest-files")
    end,
  },
  {
    "targets: project paths, the root, and @bin",
    function(T)
      local t = spawn.target("/proj", "", "hello")
      T.eq(t.path, "/proj/hello")
      T.eq(t.kind, "bash")
      T.eq(spawn.target("/proj", "./scripts/", "x").path, "/proj/scripts/x")
      local g = spawn.target("/proj", "tools", "fmt.go")
      T.eq(g.kind, "go")
      T.eq(g.path, "/proj/tools/fmt.go")
      spawn._source = "/src"
      local b = spawn.target("/proj", "@bin", "hello")
      T.eq(b.path, "/src/dot_local/bin/executable_hello")
      T.ok(b.bin)
      local bg = spawn.target("/proj", "@bin", "fmt.go")
      T.eq(bg.path, "/src/tools/cmd/fmt/main.go")
      T.eq(bg.cwd, "/src/tools")
      spawn._source = nil
    end,
  },
  {
    "writes, checks and opens a Bash script",
    function(T)
      local root = T.project({})
      T.control({ replies = { "```bash\n" .. good_bash .. "```" } })
      local t = spawn.target(root, "bin", "hello")
      local cb, result = wait_result(T)
      spawn.generate("say hello", t, cb)
      local res = result()
      T.ok(res.ok, vim.inspect(res.results))
      T.eq(table.concat(vim.fn.readfile(t.path), "\n") .. "\n", good_bash)
      T.eq(vim.fn.executable(t.path), 1)
      T.eq(res.results[1].name, "bash -n")
      local out = vim.fn.system({ t.path, "bud" })
      T.eq(out, "hello bud\n")
      T.eq(vim.api.nvim_buf_get_name(0), t.path, "opened in a float")
      T.ok(vim.api.nvim_win_get_config(0).relative ~= "")
      T.keys("q")
      T.eq(vim.fn.maparg("q", "n", false, true).buffer, nil, "q unmapped after close")
    end,
  },
  {
    "a failing check is retried once with the errors",
    function(T)
      local root = T.project({})
      T.control({ replies = { "#!/usr/bin/env bash\nif then fi\n", good_bash } })
      local t = spawn.target(root, "", "hello")
      local cb, result = wait_result(T)
      spawn.generate("say hello", t, cb)
      local res = result()
      T.ok(res.ok)
      local e = require("bud.log").entries()[1]
      T.contains(e.prompt, "Your previous version failed these checks:")
      T.contains(e.prompt, "bash -n:")
      T.contains(e.prompt, "if then fi")
      T.keys("q")
    end,
  },
  {
    "still failing after the retry: reported, not installed",
    function(T)
      local root = T.project({})
      T.control({ replies = { "#!/usr/bin/env bash\nif then fi\n", "#!/usr/bin/env bash\nif then fi\n" } })
      local notes = T.notifications()
      local t = spawn.target(root, "", "broken")
      local cb, result = wait_result(T)
      spawn.generate("broken", t, cb)
      local res = result()
      T.eq(res.ok, false)
      T.contains(notes[#notes].msg, "✗ bash -n")
      T.eq(notes[#notes].level, vim.log.levels.WARN)
      T.keys("q")
    end,
  },
  {
    "Go programs are vetted and built",
    function(T)
      if vim.fn.executable("go") == 0 then
        return
      end
      local root = T.project({})
      T.control({ replies = { 'package main\n\nimport "fmt"\n\nfunc main() {\n\tfmt.Println("hi")\n}\n' } })
      local t = spawn.target(root, "", "hi.go")
      local cb, result = wait_result(T)
      spawn.generate("print hi", t, cb)
      local res = result()
      T.ok(res.ok, vim.inspect(res.results))
      T.eq(res.results[1].name, "go vet")
      T.eq(res.results[2].name, "go build")
      T.keys("q")
    end,
  },
  {
    "the three prompts: description, path, name (suggested)",
    function(T)
      local root = T.project({}, true)
      vim.cmd.edit(root .. "/x.txt")
      T.control({ replies = { "count-lines", good_bash } })
      local answers = { "count lines in files", "scripts", nil }
      local prompts = {}
      local orig = vim.ui.input
      vim.ui.input = function(opts, cb)
        table.insert(prompts, opts)
        local i = #prompts
        vim.schedule(function()
          cb(answers[i] or opts.default)
        end)
      end
      local notes = T.notifications()
      spawn.open()
      T.wait(function()
        return vim.uv.fs_stat(root .. "/scripts/count-lines")
          and #notes > 0
          and notes[#notes].msg:find("bash -n", 1, true)
      end, 15000)
      vim.ui.input = orig
      T.eq(#prompts, 3)
      T.eq(prompts[3].default, "count-lines", "Haiku's suggestion is the default")
      T.keys("q")
    end,
  },
}
