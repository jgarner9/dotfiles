// repomap prints a ranked map of a repository's files and their top-level
// symbols, so an LLM can see the shape of a codebase before reading it.
//
// Symbols are found with per-language regular expressions (no parser, no
// cgo). Each symbol is ranked by how often its name appears elsewhere in the
// repo, and each file by the sum of its symbols' references. The output is
// fully deterministic for a given tree. See SPEC.md.
package main

import (
	"bufio"
	"bytes"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
)

const maxFileBytes = 512 * 1024

type Symbol struct {
	Name string `json:"name"`
	Kind string `json:"kind"`
	Line int    `json:"line"`
	Refs int    `json:"refs"`
	key  string // identifier used for reference counting
}

type File struct {
	Path    string   `json:"path"`
	Score   int      `json:"score"`
	Symbols []Symbol `json:"symbols"`
}

type Map struct {
	Files      []File `json:"files"`
	TotalFiles int    `json:"total_files"`
}

type rule struct {
	re   *regexp.Regexp
	kind string
	name int // capture group holding the name
	recv int // optional capture group holding a receiver/owner (0 = none)
}

func r(pattern, kind string, name int) rule {
	return rule{re: regexp.MustCompile(pattern), kind: kind, name: name}
}

var goMethod = rule{
	re:   regexp.MustCompile(`^func\s+\(\s*(?:\w+\s+)?\*?\s*([A-Za-z_]\w*)(?:\[[^\]]*\])?\s*\)\s+([A-Za-z_]\w*)`),
	kind: "method", name: 2, recv: 1,
}

var rules = map[string][]rule{
	"go": {
		goMethod,
		r(`^func\s+([A-Za-z_]\w*)`, "fn", 1),
		r(`^type\s+([A-Za-z_]\w*)\s+interface\b`, "iface", 1),
		r(`^type\s+([A-Za-z_]\w*)`, "type", 1),
	},
	"lua": {
		r(`^local\s+function\s+([\w.:]+)`, "fn", 1),
		r(`^function\s+([\w.:]+)`, "fn", 1),
		r(`^([A-Za-z_][\w]*[.:][\w.:]+)\s*=\s*function\b`, "fn", 1),
	},
	"python": {
		r(`^class\s+([A-Za-z_]\w*)`, "class", 1),
		r(`^(?:async\s+)?def\s+([A-Za-z_]\w*)`, "fn", 1),
		r(`^    (?:async\s+)?def\s+([A-Za-z_]\w*)`, "method", 1),
	},
	"js": {
		r(`^(?:export\s+)?(?:default\s+)?(?:async\s+)?function\*?\s+([A-Za-z_$][\w$]*)`, "fn", 1),
		r(`^(?:export\s+)?(?:default\s+)?(?:abstract\s+)?class\s+([A-Za-z_$][\w$]*)`, "class", 1),
		r(`^(?:export\s+)?(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*(?::[^=]+)?=\s*(?:async\s*)?(?:\([^)]*\)|[A-Za-z_$][\w$]*)\s*(?::[^=]+)?=>`, "fn", 1),
		r(`^(?:export\s+)?(?:declare\s+)?interface\s+([A-Za-z_$][\w$]*)`, "iface", 1),
		r(`^(?:export\s+)?(?:declare\s+)?type\s+([A-Za-z_$][\w$]*)\s*(?:<[^>]*>)?\s*=`, "type", 1),
		r(`^(?:export\s+)?(?:const\s+)?enum\s+([A-Za-z_$][\w$]*)`, "type", 1),
	},
	"rust": {
		r(`^\s{0,4}(?:pub(?:\([^)]*\))?\s+)?(?:const\s+)?(?:async\s+)?(?:unsafe\s+)?fn\s+([A-Za-z_]\w*)`, "fn", 1),
		r(`^(?:pub(?:\([^)]*\))?\s+)?trait\s+([A-Za-z_]\w*)`, "iface", 1),
		r(`^(?:pub(?:\([^)]*\))?\s+)?(?:struct|enum|union|type)\s+([A-Za-z_]\w*)`, "type", 1),
	},
	"ruby": {
		r(`^\s*(?:class|module)\s+([A-Z][\w:]*)`, "class", 1),
		r(`^\s*def\s+(?:self\.)?([A-Za-z_]\w*[?!=]?)`, "fn", 1),
	},
	"shell": {
		r(`^(?:function\s+)?([A-Za-z_][\w-]*)\s*\(\)\s*\{?`, "fn", 1),
		r(`^function\s+([A-Za-z_][\w-]*)`, "fn", 1),
	},
}

var langByExt = map[string]string{
	".go": "go", ".lua": "lua", ".py": "python",
	".js": "js", ".jsx": "js", ".mjs": "js", ".cjs": "js", ".ts": "js", ".tsx": "js",
	".rs": "rust", ".rb": "ruby", ".sh": "shell", ".bash": "shell", ".zsh": "shell",
}

var skipDirs = map[string]bool{
	".git": true, "node_modules": true, "vendor": true, "dist": true, "build": true,
	"target": true, ".venv": true, "venv": true, "__pycache__": true, ".cache": true,
}

var identRe = regexp.MustCompile(`[A-Za-z_][A-Za-z0-9_]*`)

func main() {
	root := flag.String("root", ".", "repository root")
	maxFiles := flag.Int("max", 50, "maximum files to print (0 = all)")
	perFile := flag.Int("per", 15, "maximum symbols per file (0 = all)")
	asJSON := flag.Bool("json", false, "print JSON instead of text")
	noGit := flag.Bool("no-git", false, "walk the tree instead of asking git for the file list")
	flag.Parse()

	m, err := Build(*root, !*noGit)
	if err != nil {
		fmt.Fprintln(os.Stderr, "repomap:", err)
		os.Exit(1)
	}
	m = m.Limit(*maxFiles, *perFile)
	if *asJSON {
		enc := json.NewEncoder(os.Stdout)
		enc.SetIndent("", "  ")
		if err := enc.Encode(m); err != nil {
			fmt.Fprintln(os.Stderr, "repomap:", err)
			os.Exit(1)
		}
		return
	}
	Render(os.Stdout, m)
}

// listFiles returns repo-relative, slash-separated paths, sorted.
func listFiles(root string, useGit bool) ([]string, error) {
	if useGit {
		out, err := exec.Command("git", "-C", root, "ls-files", "-z", "--cached", "--others", "--exclude-standard").Output()
		if err == nil {
			var files []string
			for _, f := range bytes.Split(out, []byte{0}) {
				if len(f) > 0 {
					files = append(files, string(f))
				}
			}
			sort.Strings(files)
			return files, nil
		}
	}
	var files []string
	err := filepath.WalkDir(root, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if d.IsDir() {
			if path != root && skipDirs[d.Name()] {
				return filepath.SkipDir
			}
			return nil
		}
		if !d.Type().IsRegular() {
			return nil
		}
		rel, err := filepath.Rel(root, path)
		if err != nil {
			return err
		}
		files = append(files, filepath.ToSlash(rel))
		return nil
	})
	sort.Strings(files)
	return files, err
}

func readText(path string) ([]byte, bool) {
	info, err := os.Stat(path)
	if err != nil || !info.Mode().IsRegular() || info.Size() > maxFileBytes {
		return nil, false
	}
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, false
	}
	head := data
	if len(head) > 8000 {
		head = head[:8000]
	}
	if bytes.IndexByte(head, 0) >= 0 {
		return nil, false
	}
	return data, true
}

func symbolsIn(lang string, data []byte) []Symbol {
	var syms []Symbol
	sc := bufio.NewScanner(bytes.NewReader(data))
	sc.Buffer(make([]byte, 64*1024), maxFileBytes)
	line := 0
	for sc.Scan() {
		line++
		text := sc.Text()
		for _, rl := range rules[lang] {
			m := rl.re.FindStringSubmatch(text)
			if m == nil {
				continue
			}
			name := m[rl.name]
			key := name
			if i := strings.LastIndexAny(key, ".:"); i >= 0 {
				key = key[i+1:]
			}
			if rl.recv > 0 {
				name = m[rl.recv] + "." + name
			}
			syms = append(syms, Symbol{Name: name, Kind: rl.kind, Line: line, key: key})
			break
		}
	}
	return syms
}

// Build scans root and returns every file with at least one symbol, ranked.
func Build(root string, useGit bool) (Map, error) {
	paths, err := listFiles(root, useGit)
	if err != nil {
		return Map{}, err
	}
	counts := map[string]int{}
	defs := map[string]int{}
	var files []File
	for _, p := range paths {
		data, ok := readText(filepath.Join(root, filepath.FromSlash(p)))
		if !ok {
			continue
		}
		for _, id := range identRe.FindAll(data, -1) {
			counts[string(id)]++
		}
		lang := langByExt[strings.ToLower(filepath.Ext(p))]
		if lang == "" {
			continue
		}
		syms := symbolsIn(lang, data)
		for _, s := range syms {
			defs[s.key]++
		}
		if len(syms) > 0 {
			files = append(files, File{Path: p, Symbols: syms})
		}
	}
	for i := range files {
		f := &files[i]
		for j := range f.Symbols {
			s := &f.Symbols[j]
			refs := counts[s.key] - defs[s.key]
			if refs < 0 || len(s.key) < 3 {
				// one- and two-letter names match too much unrelated text to rank on
				refs = 0
			}
			s.Refs = refs
			f.Score += refs
		}
		sort.SliceStable(f.Symbols, func(a, b int) bool {
			if f.Symbols[a].Refs != f.Symbols[b].Refs {
				return f.Symbols[a].Refs > f.Symbols[b].Refs
			}
			return f.Symbols[a].Line < f.Symbols[b].Line
		})
	}
	sort.SliceStable(files, func(a, b int) bool {
		if files[a].Score != files[b].Score {
			return files[a].Score > files[b].Score
		}
		return files[a].Path < files[b].Path
	})
	return Map{Files: files, TotalFiles: len(paths)}, nil
}

// Limit trims the map to the top maxFiles files and perFile symbols each.
func (m Map) Limit(maxFiles, perFile int) Map {
	out := Map{TotalFiles: m.TotalFiles}
	for i, f := range m.Files {
		if maxFiles > 0 && i >= maxFiles {
			break
		}
		if perFile > 0 && len(f.Symbols) > perFile {
			f.Symbols = f.Symbols[:perFile]
		}
		out.Files = append(out.Files, f)
	}
	return out
}

func Render(w io.Writer, m Map) {
	fmt.Fprintf(w, "repomap: %d of %d files shown, ranked by references\n", len(m.Files), m.TotalFiles)
	for _, f := range m.Files {
		fmt.Fprintf(w, "\n%s (refs %d)\n", f.Path, f.Score)
		width := 0
		for _, s := range f.Symbols {
			if n := len(s.Name); n > width {
				width = n
			}
		}
		if width > 40 {
			width = 40
		}
		for _, s := range f.Symbols {
			fmt.Fprintf(w, "  %-6s %-*s  L%-5d %d\n", s.Kind, width, s.Name, s.Line, s.Refs)
		}
	}
}
