# repomap

Print a ranked map of a repository's files and their top-level symbols, so an
LLM (or you) can see the shape of a codebase before reading any of it. Bud puts
this at the top of every new chat when `repomap` is installed.

## Usage

```
repomap [-root DIR] [-max N] [-per N] [-json] [-no-git]
```

| Flag | Default | Effect |
| --- | --- | --- |
| `-root` | `.` | Repository root |
| `-max` | 50 | Files to print, 0 = all |
| `-per` | 15 | Symbols per file, 0 = all |
| `-json` | off | JSON instead of text |
| `-no-git` | off | Walk the tree instead of using `git ls-files` |

## Rules

- Files come from `git ls-files --cached --others --exclude-standard`, so
  `.gitignore` is respected. Outside git (or with `-no-git`) the tree is walked,
  skipping `.git`, `node_modules`, `vendor`, `dist`, `build`, `target`,
  `.venv`, `venv`, `__pycache__` and `.cache`.
- Files over 512 KB or containing a NUL byte in the first 8 KB are ignored.
- Symbols are found line by line with regular expressions for Go, Lua, Python,
  JS/TS, Rust, Ruby and shell. Only top-level definitions (plus Python methods
  at 4-space indent and Rust fns at up to 4 spaces) count.
- A symbol's references = how many times its last name segment appears as an
  identifier across all text files, minus the number of definitions with that
  name (zero for names shorter than 3 characters). A file's score is the sum of its symbols' references.
- Files sort by score (high first), then path. Symbols sort by references, then
  line. The same tree always gives the same output.

## Output

```
repomap: 6 of 9 files shown, ranked by references

server.go (refs 7)
  fn     NewCache    L9     3
  method Cache.Get   L11    2
```

## Tests

`go test ./cmd/repomap` checks golden output in `testdata/`. After an
intentional change, regenerate with `go test ./cmd/repomap -update` and review
the diff.
