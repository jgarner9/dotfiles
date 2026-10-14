local testgen = require("bud.testgen")

local source = [[package calc

type Calc struct{}

func Add(a, b int) int {
	return a + b
}

func (c *Calc) Double(a int) int {
	return Add(a, a)
}

func init() {}
]]

local good_test = [[package calc

import "testing"

func TestAdd(t *testing.T) {
	for _, c := range []struct{ a, b, want int }{{1, 2, 3}, {0, 0, 0}, {-1, 1, 0}} {
		if got := Add(c.a, c.b); got != c.want {
			t.Errorf("Add(%d, %d) = %d, want %d", c.a, c.b, got, c.want)
		}
	}
}
]]

local function go_project(T, extra)
  local files = { ["go.mod"] = "module calc\n\ngo 1.21\n", ["calc.go"] = source }
  for k, v in pairs(extra or {}) do
    files[k] = v
  end
  return T.project(files)
end

local function wait_result(T)
  local res
  return function(ok, results)
    res = { ok = ok, results = results }
  end, function()
    T.wait(function()
      return res
    end, 30000, "test spawner finished")
    return res
  end
end

return {
  {
    "funcs: functions and methods are listed, init is skipped",
    function(T)
      local list = testgen.funcs(vim.split(source, "\n"))
      T.eq(#list, 2)
      T.eq(list[1].name, "Add")
      T.eq(list[1].line, 5)
      T.eq(list[2].name, "Double")
      T.eq(list[2].label, "*Calc.Double")
    end,
  },
  {
    "the target sits next to the source as _test.go",
    function(T)
      local t = testgen.target("/proj/pkg/calc.go", "/proj")
      T.eq(t.path, "/proj/pkg/calc_test.go")
      T.eq(t.cwd, "/proj/pkg")
      T.eq(t.kind, "go")
      T.ok(t.test)
    end,
  },
  {
    "the request carries the source, the focus, and existing tests",
    function(T)
      local d = testgen.describe("calc.go", source, "Add", "overflow", "package calc // old")
      T.contains(d, "the function `Add` in calc.go")
      T.contains(d, "func Add(a, b int) int")
      T.contains(d, "Cover in particular: overflow")
      T.contains(d, "package calc // old")
      local whole = testgen.describe("calc.go", source, nil, "", nil)
      T.contains(whole, "the code in calc.go")
      T.eq(whole:find("already exists", 1, true), nil)
    end,
  },
  {
    "writes the tests, then vets and runs them",
    function(T)
      if vim.fn.executable("go") == 0 then
        return
      end
      local root = go_project(T)
      T.control({ replies = { "```go\n" .. good_test .. "```" } })
      local t = testgen.target(root .. "/calc.go", root)
      local cb, result = wait_result(T)
      require("bud.spawn").generate(testgen.describe("calc.go", source, "Add", "", nil), t, cb)
      local res = result()
      T.ok(res.ok, vim.inspect(res.results))
      T.eq(res.results[1].name, "go vet")
      T.eq(res.results[2].name, "go test")
      T.eq(table.concat(vim.fn.readfile(t.path), "\n") .. "\n", good_test)
      T.eq(vim.fn.executable(t.path), 0, "a test file is not made executable")
      T.contains(require("bud.log").entries()[1].prompt, "It will be saved as")
      T.keys("q")
    end,
  },
  {
    "a failing test run is retried once with the errors",
    function(T)
      if vim.fn.executable("go") == 0 then
        return
      end
      local root = go_project(T)
      local bad = good_test:gsub("{1, 2, 3}", "{1, 2, 4}")
      T.control({ replies = { bad, good_test } })
      local t = testgen.target(root .. "/calc.go", root)
      local cb, result = wait_result(T)
      require("bud.spawn").generate("tests for Add", t, cb)
      T.ok(result().ok)
      T.contains(require("bud.log").entries()[1].prompt, "go test:")
      T.keys("q")
    end,
  },
  {
    "open: a non-Go buffer, like netrw, is refused with a hint",
    function(T)
      local root = T.project({ ["notes.txt"] = "hi\n" })
      vim.cmd.edit(root .. "/notes.txt")
      local notes = T.notifications()
      testgen.open()
      T.contains(notes[#notes].msg, "Open a Go source file")
      T.eq(notes[#notes].level, vim.log.levels.WARN)
      vim.cmd.edit(root .. "/x_test.go")
      testgen.open()
      T.eq(#notes, 2, "_test.go files are refused too")
    end,
  },
  {
    "open: function under the cursor first, then the notes, then generation",
    function(T)
      if vim.fn.executable("go") == 0 then
        return
      end
      local root = go_project(T)
      vim.cmd.edit(root .. "/calc.go")
      vim.api.nvim_win_set_cursor(0, { 10, 0 })
      T.control({ replies = { good_test } })
      local choices
      local orig_select, orig_input = vim.ui.select, vim.ui.input
      vim.ui.select = function(items, opts, cb)
        choices = vim.tbl_map(opts.format_item, items)
        vim.schedule(function()
          cb(items[1])
        end)
      end
      vim.ui.input = function(_, cb)
        vim.schedule(function()
          cb("negative numbers")
        end)
      end
      testgen.open()
      T.wait(function()
        return vim.uv.fs_stat(root .. "/calc_test.go") ~= nil and #require("bud.log").entries() > 0
      end, 30000)
      vim.ui.select, vim.ui.input = orig_select, orig_input
      T.eq(choices, { "*Calc.Double", "Add", "Whole file" })
      local e = require("bud.log").entries()[1]
      T.contains(e.prompt, "the function `Double` in calc.go")
      T.contains(e.prompt, "Cover in particular: negative numbers")
      T.wait(function()
        return vim.api.nvim_buf_get_name(0):match("calc_test%.go$")
      end, 30000, "result float")
      T.keys("q")
    end,
  },
  {
    "open: an existing test file is sent along to be extended",
    function(T)
      if vim.fn.executable("go") == 0 then
        return
      end
      local root = go_project(T, { ["calc_test.go"] = good_test })
      vim.cmd.edit(root .. "/calc.go")
      T.control({ replies = { good_test } })
      local orig_select, orig_input = vim.ui.select, vim.ui.input
      vim.ui.select = function(items, _, cb)
        vim.schedule(function()
          cb(items[#items])
        end)
      end
      vim.ui.input = function(_, cb)
        vim.schedule(function()
          cb("")
        end)
      end
      testgen.open()
      T.wait(function()
        return #require("bud.log").entries() > 0
      end, 30000)
      vim.ui.select, vim.ui.input = orig_select, orig_input
      local e = require("bud.log").entries()[1]
      T.contains(e.prompt, "already exists")
      T.contains(e.prompt, "func TestAdd")
      T.wait(function()
        return vim.api.nvim_buf_get_name(0):match("calc_test%.go$")
      end, 30000, "result float")
      T.keys("q")
    end,
  },
}
