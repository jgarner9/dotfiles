package main

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"syscall"
	"time"
)

// Phases a run goes through. The last three are terminal.
const (
	PhaseFiling    = "filing"
	PhaseQueued    = "queued"
	PhasePreparing = "preparing"
	PhaseFixing    = "fixing"
	PhaseTesting   = "testing"
	PhasePushing   = "pushing"
	PhaseDone      = "done"
	PhaseNoChange  = "no_change"
	PhaseFailed    = "failed"
)

func terminal(phase string) bool {
	return phase == PhaseDone || phase == PhaseNoChange || phase == PhaseFailed
}

// State is one run, written to <state dir>/<id>.json after every step so
// Bud (or `bud-fix status`) can follow along from another process.
type State struct {
	ID        string     `json:"id"`
	PID       int        `json:"pid"`
	Kind      string     `json:"kind"`
	Title     string     `json:"title"`
	Phase     string     `json:"phase"`
	Detail    string     `json:"detail,omitempty"`
	Issue     int        `json:"issue,omitempty"`
	IssueURL  string     `json:"issue_url,omitempty"`
	Branch    string     `json:"branch,omitempty"`
	Worktree  string     `json:"worktree,omitempty"`
	PR        int        `json:"pr,omitempty"`
	PRURL     string     `json:"pr_url,omitempty"`
	Draft     bool       `json:"draft,omitempty"`
	Tests     string     `json:"tests,omitempty"` // passed | failed
	SessionID string     `json:"session_id,omitempty"`
	Summary   string     `json:"summary,omitempty"`
	Error     string     `json:"error,omitempty"`
	Log       string     `json:"log"`
	Started   time.Time  `json:"started"`
	Updated   time.Time  `json:"updated"`
	Finished  *time.Time `json:"finished,omitempty"`

	path string
	mu   sync.Mutex
}

func newID(now time.Time) string {
	b := make([]byte, 2)
	_, _ = rand.Read(b)
	return now.Format("20060102-150405") + "-" + hex.EncodeToString(b)
}

func newState(dir, kind, title string) (*State, error) {
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return nil, err
	}
	now := time.Now()
	id := newID(now)
	s := &State{
		ID:      id,
		PID:     os.Getpid(),
		Kind:    kind,
		Title:   title,
		Log:     filepath.Join(dir, id+".log"),
		Started: now,
		path:    filepath.Join(dir, id+".json"),
	}
	return s, s.save()
}

// Set applies fn and writes the file. Safe from any goroutine.
func (s *State) Set(fn func(*State)) {
	s.mu.Lock()
	defer s.mu.Unlock()
	fn(s)
	if terminal(s.Phase) && s.Finished == nil {
		now := time.Now()
		s.Finished = &now
	}
	_ = s.save()
}

// save writes atomically, so a reader never sees half a file.
func (s *State) save() error {
	s.Updated = time.Now()
	data, err := json.MarshalIndent(s, "", "  ")
	if err != nil {
		return err
	}
	tmp := s.path + ".tmp"
	if err := os.WriteFile(tmp, append(data, '\n'), 0o644); err != nil {
		return err
	}
	return os.Rename(tmp, s.path)
}

// Logf appends a timestamped line to the run's log.
func (s *State) Logf(format string, args ...any) {
	f, err := os.OpenFile(s.Log, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o644)
	if err != nil {
		return
	}
	defer f.Close()
	msg := fmt.Sprintf(format, args...)
	for _, line := range strings.Split(strings.TrimRight(msg, "\n"), "\n") {
		fmt.Fprintf(f, "%s %s\n", time.Now().Format("15:04:05"), line)
	}
}

// Stale is true for a run that never finished and whose process is gone.
func (s *State) Stale() bool {
	if terminal(s.Phase) || s.PID <= 0 {
		return false
	}
	return !alive(s.PID)
}

func alive(pid int) bool {
	err := syscall.Kill(pid, 0)
	return err == nil || errors.Is(err, syscall.EPERM)
}

// loadRuns reads every run in dir, newest first.
func loadRuns(dir string) ([]*State, error) {
	paths, err := filepath.Glob(filepath.Join(dir, "*.json"))
	if err != nil {
		return nil, err
	}
	var runs []*State
	for _, p := range paths {
		data, err := os.ReadFile(p)
		if err != nil {
			continue
		}
		var s State
		if json.Unmarshal(data, &s) == nil && s.ID != "" {
			s.path = p
			runs = append(runs, &s)
		}
	}
	sort.Slice(runs, func(i, j int) bool { return runs[i].ID > runs[j].ID })
	return runs, nil
}

// lock serializes fixes: one worktree, one Claude, one test run at a time.
// A second run waits here (phase "queued") until the first finishes.
type lock struct{ f *os.File }

func tryLock(path string) (*lock, bool, error) {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return nil, false, err
	}
	f, err := os.OpenFile(path, os.O_CREATE|os.O_RDWR, 0o644)
	if err != nil {
		return nil, false, err
	}
	if err := syscall.Flock(int(f.Fd()), syscall.LOCK_EX|syscall.LOCK_NB); err != nil {
		f.Close()
		if errors.Is(err, syscall.EWOULDBLOCK) {
			return nil, false, nil
		}
		return nil, false, err
	}
	return &lock{f}, true, nil
}

func waitLock(path string) (*lock, error) {
	f, err := os.OpenFile(path, os.O_CREATE|os.O_RDWR, 0o644)
	if err != nil {
		return nil, err
	}
	if err := syscall.Flock(int(f.Fd()), syscall.LOCK_EX); err != nil {
		f.Close()
		return nil, err
	}
	return &lock{f}, nil
}

func (l *lock) release() {
	if l != nil && l.f != nil {
		_ = syscall.Flock(int(l.f.Fd()), syscall.LOCK_UN)
		l.f.Close()
	}
}
