package deploy

import (
	"context"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"sync"
	"testing"
)

type memSettings struct {
	mu   sync.Mutex
	data map[string]map[string]any
}

func (m *memSettings) Setting(_ context.Context, key string) (map[string]any, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if v, ok := m.data[key]; ok {
		return v, nil
	}
	return map[string]any{}, nil
}

func (m *memSettings) ReplaceSetting(_ context.Context, key string, data map[string]any) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.data[key] = data
	return nil
}

func TestTriggerByRenderMode(t *testing.T) {
	t.Parallel()
	var mu sync.Mutex
	hits := map[string]int{}
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = io.Copy(io.Discard, r.Body)
		mu.Lock()
		hits[r.URL.Path]++
		mu.Unlock()
	}))
	t.Cleanup(srv.Close)

	for _, tc := range []struct {
		render, kind   string
		purges, builds int
	}{
		{"static", "build", 0, 1},
		{"server", "purge", 1, 0},
		{"hybrid", "purge+build", 1, 1},
	} {
		t.Run(tc.render, func(t *testing.T) {
			t.Parallel()
			settings := &memSettings{data: map[string]map[string]any{
				"deploy":   {"hook_url": srv.URL + "/build/" + tc.render},
				"frontend": {"render": tc.render, "webhook_url": srv.URL + "/purge/" + tc.render, "secret": "s"},
			}}
			d := New(settings, slog.New(slog.DiscardHandler), func(context.Context, string, func(context.Context)) bool { return false })
			status, err := d.Trigger(t.Context(), "publish")
			if err != nil || status["kind"] != tc.kind || status["status"] != "success" {
				t.Fatalf("status %v, err %v", status, err)
			}
			mu.Lock()
			defer mu.Unlock()
			if hits["/purge/"+tc.render] != tc.purges || hits["/build/"+tc.render] != tc.builds {
				t.Fatalf("purges %d, builds %d", hits["/purge/"+tc.render], hits["/build/"+tc.render])
			}
		})
	}
}
