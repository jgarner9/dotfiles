## Serena (MCP)

Symbol-level tools backed by language servers.

- Find a symbol by name, list a file's symbols, find references to a symbol,
  and read a symbol's body without reading the whole file.
- Prefer these over reading whole files for "where is this used" and "what
  does this call" questions.

Only use its read-only tools. Never use tools that edit, rename or run code.
