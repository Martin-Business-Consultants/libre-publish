package cms

import (
	"os"
	"os/exec"
	"path/filepath"
	"testing"
	"time"
)

// buildVisits compiles the example plugin (plugins/visits) to wasm.
func buildVisits(t *testing.T) []byte {
	t.Helper()
	out := filepath.Join(t.TempDir(), "visits.wasm")
	cmd := exec.Command("go", "build", "-buildmode=c-shared", "-o", out, ".")
	cmd.Dir = filepath.Join("..", "..", "plugins", "visits")
	cmd.Env = append(os.Environ(), "GOOS=wasip1", "GOARCH=wasm")
	if b, err := cmd.CombinedOutput(); err != nil {
		t.Skipf("couldn't build the example plugin: %v\n%s", err, b)
	}
	wasm, err := os.ReadFile(out)
	if err != nil {
		t.Fatal(err)
	}
	return wasm
}

func TestWasmPlugin(t *testing.T) {
	wasm := buildVisits(t)
	s := newSite(t)
	s.must(201, s.do(s.admin, "POST", "/api/pages", map[string]any{"page": map[string]any{"slug": "about", "title": "About", "status": "published"}}))

	// Installing reads what it asks for, and leaves it off.
	s.must(403, s.do(s.agent, "POST", "/api/plugins", wasm, "Content-Type", "application/wasm"))
	r := s.must(201, s.do(s.admin, "POST", "/api/plugins", wasm, "Content-Type", "application/wasm"))
	if dig(r.Body, "plugin", "enabled") != false || dig(r.Body, "plugin", "requested", "storage") != true || dig(r.Body, "plugin", "granted", "storage") != false {
		t.Fatalf("install: %s", r.Raw)
	}
	s.must(404, s.do("", "POST", "/api/x/visits/hit", map[string]any{"body": "{}"}))

	// Granting more than it asked for grants only what it asked for.
	r = s.must(200, s.do(s.admin, "PATCH", "/api/plugins/visits", map[string]any{"plugin": map[string]any{
		"granted": map[string]any{"storage": true, "content:read": true, "http": []any{"evil.example"}}, "enabled": true}}))
	if len(dig(r.Body, "plugin", "granted", "http").([]any)) != 0 || dig(r.Body, "plugin", "enabled") != true {
		t.Fatalf("configure: %s", r.Raw)
	}

	// Its public route, its storage, its content reads.
	for i := 1; i <= 2; i++ {
		r = s.must(200, s.do("", "POST", "/api/x/visits/hit", map[string]any{"path": "/about"}))
		if r.Body["views"] != float64(i) {
			t.Fatalf("hit %d: %s", i, r.Raw)
		}
	}
	s.must(404, s.do("", "POST", "/api/x/visits/hit", map[string]any{"path": "/nope"}))
	s.must(401, s.do("", "GET", "/api/x/visits/stats", nil))
	r = s.must(200, s.do(s.admin, "GET", "/api/x/visits/stats", nil))
	if dig(r.Body, "pages", 0, "path") != "about" || dig(r.Body, "pages", 0, "views") != float64(2) {
		t.Fatalf("stats: %s", r.Raw)
	}

	// It hears the events it hooked.
	s.must(201, s.do(s.admin, "POST", "/api/pages", map[string]any{"page": map[string]any{"slug": "news", "title": "News", "status": "published"}}))
	deadline := time.Now().Add(5 * time.Second)
	for {
		var v []byte
		s.app.Store.DB.QueryRow(`SELECT value FROM plugin_kv WHERE plugin_key = 'visits' AND key = 'published:news'`).Scan(&v)
		if len(v) > 0 {
			break
		}
		if time.Now().After(deadline) {
			t.Fatal("the plugin never heard page.published")
		}
		time.Sleep(50 * time.Millisecond)
	}

	// Without storage granted, its storage calls are refused, not crashes.
	s.must(200, s.do(s.admin, "PATCH", "/api/plugins/visits", map[string]any{"plugin": map[string]any{"granted": map[string]any{"content:read": true}}}))
	r = s.must(200, s.do("", "POST", "/api/x/visits/hit", map[string]any{"path": "/about"}))
	if r.Body["views"] != float64(1) {
		t.Fatalf("storage still reachable: %s", r.Raw)
	}
}
