package main

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"syscall"
	"time"
)

type Config struct {
	Repo        string   // the dotfiles repo (chezmoi source)
	StateDir    string   // run records: <id>.json and <id>.log
	CacheDir    string   // worktrees live under <cache>/worktrees
	Model       string   // Claude model for the fix
	SystemFile  string   // appended to Claude's system prompt (Bud's instructions)
	Allow       []string // extra --allowedTools rules
	Edit        []string // globs Claude may edit, relative to the repo root
	Test        string   // run with bash -c in the worktree
	Base        string   // base ref; default origin/HEAD
	Claude      string
	GH          string
	Timeout     time.Duration // for Claude
	TestTimeout time.Duration
	NoPR        bool // commit on the branch and stop: no push, no PR
}

// Job is one report: file a new issue from Title and BodyFile, or fix the
// existing Issue.
type Job struct {
	Kind        string
	Title       string
	BodyFile    string
	ContextFile string
	Issue       int
}

type runner struct {
	cfg  Config
	st   *State
	ctx  context.Context
	repo string // owner/name for gh -R, when origin is on GitHub
}

func labelFor(kind string) string {
	if kind == "bug" {
		return "bug"
	}
	return "enhancement"
}

// run takes a job from report to pull request. It always returns the final
// state; err is non-nil when the run failed.
func run(ctx context.Context, cfg Config, job Job) (*State, error) {
	st, err := newState(cfg.StateDir, job.Kind, job.Title)
	if err != nil {
		return nil, err
	}
	r := &runner{cfg: cfg, st: st, ctx: ctx}
	err = r.do(job)
	if err != nil {
		if ctx.Err() != nil {
			err = errors.New("cancelled")
		}
		st.Set(func(s *State) {
			s.Phase = PhaseFailed
			s.Detail = ""
			s.Error = err.Error()
		})
		st.Logf("failed: %v", err)
	}
	return st, err
}

func (r *runner) phase(p, detail string) {
	r.st.Set(func(s *State) {
		s.Phase = p
		s.Detail = detail
	})
	if detail != "" {
		r.st.Logf("%s: %s", p, detail)
	} else {
		r.st.Logf("%s", p)
	}
}

func (r *runner) do(job Job) error {
	cfg := r.cfg
	r.st.Logf("bud-fix in %s", cfg.Repo)
	r.repo = githubRepo(r.out(cfg.Repo, "git", "remote", "get-url", "origin"))

	// 1. the issue
	var is Issue
	if job.Issue > 0 {
		r.phase(PhaseFiling, fmt.Sprintf("reading #%d", job.Issue))
		got, err := r.viewIssue(job.Issue)
		if err != nil {
			return err
		}
		is = got
	} else {
		r.phase(PhaseFiling, "filing the issue")
		body, err := os.ReadFile(job.BodyFile)
		if err != nil {
			return fmt.Errorf("read the report: %w", err)
		}
		is = Issue{Kind: job.Kind, Title: job.Title, Body: string(body)}
		if err := r.fileIssue(&is); err != nil {
			return err
		}
	}
	r.st.Set(func(s *State) {
		s.Issue, s.IssueURL, s.Kind, s.Title = is.Number, is.URL, is.Kind, is.Title
	})
	r.st.Logf("issue #%d %s", is.Number, is.URL)
	var local string
	if job.ContextFile != "" {
		if data, err := os.ReadFile(job.ContextFile); err == nil {
			local = string(data)
		}
	}

	// 2. one fix at a time
	lockPath := filepath.Join(cfg.StateDir, "fix.lock")
	l, ok, err := tryLock(lockPath)
	if err != nil {
		return err
	}
	if !ok {
		r.phase(PhaseQueued, "waiting for another fix to finish")
		l, err = r.waitLock(lockPath)
		if err != nil {
			return err
		}
	}
	defer l.release()

	// 3. a worktree on a fresh branch from the default branch
	r.phase(PhasePreparing, "fetching origin")
	if _, err := r.git(cfg.Repo, "fetch", "--quiet", "origin"); err != nil {
		return err
	}
	_, _ = r.git(cfg.Repo, "worktree", "prune")
	base, err := r.base()
	if err != nil {
		return err
	}
	branch, err := r.branch(is)
	if err != nil {
		return err
	}
	wt := filepath.Join(cfg.CacheDir, "worktrees", r.st.ID)
	if err := os.MkdirAll(filepath.Dir(wt), 0o755); err != nil {
		return err
	}
	if _, err := r.git(cfg.Repo, "worktree", "add", "--quiet", "--no-track", "-b", branch, wt, base); err != nil {
		return err
	}
	r.st.Set(func(s *State) { s.Branch, s.Worktree = branch, wt })
	r.st.Logf("worktree %s on %s from %s", wt, branch, base)

	// 4. Claude makes the change
	r.phase(PhaseFixing, "starting Claude")
	final, claudeErr := r.claude(wt, taskPrompt(is, local, branch, cfg.Edit))
	if r.ctx.Err() != nil {
		return r.ctx.Err()
	}
	title, desc := parseFinal(final, is.Title)
	r.st.Set(func(s *State) { s.Summary = final })
	if claudeErr != nil {
		r.st.Logf("claude: %v", claudeErr)
	}

	changed, err := r.changes(wt)
	if err != nil {
		return err
	}
	if len(changed) == 0 {
		if claudeErr != nil {
			return fmt.Errorf("claude: %w", claudeErr)
		}
		r.comment(is.Number, "bud-fix looked into this and made no changes. Claude's notes:\n\n"+strings.TrimSpace(final))
		r.cleanup(wt, branch)
		r.st.Set(func(s *State) {
			s.Phase, s.Detail, s.Worktree = PhaseNoChange, "", ""
		})
		r.st.Logf("no changes")
		return nil
	}
	if bad := outside(changed, cfg.Edit); len(bad) > 0 {
		return fmt.Errorf("changes outside the allowed paths, nothing pushed: %s (worktree kept at %s)", strings.Join(bad, ", "), wt)
	}

	// 5. bud-fix runs the tests itself
	r.phase(PhaseTesting, cfg.Test)
	testOut, testErr := r.sh(wt, cfg.Test, cfg.TestTimeout)
	r.st.Logf("%s", testOut)
	if r.ctx.Err() != nil {
		return r.ctx.Err()
	}
	passed := testErr == nil
	r.st.Set(func(s *State) {
		s.Tests = map[bool]string{true: "passed", false: "failed"}[passed]
	})
	r.st.Logf("tests %s", r.st.Tests)

	changed, err = r.changes(wt)
	if err != nil {
		return err
	}
	if bad := outside(changed, cfg.Edit); len(bad) > 0 {
		return fmt.Errorf("the tests left files outside the allowed paths, nothing pushed: %s (worktree kept at %s)", strings.Join(bad, ", "), wt)
	}

	// 6. commit, push, pull request
	r.phase(PhasePushing, "committing")
	if _, err := r.git(wt, "add", "-A"); err != nil {
		return err
	}
	if _, err := r.run(wt, commitMessage(title, is.Number), 2*time.Minute, "git", "commit", "--quiet", "-F", "-"); err != nil {
		return err
	}
	if cfg.NoPR {
		r.st.Set(func(s *State) {
			s.Phase, s.Detail = PhaseDone, "committed on "+branch+", not pushed (-no-pr)"
		})
		r.st.Logf("done without a PR; worktree kept at %s", wt)
		return nil
	}
	r.phase(PhasePushing, "pushing "+branch)
	if _, err := r.git(wt, "push", "--quiet", "-u", "origin", branch); err != nil {
		return err
	}
	claudeNote := ""
	if claudeErr != nil {
		claudeNote = claudeErr.Error()
	}
	draft := !passed || claudeErr != nil
	bodyPath := filepath.Join(cfg.StateDir, r.st.ID+"-pr.md")
	if err := os.WriteFile(bodyPath, []byte(prBody(desc, is.Number, passed, cfg.Test, tail(testOut, 40), claudeNote)), 0o644); err != nil {
		return err
	}
	r.phase(PhasePushing, "opening the pull request")
	args := []string{"pr", "create", "--base", strings.TrimPrefix(base, "origin/"), "--head", branch, "--title", title, "--body-file", bodyPath}
	if draft {
		args = append(args, "--draft")
	}
	out, err := r.gh(wt, args...)
	if err != nil {
		return err
	}
	url, n := parseURL(out, "pull")
	r.cleanup(wt, branch)
	r.st.Set(func(s *State) {
		s.Phase, s.Detail = PhaseDone, ""
		s.PR, s.PRURL, s.Draft, s.Worktree = n, url, draft, ""
	})
	r.st.Logf("pull request %s", url)
	return nil
}

func (r *runner) waitLock(path string) (*lock, error) {
	type res struct {
		l   *lock
		err error
	}
	ch := make(chan res, 1)
	go func() {
		l, err := waitLock(path)
		ch <- res{l, err}
	}()
	select {
	case got := <-ch:
		return got.l, got.err
	case <-r.ctx.Done():
		return nil, r.ctx.Err()
	}
}

// run executes a command with stdin, returning stdout. The error carries
// stderr, so it reads well in the state file.
func (r *runner) run(dir, stdin string, timeout time.Duration, name string, args ...string) (string, error) {
	ctx, cancel := context.WithTimeout(r.ctx, timeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, name, args...)
	cmd.Dir = dir
	cmd.Env = append(os.Environ(), "GIT_TERMINAL_PROMPT=0", "GH_PROMPT_DISABLED=1", "NO_COLOR=1")
	if stdin != "" {
		cmd.Stdin = strings.NewReader(stdin)
	}
	var stdout, stderr bytes.Buffer
	cmd.Stdout, cmd.Stderr = &stdout, &stderr
	err := cmd.Run()
	if err != nil {
		msg := strings.TrimSpace(stderr.String())
		if msg == "" {
			msg = strings.TrimSpace(stdout.String())
		}
		if ctx.Err() == context.DeadlineExceeded {
			msg = "timed out after " + timeout.String()
		}
		return stdout.String(), fmt.Errorf("%s %s: %s", filepath.Base(name), firstArg(args), orErr(msg, err))
	}
	return stdout.String(), nil
}

func firstArg(args []string) string {
	for _, a := range args {
		if !strings.HasPrefix(a, "-") && !strings.Contains(a, "/") {
			return a
		}
	}
	return ""
}

func orErr(msg string, err error) string {
	if msg != "" {
		return msg
	}
	return err.Error()
}

func (r *runner) git(dir string, args ...string) (string, error) {
	return r.run(dir, "", 2*time.Minute, "git", append([]string{"-C", dir}, args...)...)
}

// out is git or another command's trimmed stdout, or "" on any error.
func (r *runner) out(dir, name string, args ...string) string {
	s, err := r.run(dir, "", 30*time.Second, name, args...)
	if err != nil {
		return ""
	}
	return strings.TrimSpace(s)
}

func (r *runner) gh(dir string, args ...string) (string, error) {
	if r.repo != "" {
		args = append(args, "-R", r.repo)
	}
	return r.run(dir, "", 2*time.Minute, r.cfg.GH, args...)
}

// sh runs a shell command and returns stdout and stderr together.
func (r *runner) sh(dir, command string, timeout time.Duration) (string, error) {
	ctx, cancel := context.WithTimeout(r.ctx, timeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, "bash", "-c", command)
	cmd.Dir = dir
	cmd.Env = append(os.Environ(), "GIT_TERMINAL_PROMPT=0", "NO_COLOR=1")
	var buf bytes.Buffer
	cmd.Stdout, cmd.Stderr = &buf, &buf
	err := cmd.Run()
	if ctx.Err() == context.DeadlineExceeded {
		buf.WriteString("\nbud-fix: tests timed out after " + timeout.String() + "\n")
	}
	return buf.String(), err
}

var ghRepoRe = regexp.MustCompile(`github\.com[:/]([^/\s]+/[^/\s]+?)(?:\.git)?/?$`)

func githubRepo(url string) string {
	if m := ghRepoRe.FindStringSubmatch(strings.TrimSpace(url)); m != nil {
		return m[1]
	}
	return ""
}

var urlRe = regexp.MustCompile(`https?://\S+/(issues|pull)/(\d+)`)

func parseURL(out, kind string) (string, int) {
	for _, m := range urlRe.FindAllStringSubmatch(out, -1) {
		if m[1] == kind {
			n, _ := strconv.Atoi(m[2])
			return m[0], n
		}
	}
	return "", 0
}

func (r *runner) fileIssue(is *Issue) error {
	f, err := os.CreateTemp(r.cfg.StateDir, r.st.ID+"-issue-*.md")
	if err != nil {
		return err
	}
	f.WriteString(is.Body)
	f.Close()
	defer os.Remove(f.Name())
	create := func(labels bool) (string, error) {
		args := []string{"issue", "create", "--title", is.Title, "--body-file", f.Name()}
		if labels {
			args = append(args, "--label", "bud", "--label", labelFor(is.Kind))
		}
		return r.gh(r.cfg.Repo, args...)
	}
	out, err := create(true)
	if err != nil && strings.Contains(err.Error(), "not found") {
		// a repo without Bud's labels yet: make them once, then retry
		r.st.Logf("creating labels: %v", err)
		_, _ = r.gh(r.cfg.Repo, "label", "create", "bud", "--color", "5319e7", "--description", "Reported from Bud in Neovim")
		_, _ = r.gh(r.cfg.Repo, "label", "create", labelFor(is.Kind), "--color", "a2eeef")
		out, err = create(true)
		if err != nil && strings.Contains(err.Error(), "not found") {
			out, err = create(false)
		}
	}
	if err != nil {
		return err
	}
	is.URL, is.Number = parseURL(out, "issues")
	if is.Number == 0 {
		return fmt.Errorf("gh issue create: no issue URL in %q", strings.TrimSpace(out))
	}
	return nil
}

func (r *runner) viewIssue(n int) (Issue, error) {
	out, err := r.gh(r.cfg.Repo, "issue", "view", strconv.Itoa(n), "--json", "number,title,body,labels,url")
	if err != nil {
		return Issue{}, err
	}
	var v struct {
		Number int    `json:"number"`
		Title  string `json:"title"`
		Body   string `json:"body"`
		URL    string `json:"url"`
		Labels []struct {
			Name string `json:"name"`
		} `json:"labels"`
	}
	if err := json.Unmarshal([]byte(out), &v); err != nil {
		return Issue{}, fmt.Errorf("gh issue view: %w", err)
	}
	is := Issue{Number: v.Number, URL: v.URL, Title: v.Title, Body: v.Body, Kind: "feature"}
	for _, l := range v.Labels {
		if l.Name == "bug" {
			is.Kind = "bug"
		}
	}
	if is.Number == 0 {
		is.Number = n
	}
	return is, nil
}

func (r *runner) comment(n int, body string) {
	path := filepath.Join(r.cfg.StateDir, r.st.ID+"-comment.md")
	if err := os.WriteFile(path, []byte(body+"\n"), 0o644); err != nil {
		return
	}
	if _, err := r.gh(r.cfg.Repo, "issue", "comment", strconv.Itoa(n), "--body-file", path); err != nil {
		r.st.Logf("comment: %v", err)
	}
}

func (r *runner) base() (string, error) {
	if r.cfg.Base != "" {
		return r.cfg.Base, nil
	}
	if b := r.out(r.cfg.Repo, "git", "-C", r.cfg.Repo, "symbolic-ref", "--short", "refs/remotes/origin/HEAD"); b != "" {
		return b, nil
	}
	for _, b := range []string{"origin/main", "origin/master"} {
		if _, err := r.git(r.cfg.Repo, "rev-parse", "--verify", "--quiet", b); err == nil {
			return b, nil
		}
	}
	return "", errors.New("can't find the default branch: set origin/HEAD with `git remote set-head origin -a`")
}

// branch picks bud/<issue>-<slug>, with a suffix when an earlier attempt
// already used the name here or on origin.
func (r *runner) branch(is Issue) (string, error) {
	name := fmt.Sprintf("bud/%d-%s", is.Number, slug(is.Title))
	for i := 1; i < 10; i++ {
		b := name
		if i > 1 {
			b = fmt.Sprintf("%s-%d", name, i)
		}
		_, local := r.git(r.cfg.Repo, "rev-parse", "--verify", "--quiet", "refs/heads/"+b)
		_, remote := r.git(r.cfg.Repo, "ls-remote", "--exit-code", "--heads", "origin", b)
		if local != nil && remote != nil {
			return b, nil
		}
	}
	return "", fmt.Errorf("branches %s through -9 already exist", name)
}

// changes lists every path the worktree differs in, untracked included.
func (r *runner) changes(wt string) ([]string, error) {
	out, err := r.git(wt, "status", "--porcelain=v1", "-z", "--untracked-files=all")
	if err != nil {
		return nil, err
	}
	var paths []string
	entries := strings.Split(out, "\x00")
	for i := 0; i < len(entries); i++ {
		e := entries[i]
		if len(e) < 4 {
			continue
		}
		paths = append(paths, e[3:])
		if e[0] == 'R' || e[0] == 'C' {
			i++ // the next entry is the original path
			if i < len(entries) && entries[i] != "" {
				paths = append(paths, entries[i])
			}
		}
	}
	return paths, nil
}

func (r *runner) cleanup(wt, branch string) {
	if _, err := r.git(r.cfg.Repo, "worktree", "remove", "--force", wt); err != nil {
		r.st.Logf("cleanup: %v", err)
		return
	}
	_, _ = r.git(r.cfg.Repo, "branch", "-D", branch)
}

// The Claude process

type event struct {
	Type      string `json:"type"`
	Subtype   string `json:"subtype"`
	SessionID string `json:"session_id"`
	Message   *struct {
		Content []struct {
			Type  string          `json:"type"`
			Name  string          `json:"name"`
			Input json.RawMessage `json:"input"`
		} `json:"content"`
	} `json:"message"`
	Result  string  `json:"result"`
	IsError bool    `json:"is_error"`
	Cost    float64 `json:"total_cost_usd"`
	Turns   int     `json:"num_turns"`
}

func (r *runner) restricted() bool {
	out, _ := r.run(r.cfg.Repo, "", 20*time.Second, r.cfg.Claude, "--help")
	return strings.Contains(out, "--restricted")
}

func (r *runner) claudeArgs(restricted bool) []string {
	args := []string{"-p", "--output-format", "stream-json", "--verbose", "--model", r.cfg.Model}
	if restricted {
		// no user or project settings, file tools confined to the worktree
		args = append(args, "--restricted")
	}
	args = append(args,
		"--tools", "Read,Grep,Glob,Edit,Write,Bash",
		"--allowedTools", strings.Join(allowedTools(r.cfg.Edit, r.cfg.Allow), ","),
		"--permission-mode", "dontAsk",
		"--strict-mcp-config",
	)
	if r.cfg.SystemFile != "" {
		args = append(args, "--append-system-prompt-file", r.cfg.SystemFile)
	}
	return args
}

// claude runs one non-interactive session in the worktree and returns its
// final message. Tool calls show up in the state's detail as they happen.
func (r *runner) claude(wt, prompt string) (string, error) {
	restricted := r.restricted()
	if !restricted {
		r.st.Logf("this claude has no --restricted flag; your user settings apply to the fixer")
	}
	ctx, cancel := context.WithTimeout(r.ctx, r.cfg.Timeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, r.cfg.Claude, r.claudeArgs(restricted)...)
	cmd.Dir = wt
	cmd.Stdin = strings.NewReader(prompt)
	cmd.Cancel = func() error { return cmd.Process.Signal(syscall.SIGTERM) }
	cmd.WaitDelay = 5 * time.Second
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return "", err
	}
	if err := cmd.Start(); err != nil {
		return "", err
	}
	var result *event
	sc := bufio.NewScanner(stdout)
	sc.Buffer(make([]byte, 64*1024), 16*1024*1024)
	for sc.Scan() {
		var ev event
		if json.Unmarshal(sc.Bytes(), &ev) != nil {
			continue
		}
		if ev.SessionID != "" && r.st.SessionID == "" {
			r.st.Set(func(s *State) { s.SessionID = ev.SessionID })
		}
		switch ev.Type {
		case "assistant":
			if ev.Message == nil {
				continue
			}
			for _, c := range ev.Message.Content {
				if c.Type == "tool_use" {
					d := describeTool(c.Name, c.Input, wt)
					r.st.Set(func(s *State) { s.Detail = d })
					r.st.Logf("  %s", d)
				}
			}
		case "result":
			e := ev
			result = &e
		}
	}
	waitErr := cmd.Wait()
	if ctx.Err() == context.DeadlineExceeded {
		return "", fmt.Errorf("timed out after %s", r.cfg.Timeout)
	}
	if result == nil {
		msg := strings.TrimSpace(tail(stderr.String(), 10))
		if msg == "" && waitErr != nil {
			msg = waitErr.Error()
		}
		return "", fmt.Errorf("no result from claude: %s", orErr(msg, errors.New("it exited without one")))
	}
	r.st.Logf("claude finished: %d turns, $%.2f", result.Turns, result.Cost)
	if result.IsError {
		return result.Result, fmt.Errorf("%s", orErr(result.Result, errors.New(result.Subtype)))
	}
	return result.Result, nil
}

func describeTool(name string, input json.RawMessage, wt string) string {
	var in struct {
		FilePath string `json:"file_path"`
		Path     string `json:"path"`
		Command  string `json:"command"`
		Pattern  string `json:"pattern"`
	}
	_ = json.Unmarshal(input, &in)
	rel := func(p string) string {
		if r, err := filepath.Rel(wt, p); err == nil && !strings.HasPrefix(r, "..") {
			return r
		}
		return filepath.Base(p)
	}
	switch name {
	case "Edit", "Write", "MultiEdit", "NotebookEdit":
		return "editing " + rel(in.FilePath)
	case "Read":
		return "reading " + rel(in.FilePath)
	case "Grep", "Glob":
		return "searching"
	case "Bash":
		c := strings.TrimSpace(in.Command)
		if strings.Contains(c, "test.sh") || strings.Contains(c, "run.sh") || strings.Contains(c, " test ") {
			return "running tests"
		}
		if len(c) > 40 {
			c = c[:39] + "…"
		}
		return "running " + c
	}
	return name
}
