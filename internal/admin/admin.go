// Package admin is the admin: one HTML file, embedded in the binary, that
// works the same /api the CLI and agents use (signed in by a session cookie
// instead of a token).
package admin

import (
	_ "embed"
	"net/http"
)

//go:embed index.html
var page []byte

func Handler() http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/cms/" && r.URL.Path != "/cms/index.html" {
			http.Redirect(w, r, "/cms/", http.StatusFound)
			return
		}
		h := w.Header()
		h.Set("Content-Type", "text/html; charset=utf-8")
		h.Set("Cache-Control", "no-cache")
		h.Set("Content-Security-Policy", "default-src 'self'; img-src 'self' data: blob: https:; style-src 'self' 'unsafe-inline'; script-src 'self' 'unsafe-inline'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'")
		w.Write(page)
	})
}
