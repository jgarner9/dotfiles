## ast-grep

Syntax-aware search: matches code by its shape, not its text. Run it through
Bash.

- `ast-grep run -p 'PATTERN' -l LANG [PATH]`, where `$NAME` matches one node
  and `$$$` matches a list, e.g. `ast-grep run -p 'fmt.Errorf($$$)' -l go`
  or `ast-grep run -p 'vim.keymap.set($$$)' -l lua`.
- Use it when text search would be noisy: calls to a function, a struct
  literal, an `if err != nil` without a return.

Search only; never pass `--rewrite` or `-U`.
