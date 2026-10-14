# tools

Personal Go tools, built on every machine by chezmoi
(`run_onchange_after_build-go-tools.sh.tmpl` at the repo root) and installed to
`~/.local/bin`. chezmoi never copies this folder into `$HOME` (see
`.chezmoiignore`).

Each tool lives in `cmd/<name>/` with a `SPEC.md` and golden tests in
`testdata/`. The build runs `go test ./...` first and installs nothing if a test
fails.

| Tool | What it does |
| --- | --- |
| `repomap` | Ranked map of a repo's files and top-level symbols, for feeding an LLM |
| `bud-fix` | Turns a Bud bug report or feature request into a pull request (behind `<leader>ar`) |

Also here, because chezmoi ignores this folder:

- `dotsync/`: spec and tests for `dot_local/bin/executable_dotsync`
- `bud/`: tests for the Neovim plugin in `dot_config/nvim/lua/bud`

Run everything with `tools/test.sh`.
