// Package admin is the admin: a Svelte app (ui/), built into dist/ and
// embedded in the binary. It works the same /api the CLI and agents use,
// signed in by a session cookie instead of a token.
//
// dist/ is committed, so `go build` and `go install` need no Node; after
// changing ui/, `make ui` rebuilds it.
package admin

import (
	"embed"
	"io/fs"
	"net/http"
	"path"
	"strings"
)

//go:embed all:dist
var dist embed.FS

const csp = "default-src 'self'; img-src 'self' data: blob: https:; style-src 'self' 'unsafe-inline'; script-src 'self' 'unsafe-inline'; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'"

func Handler() http.Handler {
	files, _ := fs.Sub(dist, "dist")
	index, _ := fs.ReadFile(files, "index.html")
	assets := http.FileServer(http.FS(files))
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		rel := strings.TrimPrefix(path.Clean(r.URL.Path), "/cms")
		h := w.Header()
		h.Set("Content-Security-Policy", csp)
		// Hashed build assets never change under their name.
		if strings.HasPrefix(rel, "/assets/") {
			h.Set("Cache-Control", "public, max-age=31536000, immutable")
			r2 := r.Clone(r.Context())
			r2.URL.Path = rel
			assets.ServeHTTP(w, r2)
			return
		}
		if rel != "/" && rel != "" && rel != "/index.html" {
			http.Redirect(w, r, "/cms/", http.StatusFound)
			return
		}
		h.Set("Content-Type", "text/html; charset=utf-8")
		h.Set("Cache-Control", "no-cache")
		w.Write(index)
	})
}
