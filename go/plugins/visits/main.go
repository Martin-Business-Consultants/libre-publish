// visits is an example Libre Publish plugin, written in Go and compiled to
// WebAssembly. It counts page views a site reports, and remembers when each
// page was last published. It asks for its own storage and to read content —
// nothing else — and can't reach anything it didn't ask for.
//
//	GOOS=wasip1 GOARCH=wasm go build -buildmode=c-shared -o visits.wasm .
package main

import (
	"encoding/json"
	"strconv"
	"strings"

	"github.com/extism/go-pdk"
)

// The host's capabilities, as imports. A plugin that wasn't granted one
// gets {"error": …} back from it.
//
//go:wasmimport extism:host/user lp_kv_get
func lpKvGet(uint64) uint64

//go:wasmimport extism:host/user lp_kv_set
func lpKvSet(uint64) uint64

//go:wasmimport extism:host/user lp_kv_list
func lpKvList(uint64) uint64

//go:wasmimport extism:host/user lp_content
func lpContent(uint64) uint64

//go:wasmimport extism:host/user lp_log
func lpLog(uint64) uint64

func call(fn func(uint64) uint64, in string) []byte {
	mem := pdk.AllocateString(in)
	defer mem.Free()
	out := pdk.FindMemory(fn(mem.Offset()))
	defer out.Free()
	return out.ReadBytes()
}

func kvGet(key string) (string, bool) {
	var r struct {
		Found bool   `json:"found"`
		Value string `json:"value"`
	}
	json.Unmarshal(call(lpKvGet, key), &r)
	return r.Value, r.Found
}

func kvSet(key, value string) {
	b, _ := json.Marshal(map[string]string{"key": key, "value": value})
	call(lpKvSet, string(b))
}

//go:wasmexport manifest
func manifest() int32 {
	pdk.OutputJSON(map[string]any{
		"key":         "visits",
		"name":        "Visits",
		"version":     "1.0.0",
		"description": "Counts the page views a site reports, and when each page was last published.",
		"permissions": map[string]any{"storage": true, "content:read": true},
		"hooks":       []string{"page.published"},
		"routes": []map[string]any{
			{"method": "POST", "path": "/hit", "export": "hit", "public": true},
			{"method": "GET", "path": "/stats", "export": "stats"},
		},
		"admin": map[string]any{"screens": []map[string]any{{
			"id": "stats", "title": "Visits", "source": "/stats",
			"table": map[string]any{"rows": "pages", "columns": []map[string]string{
				{"key": "path", "label": "Page"}, {"key": "views", "label": "Views"}, {"key": "published_at", "label": "Last published"},
			}},
		}}},
	})
	return 0
}

type request struct {
	Method string `json:"method"`
	Path   string `json:"path"`
	Body   string `json:"body"`
}

type response struct {
	Status  int               `json:"status"`
	Headers map[string]string `json:"headers,omitempty"`
	Body    string            `json:"body"`
}

func reply(status int, v any) int32 {
	b, _ := json.Marshal(v)
	pdk.OutputJSON(response{Status: status, Headers: map[string]string{"Content-Type": "application/json"}, Body: string(b)})
	return 0
}

// hit counts one view of a page that exists and is live.
//
//go:wasmexport hit
func hit() int32 {
	var req request
	if err := pdk.InputJSON(&req); err != nil {
		return reply(400, map[string]string{"error": "bad_request"})
	}
	var body struct {
		Path string `json:"path"`
	}
	json.Unmarshal([]byte(req.Body), &body)
	path := strings.Trim(body.Path, "/")
	if path == "" {
		path = "home"
	}
	q, _ := json.Marshal(map[string]string{"page": path})
	var page map[string]any
	json.Unmarshal(call(lpContent, string(q)), &page)
	if _, missing := page["error"]; missing {
		return reply(404, map[string]string{"error": "not_found"})
	}
	n, _ := kvGet("views:" + path)
	count, _ := strconv.Atoi(n)
	kvSet("views:"+path, strconv.Itoa(count+1))
	return reply(200, map[string]any{"path": path, "views": count + 1})
}

//go:wasmexport stats
func stats() int32 {
	var list struct {
		Keys []string `json:"keys"`
	}
	json.Unmarshal(call(lpKvList, "views:"), &list)
	pages := []map[string]any{}
	for _, k := range list.Keys {
		path := strings.TrimPrefix(k, "views:")
		v, _ := kvGet(k)
		n, _ := strconv.Atoi(v)
		at, _ := kvGet("published:" + path)
		pages = append(pages, map[string]any{"path": path, "views": n, "published_at": at})
	}
	return reply(200, map[string]any{"pages": pages})
}

// on_event hears what it hooked: page.published.
//
//go:wasmexport on_event
func onEvent() int32 {
	var ev struct {
		Event string `json:"event"`
		Data  struct {
			Path        string `json:"path"`
			PublishedAt string `json:"published_at"`
		} `json:"data"`
	}
	if err := pdk.InputJSON(&ev); err != nil {
		return 1
	}
	kvSet("published:"+ev.Data.Path, ev.Data.PublishedAt)
	call(lpLog, "published "+ev.Data.Path)
	return 0
}

func main() {}
