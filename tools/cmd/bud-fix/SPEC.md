# bud-fix

Turn a bug report or feature request for Bud into a pull request. Bud's
reporter (`<leader>ar` in Neovim) starts it detached, so quitting Neovim never
stops a fix; it works just as well from a shell.

Claude makes the change. Everything around it is bud-fix's, and deterministic:
it files the issue, prepares the worktree, checks what Claude touched, runs the
tests itself, commits, pushes and opens the PR. It never merges.

## Usage

```
bud-fix report -kind bug|feature -title TITLE -body-file FILE [-context-file FILE] [flags]
bud-fix issue [flags] NUMBER
bud-fix status [-json] [-n N] [-state DIR]
```

`report` files a new issue from the body file, then fixes it. `issue` fixes one
that already exists (its `bug` label makes it a bug; anything else is a
feature). Both print the PR URL when they finish and exit non-zero on failure.
`status` lists recent runs.

| Flag | Default | Effect |
| --- | --- | --- |
| `-repo` | `chezmoi source-path` | The dotfiles repo |
| `-state` | `$XDG_STATE_HOME/bud/fixes` | Run records |
| `-cache` | `$XDG_CACHE_HOME/bud` | Worktrees go in `<cache>/worktrees/<id>` |
| `-model` | `sonnet` | Claude model |
| `-system-file` | none | Appended to Claude's system prompt (Bud passes its instruction files) |
| `-context-file` | none | Extra context for Claude that stays out of the issue |
| `-edit` | Bud's files and `tools/` | Path glob Claude may edit, repeatable |
| `-allow` | none | Extra `--allowedTools` rule, repeatable |
| `-test` | `bash tools/test.sh` | Test command, run in the worktree |
| `-base` | `origin/HEAD` | Base ref for the branch |
| `-timeout` | 45m | How long Claude may work |
| `-test-timeout` | 20m | How long the tests may run |
| `-no-pr` | off | Commit on the branch and stop: no push, no PR |
| `-claude`, `-gh` | `claude`, `gh` | The CLIs to run |

## A run

1. **filing**: `gh issue create` with labels `bud` and `bug` or `enhancement`
   (created if the repo doesn't have them). For `issue N`, `gh issue view`.
2. **queued**: one fix at a time, through a `flock` on `<state>/fix.lock`. A
   second report waits here.
3. **preparing**: `git fetch origin`, then a worktree at
   `<cache>/worktrees/<id>` on a new branch `bud/<issue>-<slug>` from the base
   (`-2`, `-3`… when an earlier attempt used the name).
4. **fixing**: `claude -p` in the worktree, the task on stdin:
   - `--restricted` when the CLI has it: no user or project settings, file
     tools confined to the worktree.
   - `--tools Read,Grep,Glob,Edit,Write,Bash --permission-mode dontAsk
     --strict-mcp-config`, so anything not allowed is denied, never asked.
   - Allowed: reading and searching, `Edit(./<glob>)` for each `-edit` glob,
     and in Bash only the test runners, `go -C tools test|vet`, `rg`,
     `shellcheck` and read-only git (status, diff, log, show), plus `-allow`.
     No commit, push, `gh` or network.
   - A bug must be reproduced with a failing test first; a feature comes with
     tests. Claude ends with `Title:` and a Before/After/How description.
5. **testing**: if nothing changed, the run ends as `no_change` with Claude's
   notes as an issue comment. If anything changed outside the `-edit` globs,
   it fails and nothing is pushed (the worktree is kept). Otherwise bud-fix
   runs `-test` itself and checks the paths again.
6. **pushing**: commit (`<title>`, `Refs #N`, a `Co-Authored-By: Claude`
   trailer), push, `gh pr create` with `Fixes #N` and the test result. The PR
   is a draft when the tests failed or Claude stopped early, with the tests'
   last 40 lines in the body.
7. **done**: the worktree and the local branch are removed.

A failure at any step ends the run as `failed` with the error, keeping the
worktree when there is one. SIGINT or SIGTERM stops Claude and fails the run
as `cancelled`. SIGHUP and SIGPIPE are ignored, so a closed terminal or a
gone Neovim don't matter.

## State

`<state>/<id>.json` is rewritten atomically after every step; `<id>.log` has
the steps, Claude's tool calls and the test output. The id is
`YYYYMMDD-HHMMSS-xxxx`, so ids sort by start time.

```json
{
  "id": "20261013-173215-ab12",
  "pid": 41234,
  "kind": "bug",
  "title": "Chat footer shows nil after a cancel",
  "phase": "done",
  "issue": 12,
  "issue_url": "https://github.com/jgarner9/dotfiles/issues/12",
  "branch": "bud/12-chat-footer-shows-nil-after",
  "pr": 14,
  "pr_url": "https://github.com/jgarner9/dotfiles/pull/14",
  "tests": "passed",
  "session_id": "…",
  "summary": "Claude's last message",
  "log": "…/20261013-173215-ab12.log",
  "started": "…", "updated": "…", "finished": "…"
}
```

Phases: `filing`, `queued`, `preparing`, `fixing`, `testing`, `pushing`, then
one of `done`, `no_change`, `failed`. A run that isn't finished and whose `pid`
is gone reads as failed ("stopped before it finished").

## Tests

`main_test.go` runs whole fixes against real git, with a local bare repo as
origin and fake `claude` and `gh` scripts: a fix to a PR, failing tests to a
draft, no changes to a comment, out-of-scope edits refused, an existing issue,
missing labels, Claude errors and crashes, the queue, and cancelling.
