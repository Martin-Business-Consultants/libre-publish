package cms

import (
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"sync"
	"testing"
	"time"
)

func TestCanonicalJSON(t *testing.T) {
	t.Parallel()
	// Keys sorted at every depth, compact, encoding/json's default escaping
	// (<, > and & and the line separator as escapes), numbers as written:
	// the same bytes however the value was built.
	ls := string(rune(0x2028))
	a := O("b", 1, "a", map[string]any{"z": []any{2.5, "x<y&z", ls}, "y": nil}, "c", 1e21)
	var b any
	if err := json.Unmarshal([]byte(`{"c":1e21,"a":{"y":null,"z":[2.5,"x<y&z","`+ls+`"]},"b":1}`), &b); err != nil {
		t.Fatal(err)
	}
	esc := func(code string) string { return `\` + "u" + code }
	want := `{"a":{"y":null,"z":[2.5,"x` + esc("003c") + `y` + esc("0026") + `z","` + esc("2028") + `"]},"b":1,"c":1e+21}`
	for _, v := range []any{a, b} {
		got, err := canonicalJSON(v)
		if err != nil || string(got) != want {
			t.Fatalf("canonical:\n got %s\nwant %s (%v)", got, want, err)
		}
	}
}

func TestSchemaDigestMoves(t *testing.T) {
	t.Parallel()
	s := newSiteWith(t, Config{NoDefaultPlugins: true, SchemaDebounce: 10 * time.Millisecond})
	var mu sync.Mutex
	var got []map[string]any
	recv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		b, _ := io.ReadAll(r.Body)
		var m map[string]any
		if json.Unmarshal(b, &m) == nil {
			mu.Lock()
			got = append(got, m)
			mu.Unlock()
		}
	}))
	t.Cleanup(recv.Close)
	s.must(201, s.do(s.admin, "POST", "/api/webhooks", map[string]any{"webhook": map[string]any{"name": "schema", "url": recv.URL, "events": []any{schemaChangedEvent}}}))

	before := s.must(200, s.do(s.prod, "GET", "/api/v1/site", nil)).Header.Get(schemaDigestHeader)
	// Content doesn't move it; a block type does.
	s.must(201, s.do(s.admin, "POST", "/api/pages", map[string]any{"page": map[string]any{"slug": "home", "title": "Home", "status": "published"}}))
	if now := s.must(200, s.do(s.prod, "GET", "/api/v1/site", nil)).Header.Get(schemaDigestHeader); now != before {
		t.Fatalf("a page without fields moved the digest: %s -> %s", before, now)
	}
	s.must(201, s.do(s.admin, "POST", "/api/block_types", map[string]any{"block_type": map[string]any{"slug": "banner", "label": "Banner",
		"fields": []any{map[string]any{"name": "text", "label": "Text", "type": "string"}}}}))
	r := s.must(200, s.do(s.prod, "GET", "/api/v1/schema", nil))
	after := r.Header.Get(schemaDigestHeader)
	if after == before || dig(r.Body, "meta", "schema_digest") != after || dig(r.Body, "data", "blocks", "banner") == nil {
		t.Fatalf("digest %s -> %s: %s", before, after, r.Raw)
	}
	deadline := time.Now().Add(5 * time.Second)
	for {
		mu.Lock()
		n := len(got)
		var last map[string]any
		if n > 0 {
			last = got[n-1]
		}
		mu.Unlock()
		if last != nil && dig(last, "data", "schema_digest") == after {
			break
		}
		if time.Now().After(deadline) {
			t.Fatalf("no schema.changed naming %s: %v", after, got)
		}
		time.Sleep(10 * time.Millisecond)
	}
}
