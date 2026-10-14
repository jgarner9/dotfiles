#!/usr/bin/env bash
# Runs every test for the personal tools and for Bud. A suite whose toolchain
# isn't installed is skipped with a note, so this works on a fresh machine.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/.." && pwd)
status=0

run() {
	local name=$1
	shift
	echo "== $name"
	if "$@"; then
		echo "-- $name: ok"
	else
		echo "-- $name: FAILED"
		status=1
	fi
}

skip() {
	echo "== $1: skipped ($2)"
}

if command -v go >/dev/null 2>&1; then
	run "go tools" bash -c "cd '$here' && go vet ./... && go test ./..."
else
	skip "go tools" "go not installed"
fi

if command -v jq >/dev/null 2>&1; then
	run "dotsync" bash "$here/dotsync/dotsync_test.sh"
else
	skip "dotsync" "jq not installed"
fi

if command -v shellcheck >/dev/null 2>&1; then
	run "shellcheck" shellcheck \
		"$repo/dot_local/bin/executable_dotsync" \
		"$here/test.sh" \
		"$here/dotsync/dotsync_test.sh" \
		"$here/bud/run.sh" \
		"$here/bud/fake-claude"
else
	skip "shellcheck" "shellcheck not installed"
fi

# Inside Neovim (and anything it starts, like bud-fix) $NVIM is the server
# socket, not a binary: only an executable file counts.
nvim=nvim
if [[ -n ${NVIM:-} && -f $NVIM && -x $NVIM ]]; then
	nvim=$NVIM
fi
if command -v "$nvim" >/dev/null 2>&1; then
	run "bud" env NVIM="$nvim" bash "$here/bud/run.sh"
else
	skip "bud" "nvim not installed"
fi

exit "$status"
