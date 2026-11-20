#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROMPT_FILE="$SCRIPT_DIR/sync-claude-ai-memory-prompt.md"
LOG_DIR="$HOME/.claude/logs"
LOG_FILE="$LOG_DIR/memory-sync.log"
CLAUDE_BIN="$(command -v claude)"

mkdir -p "$LOG_DIR"

{
  echo "=== $(date -Is) sync start ==="
  "$CLAUDE_BIN" -p "$(cat "$PROMPT_FILE")" \
    --permission-mode acceptEdits \
    --permission-prompts none \
    --allowedTools "Read" "Write" "Edit" "mcp__claude_ai_Basic_Memory__list_memory_projects" "mcp__claude_ai_Basic_Memory__recent_activity" "mcp__claude_ai_Basic_Memory__read_note" "mcp__claude_ai_Basic_Memory__list_directory" "mcp__claude_ai_Basic_Memory__search" \
    --no-session-persistence \
    --output-format text
  echo "=== $(date -Is) sync end (exit $?) ==="
} >> "$LOG_FILE" 2>&1
