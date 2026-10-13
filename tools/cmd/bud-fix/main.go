// bud-fix turns a bug report or feature request for Bud into a pull request.
//
// It files the GitHub issue, runs Claude Code in a fresh git worktree of the
// dotfiles repo with edits limited to Bud's own files, then runs the tests
// itself and opens the pull request: ready for review when they pass, a
// draft when they don't. Claude never commits, pushes or opens anything;
// those steps are bud-fix's, and it never merges. Bud starts it detached, so
// quitting Neovim doesn't stop a fix, and follows along through the state
// files. See SPEC.md.
package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"time"
)

const usage = `usage:
  bud-fix report -kind bug|feature -title TITLE -body-file FILE [-context-file FILE] [flags]
  bud-fix issue [flags] NUMBER
  bud-fix status [-json] [-state DIR]

report files a new issue, then fixes it; issue fixes one that already exists.
Both print the pull request URL when they finish. Run state is kept in
-state as <id>.json and <id>.log.

flags:
`

type multi []string

func (m *multi) String() string     { return strings.Join(*m, ",") }
func (m *multi) Set(v string) error { *m = append(*m, v); return nil }

func xdg(env, fallback string) string {
	if v := os.Getenv(env); v != "" {
		return v
	}
	home, _ := os.UserHomeDir()
	return filepath.Join(home, fallback)
}

func chezmoiSource() string {
	if out, err := exec.Command("chezmoi", "source-path").Output(); err == nil {
		if p := strings.TrimSpace(string(out)); p != "" {
			return p
		}
	}
	home, _ := os.UserHomeDir()
	return filepath.Join(home, ".local", "share", "chezmoi")
}

func main() {
	os.Exit(cli(os.Args[1:], os.Stdout, os.Stderr))
}

func cli(args []string, stdout, stderr io.Writer) int {
	if len(args) == 0 || args[0] == "-h" || args[0] == "--help" || args[0] == "help" {
		fmt.Fprint(stdout, usage)
		flags("report", stdout, &Config{}, &Job{}).PrintDefaults()
		return 0
	}
	sub, rest := args[0], args[1:]
	switch sub {
	case "status":
		return status(rest, stdout, stderr)
	case "report", "issue":
	default:
		fmt.Fprintf(stderr, "bud-fix: unknown command %q\n\n%s", sub, usage)
		return 2
	}

	var cfg Config
	var job Job
	fs := flags(sub, stderr, &cfg, &job)
	if err := fs.Parse(rest); err != nil {
		return 2
	}
	// flags may come before or after the issue number
	if sub == "issue" && fs.NArg() > 0 {
		n, err := strconv.Atoi(strings.TrimPrefix(fs.Arg(0), "#"))
		if err != nil || n <= 0 {
			fmt.Fprintf(stderr, "bud-fix: %q is not an issue number\n", fs.Arg(0))
			return 2
		}
		job.Issue = n
		if err := fs.Parse(fs.Args()[1:]); err != nil {
			return 2
		}
	}
	if len(cfg.Edit) == 0 {
		cfg.Edit = defaultEdit
	}
	if cfg.Repo == "" {
		cfg.Repo = chezmoiSource()
	}
	switch {
	case sub == "issue" && job.Issue == 0:
		fmt.Fprintln(stderr, "bud-fix: issue needs a number")
		return 2
	case sub == "report" && job.Kind != "bug" && job.Kind != "feature":
		fmt.Fprintln(stderr, "bud-fix: -kind must be bug or feature")
		return 2
	case sub == "report" && (strings.TrimSpace(job.Title) == "" || job.BodyFile == ""):
		fmt.Fprintln(stderr, "bud-fix: report needs -title and -body-file")
		return 2
	}
	if st, err := os.Stat(filepath.Join(cfg.Repo, ".git")); err != nil || st == nil {
		fmt.Fprintf(stderr, "bud-fix: %s is not a git repo (set -repo)\n", cfg.Repo)
		return 2
	}

	// Bud starts this detached: a closed terminal or a gone Neovim must not
	// stop it, and output it can't write is fine (everything goes to the
	// state files too).
	signal.Ignore(syscall.SIGHUP, syscall.SIGPIPE)
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	st, err := run(ctx, cfg, job)
	if st == nil {
		fmt.Fprintf(stderr, "bud-fix: %v\n", err)
		return 1
	}
	if err != nil {
		fmt.Fprintf(stderr, "bud-fix: %v\nlog: %s\n", err, st.Log)
		return 1
	}
	switch {
	case st.PRURL != "":
		fmt.Fprintln(stdout, st.PRURL)
	case st.Phase == PhaseNoChange:
		fmt.Fprintf(stdout, "no changes; notes are on %s\n", st.IssueURL)
	default:
		fmt.Fprintln(stdout, st.Detail)
	}
	return 0
}

func flags(sub string, out io.Writer, cfg *Config, job *Job) *flag.FlagSet {
	fs := flag.NewFlagSet("bud-fix "+sub, flag.ContinueOnError)
	if out != nil {
		fs.SetOutput(out)
	}
	fs.StringVar(&job.Kind, "kind", "", "bug or feature (report)")
	fs.StringVar(&job.Title, "title", "", "issue title (report)")
	fs.StringVar(&job.BodyFile, "body-file", "", "issue body, markdown (report)")
	fs.StringVar(&job.ContextFile, "context-file", "", "extra context for Claude that stays out of the issue")
	fs.StringVar(&cfg.Repo, "repo", "", "the dotfiles repo (default: chezmoi source-path)")
	fs.StringVar(&cfg.StateDir, "state", filepath.Join(xdg("XDG_STATE_HOME", ".local/state"), "bud", "fixes"), "where runs are recorded")
	fs.StringVar(&cfg.CacheDir, "cache", filepath.Join(xdg("XDG_CACHE_HOME", ".cache"), "bud"), "worktrees go in <cache>/worktrees")
	fs.StringVar(&cfg.Model, "model", "sonnet", "Claude model for the fix")
	fs.StringVar(&cfg.SystemFile, "system-file", "", "appended to Claude's system prompt")
	fs.Var((*multi)(&cfg.Allow), "allow", "extra allowed tool rule, e.g. 'Bash(repomap *)' (repeatable)")
	fs.Var((*multi)(&cfg.Edit), "edit", "path glob Claude may edit, relative to the repo (repeatable; default: Bud's files and tools/)")
	fs.StringVar(&cfg.Test, "test", "bash tools/test.sh", "test command, run in the worktree")
	fs.StringVar(&cfg.Base, "base", "", "base ref (default: origin/HEAD)")
	fs.StringVar(&cfg.Claude, "claude", "claude", "the Claude Code CLI")
	fs.StringVar(&cfg.GH, "gh", "gh", "the GitHub CLI")
	fs.DurationVar(&cfg.Timeout, "timeout", 45*time.Minute, "how long Claude may work")
	fs.DurationVar(&cfg.TestTimeout, "test-timeout", 20*time.Minute, "how long the tests may run")
	fs.BoolVar(&cfg.NoPR, "no-pr", false, "commit on the branch and stop: no push, no pull request")
	return fs
}

func status(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("bud-fix status", flag.ContinueOnError)
	fs.SetOutput(stderr)
	asJSON := fs.Bool("json", false, "print the runs as JSON")
	dir := fs.String("state", filepath.Join(xdg("XDG_STATE_HOME", ".local/state"), "bud", "fixes"), "where runs are recorded")
	limit := fs.Int("n", 10, "runs to show")
	if err := fs.Parse(args); err != nil {
		return 2
	}
	runs, err := loadRuns(*dir)
	if err != nil {
		fmt.Fprintf(stderr, "bud-fix: %v\n", err)
		return 1
	}
	if len(runs) > *limit {
		runs = runs[:*limit]
	}
	for _, s := range runs {
		if s.Stale() {
			s.Phase, s.Error = PhaseFailed, "stopped before it finished"
		}
	}
	if *asJSON {
		data, _ := json.MarshalIndent(runs, "", "  ")
		fmt.Fprintln(stdout, string(data))
		return 0
	}
	if len(runs) == 0 {
		fmt.Fprintln(stdout, "no runs yet")
		return 0
	}
	for _, s := range runs {
		where := ""
		if s.Issue > 0 {
			where = fmt.Sprintf("#%d", s.Issue)
		}
		if s.PR > 0 {
			where += fmt.Sprintf(" → PR #%d", s.PR)
			if s.Draft {
				where += " (draft)"
			}
		}
		note := s.Detail
		if s.Error != "" {
			note = s.Error
		}
		fmt.Fprintf(stdout, "%s  %-9s %-22s %s\n", s.ID, s.Phase, where, s.Title)
		if note != "" {
			fmt.Fprintf(stdout, "%22s %s\n", "", note)
		}
	}
	return 0
}
