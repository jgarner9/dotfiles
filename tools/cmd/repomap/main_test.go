package main

import (
	"bytes"
	"encoding/json"
	"flag"
	"os"
	"path/filepath"
	"testing"
)

var update = flag.Bool("update", false, "rewrite golden files")

func golden(t *testing.T, name string, got []byte) {
	t.Helper()
	path := filepath.Join("testdata", name)
	if *update {
		if err := os.WriteFile(path, got, 0o644); err != nil {
			t.Fatal(err)
		}
	}
	want, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read golden (run go test -update): %v", err)
	}
	if !bytes.Equal(got, want) {
		t.Errorf("%s mismatch\n--- got ---\n%s\n--- want ---\n%s", name, got, want)
	}
}

func TestTextGolden(t *testing.T) {
	m, err := Build("testdata/sample", false)
	if err != nil {
		t.Fatal(err)
	}
	var buf bytes.Buffer
	Render(&buf, m.Limit(0, 0))
	golden(t, "sample.golden", buf.Bytes())
}

func TestJSONGolden(t *testing.T) {
	m, err := Build("testdata/sample", false)
	if err != nil {
		t.Fatal(err)
	}
	out, err := json.MarshalIndent(m.Limit(2, 2), "", "  ")
	if err != nil {
		t.Fatal(err)
	}
	golden(t, "sample-limited.json.golden", append(out, '\n'))
}

func TestDeterministic(t *testing.T) {
	a, _ := Build("testdata/sample", false)
	b, _ := Build("testdata/sample", false)
	var x, y bytes.Buffer
	Render(&x, a)
	Render(&y, b)
	if !bytes.Equal(x.Bytes(), y.Bytes()) {
		t.Fatal("two runs over the same tree differ")
	}
}

func TestSkipsVendoredDirs(t *testing.T) {
	m, _ := Build("testdata/sample", false)
	for _, f := range m.Files {
		if filepath.Dir(f.Path) == "node_modules/x" {
			t.Fatalf("node_modules file listed: %s", f.Path)
		}
	}
}

func TestSymbolRules(t *testing.T) {
	cases := []struct {
		lang, line, name, kind string
	}{
		{"go", "func (m *Map) Limit(n int) Map {", "Map.Limit", "method"},
		{"go", "func (Map) Plain() {}", "Map.Plain", "method"},
		{"go", "func Build(root string) {", "Build", "fn"},
		{"go", "type Reader interface {", "Reader", "iface"},
		{"lua", "local function trim(s)", "trim", "fn"},
		{"lua", "function M.setup(opts)", "M.setup", "fn"},
		{"lua", "M.toggle = function()", "M.toggle", "fn"},
		{"python", "async def fetch(url):", "fetch", "fn"},
		{"js", "export default async function main() {", "main", "fn"},
		{"js", "export const add = (a, b) => a + b", "add", "fn"},
		{"rust", "pub(crate) async fn serve() {", "serve", "fn"},
		{"rust", "pub struct Config {", "Config", "type"},
		{"ruby", "  def self.call?", "call?", "fn"},
		{"shell", "cleanup() {", "cleanup", "fn"},
	}
	for _, c := range cases {
		syms := symbolsIn(c.lang, []byte(c.line+"\n"))
		if len(syms) != 1 || syms[0].Name != c.name || syms[0].Kind != c.kind {
			t.Errorf("%s %q: got %+v, want %s %s", c.lang, c.line, syms, c.kind, c.name)
		}
	}
}
