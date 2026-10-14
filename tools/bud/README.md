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
