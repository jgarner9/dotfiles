# dotsync

Pull the chezmoi source repo and apply it, safely, from a background process.
Neovim (Bud) runs `dotsync --json` on startup; you can also run it by hand.

## Usage

```
dotsync [--force] [--json] [--quiet]
```

| Flag | Effect |
| --- | --- |
| `--force` | Ignore the throttle |
| `--json` | Print exactly one JSON object (see Output) |
| `--quiet` | Print nothing unless the run fails |

Environment: `DOTSYNC_INTERVAL` (seconds, default 1800), `DOTSYNC_STALE_LOCK`
(seconds, default 600), `XDG_STATE_HOME` (state lives in `$XDG_STATE_HOME/dotsync`,
default `~/.local/state/dotsync`).

## Behavior, in order

1. `chezmoi` or `git` missing: `error`, exit 1.
2. Throttle: if the last started run was less than `DOTSYNC_INTERVAL` seconds
   ago and `--force` is not set: `skipped_throttle`, exit 0. Skipped runs do
   not reset the clock.
3. Lock: a lock directory older than `DOTSYNC_STALE_LOCK` is removed. If the lock
   is held: `skipped_locked`, exit 0. The lock is always released on exit.
4. Source: `chezmoi source-path` must be a git repo with an upstream branch,
   otherwise `error`, exit 1.
5. Pull: `git pull --ff-only`. Never rebases, never merges, never pushes. A
   failed pull (diverged history, conflicts) is `error`, exit 1.
6. Nothing new: `up_to_date`, exit 0. No apply runs.
7. Drift: any `chezmoi status` line whose first column is not a space is a
   file edited outside chezmoi. Any drift: `skipped_drift` with the paths,
   exit 0. The pull stays; the apply does not run.
8. Apply: `chezmoi apply --no-tty`. Failure is `error`, exit 1.
9. Success: `synced`, exit 0. `nvim_changed` is true when any changed path
   starts with `dot_config/nvim/`.

Every run appends one line to `dotsync.log` in the state dir.

## Output (`--json`)

```json
{"status":"synced","message":"synced 2 change(s)","changed":["dot_zshrc"],"drift":[],"nvim_changed":false}
```

`status` is one of `synced`, `up_to_date`, `skipped_throttle`, `skipped_locked`,
`skipped_drift`, `error`.

## Tests

`tools/dotsync/dotsync_test.sh` builds a throwaway origin and clone with real
git and a fake `chezmoi`, then checks each status above.
