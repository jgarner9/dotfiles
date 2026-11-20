You are running a non-interactive, unattended maintenance task. There is no user present to ask questions — make reasonable decisions yourself and just do the work, then stop.

## Goal

Refresh Claude Code's global auto-memory cache (configured via `autoMemoryDirectory` in `~/.claude/settings.json`, shared across every project — check your own environment info for the actual path, don't assume one) from Jason's claude.ai memory mirror, which lives in his self-hosted Basic Memory MCP server (project "main") under the `reference/claude-ai-memory/` folder. That folder is itself a read-only daily mirror of claude.ai's built-in memory (profile, preferences, and notes under `areas/`, `topics/`, `people/`).

## Steps

1. Read `reference/claude-ai-memory/index` in Basic Memory (project "main") to see the current list of mirrored notes.
2. Read `reference/claude-ai-memory/profile` and `reference/claude-ai-memory/preferences` in full.
3. Read every note currently listed under `reference/claude-ai-memory/areas/`, `reference/claude-ai-memory/topics/`, and `reference/claude-ai-memory/people/`.
4. Read the current local memory files in your global auto-memory directory (there's an `MEMORY.md` index plus one file per topic, named like `user_profile.md`, `user_interests.md`, `feedback_memory-architecture.md`, `project_<name>.md`, `reference_basic-memory.md`).
5. Compare the mirror's current content against the local files. Update local files whose underlying facts have changed. Add a new local file (following the existing naming and frontmatter pattern below) for any genuinely new area/topic/person in the mirror that isn't represented locally yet. If a mirrored note has been removed from the index, don't delete the local file outright — instead add a line noting it no longer appears in the mirror as of today's date, so history isn't lost.
6. Update `MEMORY.md` to match (one line per file, under ~150 chars, format `- [Title](file.md) — one-line hook`).
7. Leave files whose underlying facts are unchanged untouched — don't rewrite content that didn't change just to bump a timestamp.

## Memory file conventions to preserve

Each file (except `MEMORY.md`) has frontmatter:
```
---
name: kebab-case-slug
description: one-line summary
metadata:
  type: user | feedback | project | reference
---
```
Type guide: `user` = identity/interests/context about Jason; `feedback` = how Claude should work/route information; `project` = ongoing initiatives with a **Why:** and **How to apply:** line; `reference` = pointers to external systems. Link related files with `[[name]]` using the file's `name:` slug.

## Boundaries

- Never write to anything under `reference/claude-ai-memory/` in Basic Memory — that folder is a read-only mirror owned by a separate daily claude.ai sync task.
- Don't touch any other local memory files unrelated to this mirror (if Jason has added his own memories about other topics, leave them alone).
- Don't ask questions, don't wait for confirmation, don't open a plan — just make the edits and exit.
