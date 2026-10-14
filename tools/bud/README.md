# Bud tests

Headless tests for the Neovim plugin in `dot_config/nvim/lua/bud/`. They run
in `nvim -l` against `fake-claude`, a stand-in for the Claude Code CLI that
speaks the same stream-json protocol, so they cost nothing and need no login.

```sh
tools/bud/run.sh          # everything
tools/bud/run.sh chat     # just tests/test_chat.lua
NVIM=/opt/nvim/bin/nvim tools/bud/run.sh
```

A test file returns a list of `{ name, fn }`; `fn(T)` gets the helpers from
`runner.lua` (`T.eq`, `T.wait`, `T.keys`, `T.project`, `T.control` and so on).
`T.control({ replies = { ... }, delay_ms = 100, tool = { ... }, error = "..." })`
sets what the fake CLI answers next.

## Writing a test

- Add a case to the `tests/test_<area>.lua` the code belongs to, or make a new
  file that returns `{ { "what it checks", function(T) ... end } }`.
- Drive floats through a mapping (`vim.keymap.set("n", "<F5>", mod.open)`,
  then `T.keys("<F5>...")`) so `startinsert` applies the way it does for real
  keys.
- `T.project(files, git)` makes a temp project, `T.bin(name, script)` puts a
  fake command first on PATH, and `T.notifications()` captures `vim.notify`.
- `tools/bud/run.sh <area>` runs one file; `tools/test.sh` runs everything.

Bud's fixer (`bud-fix`, behind `<leader>ar`) reads this file before it
changes anything, so keep it accurate.
