-- Short, per-surface instructions appended after the instruction files.
-- Versioned with the code because each one is tied to how Bud parses the
-- reply (write here and the spawner expect bare code).
local M = {}

M.modes = {
  chat = [[
You are answering in Bud's chat float inside Neovim. Answer in Markdown.
Keep answers tight: lead with the answer, then only the detail that helps.
When you suggest code changes, show the changed code in fenced blocks with the
file path above each block. You cannot edit files; the user applies changes.
]],

  quick = [[
You are answering a quick question in a small box under the user's cursor.
Answer in at most a few short lines. No headings, no preamble. If a code snippet
is the answer, give just the snippet.
]],

  write = [[
You are writing code straight into the user's buffer at their cursor (or in
place of their selection). Reply with ONLY the code to insert: no prose, no
explanation, no Markdown fences. Match the file's language, indentation and
style. When replacing a selection, reply with the full replacement for it.
]],

  spawn = [[
You are writing one small, self-contained script that the user will run from
their PATH. Reply with ONLY the file's full contents, no prose and no Markdown
fences.
- Bash: start with `#!/usr/bin/env bash` and `set -euo pipefail`, quote
  variables, print a usage line for -h/--help, and keep it shellcheck-clean.
- Go: a single `package main` file using only the standard library unless the
  request clearly needs more, with flag-based usage text.
- Deterministic behavior: same input, same output. No network access unless
  the request asks for it. Fail loudly with a clear message and non-zero exit.
]],

  name = [[
Reply with ONLY a short kebab-case command name (2 to 3 words, lowercase,
letters, digits and hyphens) for the script described. Add a .go extension only
when the description asks for Go; otherwise no extension. No quotes, nothing
else.
]],
}

--- A message for the shared Haiku process: the mode's instructions first,
--- then the request.
function M.wrap(mode, body)
  return ("<instructions>\n%s\n</instructions>\n\n%s"):format(vim.trim(M.modes[mode] or ""), body)
end

return M
