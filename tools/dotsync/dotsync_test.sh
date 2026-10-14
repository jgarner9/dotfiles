#!/usr/bin/env bash
# Tests for dot_local/bin/executable_dotsync. Real git, fake chezmoi.
# Usage: tools/dotsync/dotsync_test.sh

set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
DOTSYNC="$repo/dot_local/bin/executable_dotsync"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

pass=0
fail=0

export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com

setup() {
	rm -rf "${work:?}"/*
	mkdir -p "$work/bin" "$work/state"
	git init -q --bare -b main "$work/origin.git"
	git clone -q "$work/origin.git" "$work/src" 2>/dev/null
	git -C "$work/src" commit -q --allow-empty -m init
	git -C "$work/src" push -q origin HEAD:main 2>/dev/null
	git -C "$work/src" branch -q --set-upstream-to=origin/main
	git clone -q "$work/origin.git" "$work/upstream"
	: >"$work/status"
	: >"$work/calls"
	cat >"$work/bin/chezmoi" <<FAKE
#!/usr/bin/env bash
echo "\$*" >>"$work/calls"
case "\$1" in
source-path) echo "$work/src" ;;
status) cat "$work/status" ;;
apply) [[ -f "$work/apply-fails" ]] && { echo "boom" >&2; exit 1; }; exit 0 ;;
esac
FAKE
	chmod +x "$work/bin/chezmoi"
}

upstream_commit() { # path
	mkdir -p "$work/upstream/$(dirname "$1")"
	echo "$RANDOM" >>"$work/upstream/$1"
	git -C "$work/upstream" add -A
	git -C "$work/upstream" commit -q -m "change $1"
	git -C "$work/upstream" push -q origin HEAD:main 2>/dev/null
}

run() {
	PATH="$work/bin:$PATH" XDG_STATE_HOME="$work/state" bash "$DOTSYNC" --json "$@" || true
}

check() { # name, output, jq-expression that must be true
	if jq -e "$3" >/dev/null 2>&1 <<<"$2"; then
		pass=$((pass + 1))
		echo "ok   $1"
	else
		fail=$((fail + 1))
		echo "FAIL $1"
		echo "     got: $2"
		echo "     want: $3"
	fi
}

setup
check "up to date" "$(run)" '.status == "up_to_date" and .changed == []'

setup
upstream_commit dot_zshrc
out=$(run)
check "synced" "$out" '.status == "synced" and .changed == ["dot_zshrc"] and .nvim_changed == false'
check "apply ran" "$(grep -c '^apply' "$work/calls" | jq -R '{n: tonumber}')" '.n == 1'

setup
upstream_commit dot_config/nvim/init.lua
check "nvim change flagged" "$(run)" '.status == "synced" and .nvim_changed == true and (.message | test("restart Neovim"))'

setup
run >/dev/null
upstream_commit dot_zshrc
check "throttled" "$(run)" '.status == "skipped_throttle"'
check "force bypasses throttle" "$(run --force)" '.status == "synced"'

setup
upstream_commit dot_zshrc
printf 'MM .zshrc\n R script\n' >"$work/status"
out=$(run)
check "drift skips apply" "$out" '.status == "skipped_drift" and .drift == [".zshrc"]'
check "no apply on drift" "$(grep -c '^apply' "$work/calls" | jq -R '{n: tonumber}')" '.n == 0'

setup
upstream_commit dot_zshrc
printf ' M .zshrc\n' >"$work/status"
check "pending changes are not drift" "$(run)" '.status == "synced"'

setup
mkdir -p "$work/state/dotsync/lock"
check "locked" "$(run --force)" '.status == "skipped_locked"'
# -t works with both GNU and BSD touch; -d's formats don't
stale=$(date -d '20 minutes ago' +%Y%m%d%H%M 2>/dev/null || date -v-20M +%Y%m%d%H%M)
touch -t "$stale" "$work/state/dotsync/lock"
check "stale lock cleared" "$(run --force)" '.status == "up_to_date"'
check "lock released" "$(test -d "$work/state/dotsync/lock" && echo '{"held":true}' || echo '{"held":false}')" '.held == false'

setup
upstream_commit dot_zshrc
echo local >"$work/src/dot_zshrc"
git -C "$work/src" add -A
git -C "$work/src" commit -q -m "local change"
check "diverged pull is an error" "$(run)" '.status == "error" and (.message | test("diverged"))'

setup
upstream_commit dot_zshrc
touch "$work/apply-fails"
check "apply failure is an error" "$(run)" '.status == "error" and (.message | test("apply failed"))'

setup
check "log written" "$(run >/dev/null; wc -l <"$work/state/dotsync/dotsync.log" | jq -R '{n: tonumber}')" '.n == 1'

echo
echo "$pass passed, $fail failed"
((fail == 0))
