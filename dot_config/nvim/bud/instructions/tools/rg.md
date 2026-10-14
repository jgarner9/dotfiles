## ripgrep (`rg`)

Fast text search across the repo, respecting .gitignore. Run it through Bash.

- `rg -n 'pattern'` for matches with line numbers; add `-t go`, `-t lua` etc.
  to filter by language, or `-g '*.md'` by glob.
- `rg -l 'pattern'` to list files only; `rg -C 3` for context lines.
- `rg --files | rg name` to find a file by name.
- Use `-F` for literal strings with regex characters in them.

Keep searches narrow; if you get hundreds of hits, refine the pattern before
reading results.
