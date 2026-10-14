#!/usr/bin/env bash
# Runs Bud's headless tests against a fake Claude CLI. Needs Neovim 0.11+.
#   tools/bud/run.sh            all tests
#   tools/bud/run.sh chat       only test_chat.lua
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
# Inside Neovim $NVIM is the server socket; only an executable file counts.
if [[ -z ${NVIM:-} || ! -f $NVIM || ! -x $NVIM ]]; then
	NVIM=nvim
fi
BUD_TEST_NVIM=$(command -v "$NVIM" || true)
export BUD_TEST_NVIM

if [[ -z $BUD_TEST_NVIM ]]; then
	echo "bud tests: $NVIM not found (set NVIM=/path/to/nvim)" >&2
	exit 1
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin"

export XDG_CONFIG_HOME="$work/config" XDG_DATA_HOME="$work/data"
export XDG_STATE_HOME="$work/state" XDG_CACHE_HOME="$work/cache"
export BUD_REPO="$repo" BUD_TEST_DIR="$here" BUD_TEST_WORK="$work"
export FAKE_CLAUDE_CONTROL="$work/control.json" FAKE_CLAUDE_LOG="$work/claude.log"
export PATH="$work/bin:$PATH"

"$NVIM" --clean -l "$here/runner.lua" "$@"
