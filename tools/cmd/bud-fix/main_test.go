package main

import (
	"bytes"
	"context"
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// The tests run real git against a local bare "origin", with fake claude and
// gh scripts that record what they were asked and answer from $FAKE_DIR.

const fakeClaude = `#!/usr/bin/env bash
if [[ ${1:-} == --help ]]; then
	echo "  --restricted   Restricted mode"
	exit 0
fi
printf '%s\n' "$@" >"$FAKE_DIR/claude-args"
cat >"$FAKE_DIR/claude-prompt"
pwd >"$FAKE_DIR/claude-cwd"
if [[ -n ${FAKE_EDIT:-} ]]; then
	mkdir -p "$(dirname "$FAKE_EDIT")"
	echo "-- fixed" >>"$FAKE_EDIT"
fi
echo '{"type":"system","subtype":"init","session_id":"sess-1"}'
echo '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"'"$PWD"'/dot_config/nvim/lua/bud/x.lua"}}]}}'
if [[ -n ${FAKE_SLEEP:-} ]]; then
	exec sleep "$FAKE_SLEEP"
fi
if [[ -f $FAKE_DIR/result.json ]]; then
	cat "$FAKE_DIR/result.json"
fi
exit "${FAKE_CLAUDE_EXIT:-0}"
`

const fakeGH = `#!/usr/bin/env bash
echo "$*" >>"$FAKE_DIR/gh-calls"
body=""
prev=""
for a in "$@"; do
	if [[ $prev == --body-file ]]; then
		body=$a
	fi
	prev=$a
done
case "$1 $2" in
"issue create")
	if [[ -n ${FAKE_GH_NO_LABEL:-} && ! -e $FAKE_DIR/label-made ]]; then
		echo "could not add label: 'bud' not found" >&2
		exit 1
	fi
	cp "$body" "$FAKE_DIR/issue-body.md"
	echo "https://github.com/o/r/issues/12"
	;;
"label create") touch "$FAKE_DIR/label-made" ;;
"issue view") cat "$FAKE_DIR/issue.json" ;;
"issue comment") cp "$body" "$FAKE_DIR/comment.md" ;;
"pr create")
	cp "$body" "$FAKE_DIR/pr-body.md"
	echo "Creating pull request..." >&2
	echo "https://github.com/o/r/pull/14"
	;;
*)
	echo "fake gh: unexpected $*" >&2
	exit 1
	;;
esac
`

const fakeTests = `#!/usr/bin/env bash
echo "== bud"
echo "ok   test_chat: footer"
exit "${FAKE_TEST_EXIT:-0}"
`

type env struct {
	cfg    Config
	src    string
	remote string
	fake   string
}

func git(t *testing.T, dir string, args ...string) string {
	t.Helper()
	cmd := exec.Command("git", append([]string{"-C", dir}, args...)...)
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("git %v: %v\n%s", args, err, out)
	}
	return strings.TrimSpace(string(out))
}

func write(t *testing.T, path, text string, mode os.FileMode) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(text), mode); err != nil {
		t.Fatal(err)
	}
}

func read(t *testing.T, path string) string {
	t.Helper()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	return string(data)
}

func setup(t *testing.T) *env {
	t.Helper()
	t.Setenv("GIT_CONFIG_GLOBAL", "/dev/null")
	t.Setenv("GIT_CONFIG_NOSYSTEM", "1")
	// physical paths, so they compare equal to what pwd prints on macOS too
	root, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	seed := filepath.Join(root, "seed")
	write(t, filepath.Join(seed, "dot_config/nvim/lua/bud/x.lua"), "return 1\n", 0o644)
	write(t, filepath.Join(seed, "tools/test.sh"), fakeTests, 0o755)
	write(t, filepath.Join(seed, "dot_zshrc"), "export A=1\n", 0o644)
	git(t, root, "init", "-q", "-b", "main", seed)
	git(t, seed, "-c", "user.name=t", "-c", "user.email=t@t", "add", ".")
	git(t, seed, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "init")
	remote := filepath.Join(root, "remote.git")
	git(t, root, "clone", "-q", "--bare", seed, remote)
	src := filepath.Join(root, "src")
	git(t, root, "clone", "-q", remote, src)
	git(t, src, "config", "user.name", "Tester")
	git(t, src, "config", "user.email", "tester@example.com")

	fake := filepath.Join(root, "fake")
	write(t, filepath.Join(fake, "claude"), fakeClaude, 0o755)
	write(t, filepath.Join(fake, "gh"), fakeGH, 0o755)
	t.Setenv("FAKE_DIR", fake)
	t.Setenv("FAKE_EDIT", "dot_config/nvim/lua/bud/x.lua")
	t.Setenv("FAKE_TEST_EXIT", "0")

	e := &env{src: src, remote: remote, fake: fake}
	e.cfg = Config{
		Repo:        src,
		StateDir:    filepath.Join(root, "state"),
		CacheDir:    filepath.Join(root, "cache"),
		Model:       "sonnet",
		Edit:        defaultEdit,
		Test:        "bash tools/test.sh",
		Claude:      filepath.Join(fake, "claude"),
		GH:          filepath.Join(fake, "gh"),
		Timeout:     time.Minute,
		TestTimeout: time.Minute,
	}
	return e
}

func (e *env) result(t *testing.T, text string, isErr bool) {
	t.Helper()
	data, _ := json.Marshal(map[string]any{
		"type": "result", "subtype": "success", "is_error": isErr, "result": text,
		"session_id": "sess-1", "num_turns": 3, "total_cost_usd": 0.12,
	})
	write(t, filepath.Join(e.fake, "result.json"), string(data)+"\n", 0o644)
}

func (e *env) report(t *testing.T, body string) Job {
	t.Helper()
	dir := t.TempDir()
	write(t, filepath.Join(dir, "body.md"), body, 0o644)
	write(t, filepath.Join(dir, "context.md"), "## Recent requests\nRequest: secret prompt text\n", 0o644)
	return Job{Kind: "bug", Title: "Chat footer shows nil", BodyFile: filepath.Join(dir, "body.md"), ContextFile: filepath.Join(dir, "context.md")}
}

func (e *env) ghCalls(t *testing.T) string {
	data, _ := os.ReadFile(filepath.Join(e.fake, "gh-calls"))
	return string(data)
}

func contains(t *testing.T, s, sub, what string) {
	t.Helper()
	if !strings.Contains(s, sub) {
		t.Errorf("%s: expected %q in\n%s", what, sub, s)
	}
}

func lacks(t *testing.T, s, sub, what string) {
	t.Helper()
	if strings.Contains(s, sub) {
		t.Errorf("%s: did not expect %q in\n%s", what, sub, s)
	}
}

const goodFinal = "Found it: the footer read a nil status.\n\nTitle: Fix the chat footer after a cancel\n\nBefore: the footer said nil.\n\nAfter: it says Cancelled.\n\nHow: the footer falls back to the error text.\n"

func TestReportToPullRequest(t *testing.T) {
	e := setup(t)
	e.result(t, goodFinal, false)
	body := "The chat footer shows nil after I cancel.\n\n### Environment\n- Neovim 0.11.4\n"
	st, err := run(context.Background(), e.cfg, e.report(t, body))
	if err != nil {
		t.Fatalf("run: %v\n%s", err, read(t, st.Log))
	}
	if st.Phase != PhaseDone || st.Issue != 12 || st.PR != 14 || st.Draft || st.Tests != "passed" {
		t.Fatalf("state: %+v", st)
	}
	if st.PRURL != "https://github.com/o/r/pull/14" || st.IssueURL != "https://github.com/o/r/issues/12" {
		t.Errorf("urls: %s %s", st.PRURL, st.IssueURL)
	}

	// the issue has the report and none of the local context
	issue := read(t, filepath.Join(e.fake, "issue-body.md"))
	if issue != body {
		t.Errorf("issue body: %q", issue)
	}
	calls := e.ghCalls(t)
	contains(t, calls, "issue create --title Chat footer shows nil", "gh")
	contains(t, calls, "--label bud --label bug", "gh")
	contains(t, calls, "pr create --base main --head bud/12-chat-footer-shows-nil --title Fix the chat footer after a cancel", "gh")
	lacks(t, calls, "--draft", "gh")

	// Claude got the issue, the local context and the bug workflow, with
	// edits scoped and no way to push
	prompt := read(t, filepath.Join(e.fake, "claude-prompt"))
	contains(t, prompt, "issue #12", "prompt")
	contains(t, prompt, "secret prompt text", "prompt")
	contains(t, prompt, "Reproduce it first", "prompt")
	args := read(t, filepath.Join(e.fake, "claude-args"))
	for _, want := range []string{"--restricted", "dontAsk", "--strict-mcp-config", "Edit(./dot_config/nvim/lua/bud/**)", "Bash(bash tools/test.sh*)"} {
		contains(t, args, want, "claude args")
	}
	for _, bad := range []string{"git push", "git commit", "Bash(gh"} {
		lacks(t, args, bad, "claude args")
	}
	cwd := strings.TrimSpace(read(t, filepath.Join(e.fake, "claude-cwd")))
	if !strings.HasPrefix(cwd, filepath.Join(e.cfg.CacheDir, "worktrees")) {
		t.Errorf("claude ran in %s", cwd)
	}

	// the branch is on origin with the change; the worktree and local branch are gone
	msg := git(t, e.remote, "log", "-1", "--format=%B", "bud/12-chat-footer-shows-nil")
	contains(t, msg, "Fix the chat footer after a cancel", "commit")
	contains(t, msg, "Refs #12", "commit")
	file := git(t, e.remote, "show", "bud/12-chat-footer-shows-nil:dot_config/nvim/lua/bud/x.lua")
	contains(t, file, "-- fixed", "pushed file")
	if _, err := os.Stat(cwd); !os.IsNotExist(err) {
		t.Errorf("worktree still there: %v", err)
	}
	if out, _ := exec.Command("git", "-C", e.src, "branch", "--list", "bud/*").Output(); len(bytes.TrimSpace(out)) > 0 {
		t.Errorf("local branch kept: %s", out)
	}

	pr := read(t, filepath.Join(e.fake, "pr-body.md"))
	contains(t, pr, "Before: the footer said nil.", "pr body")
	contains(t, pr, "Fixes #12", "pr body")
	contains(t, pr, "passed", "pr body")
	lacks(t, pr, "Title:", "pr body")

	runs, _ := loadRuns(e.cfg.StateDir)
	if len(runs) != 1 || runs[0].Phase != PhaseDone || runs[0].PR != 14 || runs[0].SessionID != "sess-1" {
		t.Errorf("state file: %+v", runs)
	}
}

func TestFailingTestsOpenADraft(t *testing.T) {
	e := setup(t)
	e.result(t, goodFinal, false)
	t.Setenv("FAKE_TEST_EXIT", "1")
	st, err := run(context.Background(), e.cfg, e.report(t, "body"))
	if err != nil {
		t.Fatal(err)
	}
	if !st.Draft || st.Tests != "failed" || st.PR != 14 {
		t.Fatalf("state: %+v", st)
	}
	contains(t, e.ghCalls(t), "--draft", "gh")
	pr := read(t, filepath.Join(e.fake, "pr-body.md"))
	contains(t, pr, "failed, so this is a draft", "pr body")
	contains(t, pr, "ok   test_chat: footer", "pr body")
}

func TestNoChangesCommentsOnTheIssue(t *testing.T) {
	e := setup(t)
	e.result(t, "This already works: the footer is set in finish().", false)
	t.Setenv("FAKE_EDIT", "")
	st, err := run(context.Background(), e.cfg, e.report(t, "body"))
	if err != nil {
		t.Fatal(err)
	}
	if st.Phase != PhaseNoChange || st.PR != 0 || st.Worktree != "" {
		t.Fatalf("state: %+v", st)
	}
	contains(t, read(t, filepath.Join(e.fake, "comment.md")), "This already works", "comment")
	lacks(t, e.ghCalls(t), "pr create", "gh")
}

func TestChangesOutsideTheAllowedPathsAreNotPushed(t *testing.T) {
	e := setup(t)
	e.result(t, goodFinal, false)
	t.Setenv("FAKE_EDIT", "dot_zshrc")
	st, err := run(context.Background(), e.cfg, e.report(t, "body"))
	if err == nil || st.Phase != PhaseFailed {
		t.Fatalf("expected a failure, got %+v", st)
	}
	contains(t, st.Error, "dot_zshrc", "error")
	if out := git(t, e.remote, "branch", "--list", "bud/*"); out != "" {
		t.Errorf("pushed: %s", out)
	}
	if _, err := os.Stat(st.Worktree); err != nil {
		t.Errorf("worktree should be kept for a look: %v", err)
	}
	lacks(t, e.ghCalls(t), "pr create", "gh")
}

func TestFixAnExistingIssue(t *testing.T) {
	e := setup(t)
	e.result(t, goodFinal, false)
	write(t, filepath.Join(e.fake, "issue.json"), `{"number":7,"title":"Add a thing","body":"please","url":"https://github.com/o/r/issues/7","labels":[{"name":"enhancement"}]}`, 0o644)
	st, err := run(context.Background(), e.cfg, Job{Issue: 7})
	if err != nil {
		t.Fatal(err)
	}
	if st.Kind != "feature" || st.Issue != 7 || st.Title != "Add a thing" || st.Branch != "bud/7-add-a-thing" {
		t.Fatalf("state: %+v", st)
	}
	calls := e.ghCalls(t)
	lacks(t, calls, "issue create", "gh")
	contains(t, calls, "issue view 7", "gh")
	contains(t, read(t, filepath.Join(e.fake, "claude-prompt")), "Build it in the style", "prompt")
}

func TestMissingLabelsAreCreated(t *testing.T) {
	e := setup(t)
	e.result(t, goodFinal, false)
	t.Setenv("FAKE_GH_NO_LABEL", "1")
	st, err := run(context.Background(), e.cfg, e.report(t, "body"))
	if err != nil {
		t.Fatal(err)
	}
	if st.Issue != 12 {
		t.Fatalf("state: %+v", st)
	}
	contains(t, e.ghCalls(t), "label create bud", "gh")
}

func TestClaudeErrorWithChangesIsADraft(t *testing.T) {
	e := setup(t)
	e.result(t, "Reached the turn limit.", true)
	st, err := run(context.Background(), e.cfg, e.report(t, "body"))
	if err != nil {
		t.Fatal(err)
	}
	if !st.Draft || st.Tests != "passed" {
		t.Fatalf("state: %+v", st)
	}
	contains(t, read(t, filepath.Join(e.fake, "pr-body.md")), "Claude stopped early", "pr body")
	// no Title: line, so the issue title stands in
	contains(t, e.ghCalls(t), "--title Chat footer shows nil --body-file", "gh")
}

func TestClaudeCrashWithoutChangesFails(t *testing.T) {
	e := setup(t)
	t.Setenv("FAKE_EDIT", "")
	t.Setenv("FAKE_CLAUDE_EXIT", "1")
	st, err := run(context.Background(), e.cfg, e.report(t, "body"))
	if err == nil || st.Phase != PhaseFailed {
		t.Fatalf("expected a failure, got %+v", st)
	}
	contains(t, st.Error, "no result from claude", "error")
}

func TestAQueuedRunWaitsForTheLock(t *testing.T) {
	e := setup(t)
	e.result(t, goodFinal, false)
	held, ok, err := tryLock(filepath.Join(e.cfg.StateDir, "fix.lock"))
	if err != nil || !ok {
		t.Fatalf("lock: %v %v", ok, err)
	}
	done := make(chan *State, 1)
	go func() {
		st, _ := run(context.Background(), e.cfg, e.report(t, "body"))
		done <- st
	}()
	deadline := time.Now().Add(10 * time.Second)
	for {
		runs, _ := loadRuns(e.cfg.StateDir)
		if len(runs) == 1 && runs[0].Phase == PhaseQueued {
			break
		}
		if time.Now().After(deadline) {
			t.Fatalf("never queued: %+v", runs)
		}
		time.Sleep(20 * time.Millisecond)
	}
	held.release()
	select {
	case st := <-done:
		if st.Phase != PhaseDone {
			t.Fatalf("state: %+v", st)
		}
	case <-time.After(30 * time.Second):
		t.Fatal("run never finished")
	}
}

func TestCancelStopsClaude(t *testing.T) {
	e := setup(t)
	t.Setenv("FAKE_SLEEP", "30")
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan *State, 1)
	go func() {
		st, _ := run(ctx, e.cfg, e.report(t, "body"))
		done <- st
	}()
	deadline := time.Now().Add(10 * time.Second)
	for {
		runs, _ := loadRuns(e.cfg.StateDir)
		if len(runs) == 1 && runs[0].Phase == PhaseFixing && runs[0].Detail == "editing dot_config/nvim/lua/bud/x.lua" {
			break
		}
		if time.Now().After(deadline) {
			t.Fatalf("never started fixing: %+v", runs)
		}
		time.Sleep(20 * time.Millisecond)
	}
	cancel()
	select {
	case st := <-done:
		if st.Phase != PhaseFailed || st.Error != "cancelled" {
			t.Fatalf("state: %+v", st)
		}
	case <-time.After(15 * time.Second):
		t.Fatal("cancel didn't stop the run")
	}
}

func TestParseFinal(t *testing.T) {
	cases := []struct{ in, title, body string }{
		{goodFinal, "Fix the chat footer after a cancel", "Before: the footer said nil.\n\nAfter: it says Cancelled.\n\nHow: the footer falls back to the error text."},
		{"**Title:** `Add a thing`\n\nBefore: none", "Add a thing", "Before: none"},
		{"**Title**: Add it\nAfter: yes", "Add it", "After: yes"},
		{"No title here.", "fallback", "No title here."},
		{"Title: first\n\nTitle: second\nbody", "second", "body"},
	}
	for _, c := range cases {
		title, body := parseFinal(c.in, "fallback")
		if title != c.title || body != c.body {
			t.Errorf("parseFinal(%q) = %q, %q; want %q, %q", c.in, title, body, c.title, c.body)
		}
	}
}

func TestHelpers(t *testing.T) {
	if s := slug("The chat footer shows `nil` after I cancel a request"); s != "the-chat-footer-shows-nil" {
		t.Errorf("slug: %s", s)
	}
	if s := slug("!!!"); s != "report" {
		t.Errorf("slug: %s", s)
	}
	got := outside([]string{
		"dot_config/nvim/lua/bud/ui/chat.lua",
		"dot_config/nvim/lua/plugins/bud.lua",
		"dot_config/nvim/lua/plugins/other.lua",
		"tools/bud/tests/test_x.lua",
		"dot_zshrc",
		"dot_config/nvim/lua/budget.lua",
	}, defaultEdit)
	if strings.Join(got, ",") != "dot_config/nvim/lua/plugins/other.lua,dot_zshrc,dot_config/nvim/lua/budget.lua" {
		t.Errorf("outside: %v", got)
	}
	if !globRe("a/**/b.lua").MatchString("a/b.lua") || !globRe("a/**/b.lua").MatchString("a/x/y/b.lua") || globRe("a/*.lua").MatchString("a/x/b.lua") {
		t.Error("globRe")
	}
	for in, want := range map[string]string{
		"git@github.com:jgarner9/dotfiles.git":      "jgarner9/dotfiles",
		"https://github.com/jgarner9/dotfiles":      "jgarner9/dotfiles",
		"https://github.com/jgarner9/dotfiles.git/": "jgarner9/dotfiles",
		"/tmp/remote.git":                           "",
	} {
		if got := githubRepo(in); got != want {
			t.Errorf("githubRepo(%q) = %q", in, got)
		}
	}
	if url, n := parseURL("Creating...\nhttps://github.com/o/r/pull/14\n", "pull"); n != 14 || url != "https://github.com/o/r/pull/14" {
		t.Errorf("parseURL: %s %d", url, n)
	}
	rules := allowedTools([]string{"tools/**"}, []string{"Bash(rg *)", "Bash(repomap *)"})
	if strings.Count(strings.Join(rules, ","), "Bash(rg *)") != 1 || rules[len(rules)-1] != "Bash(repomap *)" || rules[3] != "Edit(./tools/**)" {
		t.Errorf("allowedTools: %v", rules)
	}
	if d := describeTool("Bash", json.RawMessage(`{"command":"bash tools/bud/run.sh chat"}`), "/w"); d != "running tests" {
		t.Errorf("describeTool: %s", d)
	}
}

func TestCLI(t *testing.T) {
	var out, errOut bytes.Buffer
	if code := cli([]string{"report", "-kind", "nope"}, &out, &errOut); code != 2 {
		t.Errorf("bad kind: %d", code)
	}
	if code := cli([]string{"issue", "abc"}, &out, &errOut); code != 2 {
		t.Errorf("bad number: %d", code)
	}
	if code := cli([]string{"frobnicate"}, &out, &errOut); code != 2 {
		t.Errorf("unknown command: %d", code)
	}
	out.Reset()
	if code := cli([]string{"status", "-state", t.TempDir()}, &out, &errOut); code != 0 || !strings.Contains(out.String(), "no runs yet") {
		t.Errorf("status: %d %q", code, out.String())
	}
	out.Reset()
	if code := cli([]string{"--help"}, &out, &errOut); code != 0 || !strings.Contains(out.String(), "-no-pr") {
		t.Errorf("help: %d", code)
	}
}

func TestStatusMarksStaleRuns(t *testing.T) {
	dir := t.TempDir()
	write(t, filepath.Join(dir, "20260101-000000-aaaa.json"), `{"id":"20260101-000000-aaaa","pid":999999999,"phase":"fixing","title":"Old","issue":3}`, 0o644)
	var out bytes.Buffer
	if code := cli([]string{"status", "-state", dir}, &out, &out); code != 0 {
		t.Fatal(out.String())
	}
	contains(t, out.String(), "failed", "status")
	contains(t, out.String(), "stopped before it finished", "status")
}
