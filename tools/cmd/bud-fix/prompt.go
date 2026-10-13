package main

import (
	"fmt"
	"regexp"
	"strings"
)

// Paths Claude may edit, relative to the repo root: Bud itself, its plugin
// spec, and tools/ (Bud's tests and the Go tools).
var defaultEdit = []string{
	"dot_config/nvim/lua/bud/**",
	"dot_config/nvim/bud/**",
	"dot_config/nvim/lua/plugins/bud.lua",
	"tools/**",
}

// Commands Claude may run besides reading and searching: the test runners and
// read-only git. No commit, push, gh or network.
var baseBash = []string{
	"Bash(bash tools/test.sh*)",
	"Bash(tools/test.sh*)",
	"Bash(bash tools/bud/run.sh*)",
	"Bash(tools/bud/run.sh*)",
	"Bash(go -C tools test *)",
	"Bash(go -C tools vet *)",
	"Bash(git status*)",
	"Bash(git diff*)",
	"Bash(git log*)",
	"Bash(git show*)",
	"Bash(rg *)",
	"Bash(shellcheck *)",
}

// allowedTools is the --allowedTools list for a run.
func allowedTools(edit, extra []string) []string {
	out := []string{"Read", "Grep", "Glob"}
	for _, g := range edit {
		out = append(out, "Edit(./"+strings.TrimPrefix(g, "./")+")")
	}
	out = append(out, baseBash...)
	seen := map[string]bool{}
	for _, r := range out {
		seen[r] = true
	}
	for _, r := range extra {
		if !seen[r] {
			out = append(out, r)
			seen[r] = true
		}
	}
	return out
}

// Issue is what the fixer works from.
type Issue struct {
	Number int
	URL    string
	Kind   string // bug | feature
	Title  string
	Body   string
}

func taskPrompt(is Issue, context, branch string, edit []string) string {
	var b strings.Builder
	noun := "feature request"
	if is.Kind == "bug" {
		noun = "bug report"
	}
	fmt.Fprintf(&b, "You're working on a %s for Bud, the Neovim plugin in this dotfiles repo, filed as issue #%d.\n\n", noun, is.Number)
	fmt.Fprintf(&b, "<issue>\n# %s\n\n%s\n</issue>\n\n", is.Title, strings.TrimSpace(is.Body))
	if strings.TrimSpace(context) != "" {
		b.WriteString("Bud attached this from the reporter's machine. It isn't in the issue.\n\n")
		fmt.Fprintf(&b, "<local-context>\n%s\n</local-context>\n\n", strings.TrimSpace(context))
	}
	fmt.Fprintf(&b, "You're in a fresh git worktree of the repo, on branch %s. Work like this:\n\n", branch)
	b.WriteString("1. Read tools/bud/README.md and the code involved before changing anything.\n")
	if is.Kind == "bug" {
		b.WriteString("2. Reproduce it first: add a test (tools/bud/tests/test_*.lua for Bud, a Go test for a tool) that fails because of the bug, run it and watch it fail. Then fix the code until it passes.\n")
	} else {
		b.WriteString("2. Build it in the style of the surrounding code, with tests for the new behavior (tools/bud/tests/test_*.lua for Bud, Go tests for a tool). Update the docs and keymap lists it touches.\n")
	}
	b.WriteString("3. Run the whole suite with `bash tools/test.sh` and keep going until it passes. `bash tools/bud/run.sh <name>` runs just tools/bud/tests/test_<name>.lua.\n")
	b.WriteString("4. Keep the change as small as the request allows, and leave unrelated code alone.\n\n")
	fmt.Fprintf(&b, "You can edit only these paths: %s.\n", strings.Join(edit, ", "))
	b.WriteString("Shell commands are limited to the test runners above, `go -C tools test` and `go -C tools vet`, `rg`, `shellcheck`, and read-only git (status, diff, log, show), one plain command at a time. ")
	b.WriteString("Don't commit, push or open anything yourself: when you finish, bud-fix runs the tests again, commits your changes and opens the pull request.\n\n")
	b.WriteString("If you can't finish, or can't get the tests to pass, stop and say what you found and what's left. bud-fix opens a draft pull request with whatever you changed.\n\n")
	b.WriteString("End your final message with the pull request description, in exactly this shape:\n\n")
	b.WriteString("Title: <imperative summary, under 70 characters>\n\n")
	b.WriteString("Before: <what the user saw before, in a sentence or two>\n\n")
	b.WriteString("After: <what they see now>\n\n")
	b.WriteString("How: <a short paragraph on the change>\n")
	return b.String()
}

var titleLine = regexp.MustCompile(`(?im)^\s*\**title\**\s*:\s*\**\s*(.+?)\s*$`)

// parseFinal splits Claude's last message into a PR title and description.
// The last "Title:" line wins; without one, the issue title stands in and
// the whole message becomes the description.
func parseFinal(text, fallback string) (title, body string) {
	text = strings.TrimSpace(text)
	locs := titleLine.FindAllStringSubmatchIndex(text, -1)
	if len(locs) == 0 {
		return fallback, text
	}
	last := locs[len(locs)-1]
	title = strings.Trim(text[last[2]:last[3]], "`*\"' ")
	body = strings.TrimSpace(text[last[1]:])
	if title == "" {
		title = fallback
	}
	if len([]rune(title)) > 72 {
		title = string([]rune(title)[:71]) + "…"
	}
	return title, body
}

func prBody(desc string, issue int, testsPassed bool, testCmd, testTail, claudeErr string) string {
	var b strings.Builder
	if strings.TrimSpace(desc) != "" {
		b.WriteString(strings.TrimSpace(desc))
		b.WriteString("\n\n")
	}
	fmt.Fprintf(&b, "Fixes #%d\n\n", issue)
	if claudeErr != "" {
		fmt.Fprintf(&b, "**Claude stopped early:** %s\n\n", claudeErr)
	}
	if testsPassed {
		fmt.Fprintf(&b, "**Tests:** `%s` passed.\n", testCmd)
	} else {
		fmt.Fprintf(&b, "**Tests:** `%s` failed, so this is a draft. The last lines:\n\n", testCmd)
		fmt.Fprintf(&b, "```text\n%s\n```\n", strings.TrimRight(testTail, "\n"))
	}
	b.WriteString("\n---\n🤖 Opened by bud-fix from a report in Neovim. Claude Code wrote the change; bud-fix ran the tests and opened this PR.\n")
	return b.String()
}

func commitMessage(title string, issue int) string {
	return fmt.Sprintf("%s\n\nRefs #%d\n\nCo-Authored-By: Claude <noreply@anthropic.com>\n", title, issue)
}

var nonSlug = regexp.MustCompile(`[^a-z0-9]+`)

// slug turns a title into a short branch-safe name.
func slug(title string) string {
	s := nonSlug.ReplaceAllString(strings.ToLower(title), "-")
	s = strings.Trim(s, "-")
	words := strings.Split(s, "-")
	if len(words) > 5 {
		words = words[:5]
	}
	s = strings.Join(words, "-")
	if len(s) > 40 {
		s = strings.Trim(s[:40], "-")
	}
	if s == "" {
		return "report"
	}
	return s
}

// globRe compiles a path glob: ** matches across directories, * and ?
// within one.
func globRe(glob string) *regexp.Regexp {
	glob = strings.TrimPrefix(glob, "./")
	var b strings.Builder
	b.WriteString("^")
	for i := 0; i < len(glob); i++ {
		c := glob[i]
		switch {
		case c == '*' && i+1 < len(glob) && glob[i+1] == '*':
			i++
			if i+1 < len(glob) && glob[i+1] == '/' {
				i++
				b.WriteString("(?:.*/)?")
			} else {
				b.WriteString(".*")
			}
		case c == '*':
			b.WriteString("[^/]*")
		case c == '?':
			b.WriteString("[^/]")
		default:
			b.WriteString(regexp.QuoteMeta(string(c)))
		}
	}
	b.WriteString("$")
	return regexp.MustCompile(b.String())
}

// outside lists the paths no glob covers.
func outside(paths, globs []string) []string {
	var res []*regexp.Regexp
	for _, g := range globs {
		res = append(res, globRe(g))
	}
	var out []string
	for _, p := range paths {
		ok := false
		for _, re := range res {
			if re.MatchString(p) {
				ok = true
				break
			}
		}
		if !ok {
			out = append(out, p)
		}
	}
	return out
}

// tail keeps the last n lines of s.
func tail(s string, n int) string {
	lines := strings.Split(strings.TrimRight(s, "\n"), "\n")
	if len(lines) > n {
		lines = lines[len(lines)-n:]
	}
	return strings.Join(lines, "\n")
}
