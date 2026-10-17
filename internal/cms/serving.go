package cms

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"strings"
	"sync"
	"sync/atomic"
	"time"
)

// Server is what `librepublish serve` runs: the install's App behind a
// handler that can take it down and bring up another without a restart.
// Applying an imported backup does that (Replace): every request but /up
// is answered 503 while the App is closed, its data directory swapped, and
// a new App opened on what's there now. The App is replaced whole (its
// database, key, plugins, scheduler), so nothing has to be reopened in
// place, and an App that never runs behind a Server (the one-off commands,
// most tests) is unchanged.
type Server struct {
	cfg Config

	app     atomic.Pointer[App]
	handler atomic.Pointer[http.Handler]
	// While set, requests are answered 503; inflight counts those past
	// that check, so Replace can wait for them.
	maintenance atomic.Bool
	inflight    atomic.Int64

	mu  sync.Mutex      // one Replace at a time, and not during Close
	ctx context.Context //nolint:containedctx // Start's, which each new App is started with
	// drain is how long Replace waits for requests in flight.
	drain time.Duration
}

// NewServer opens the install (NewApp) behind a Server.
func NewServer(cfg Config) (*Server, error) {
	if cfg.Logger == nil {
		cfg.Logger = slog.New(slog.NewTextHandler(os.Stderr, nil))
	}
	s := &Server{cfg: cfg, drain: 30 * time.Second, ctx: context.Background()}
	app, err := s.open()
	if err != nil {
		return nil, err
	}
	s.app.Store(app)
	h := app.Handler()
	s.handler.Store(&h)
	return s, nil
}

func (s *Server) open() (*App, error) {
	app, err := NewApp(s.cfg)
	if err != nil {
		return nil, err
	}
	app.server = s
	return app, nil
}

// Start starts the App (Start); later ones are started with the same ctx.
func (s *Server) Start(ctx context.Context) error {
	s.mu.Lock()
	s.ctx = ctx
	s.mu.Unlock()
	return s.app.Load().Start(ctx)
}

// App is the App serving now.
func (s *Server) App() *App { return s.app.Load() }

// Close closes the App serving now.
func (s *Server) Close() error {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.app.Load().Close()
}

// Handler serves the App, or 503 while it's being replaced.
func (s *Server) Handler() http.Handler { return s }

// ServeHTTP counts the request in first and only then checks for
// maintenance, so Replace, which sets maintenance and then waits for the
// count, never closes the App under a request it let through.
func (s *Server) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	s.inflight.Add(1)
	defer s.inflight.Add(-1)
	if s.maintenance.Load() {
		maintenancePage(w, r)
		return
	}
	(*s.handler.Load()).ServeHTTP(w, r)
}

// maintenancePage is every answer while the site is being replaced: /up
// stays up (a health check mustn't restart the process mid-swap), the API
// says so in its own shape, anything else is a page that reloads itself.
func maintenancePage(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path == "/up" {
		w.Write([]byte("maintenance"))
		return
	}
	w.Header().Set("Retry-After", "10")
	w.Header().Set("Cache-Control", "no-store")
	if strings.HasPrefix(r.URL.Path, "/api") {
		w.Header().Set("Content-Type", "application/json; charset=utf-8")
		w.WriteHeader(http.StatusServiceUnavailable)
		w.Write([]byte(`{"error":"maintenance","message":"The site is being replaced by an imported backup. Try again in a moment."}`))
		return
	}
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.WriteHeader(http.StatusServiceUnavailable)
	w.Write([]byte(`<!doctype html><meta charset="utf-8"><meta http-equiv="refresh" content="10"><title>Back in a moment</title>` +
		`<p style="font:16px system-ui;margin:4rem auto;max-width:32rem">The site is being replaced by an imported backup. This page reloads itself.</p>`))
}

// errBusy is a Replace that gave up waiting for requests in flight.
var errBusy = errors.New("requests are still running (a download?): try again in a minute")

// Replace closes the App, runs apply (which changes the data directory
// under it), and opens a new App on the result, holding requests off with
// 503s throughout. It's called from a request (counted in flight, so the
// wait is for the others). When apply fails it must have changed nothing,
// and the App is reopened as it was. When the new App won't open, undo
// (what apply returned) puts the old data back and that's reopened.
func (s *Server) Replace(ctx context.Context, apply func() (undo func() error, err error)) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.maintenance.Store(true)
	defer s.maintenance.Store(false)
	if err := s.wait(ctx, 1); err != nil {
		return err
	}
	if err := s.app.Load().Close(); err != nil {
		s.cfg.Logger.Warn("replace: closing the app", "err", err)
	}
	undo, applyErr := apply()
	app, err := s.open()
	if err != nil && applyErr == nil && undo != nil {
		s.cfg.Logger.Error("replace: the new site won't open; putting the old one back", "err", err)
		if uerr := undo(); uerr != nil {
			err = errors.Join(err, fmt.Errorf("putting the old site back: %w", uerr))
		} else if app, err = s.open(); err == nil {
			applyErr = errors.New("the imported site wouldn't open, so the previous one was put back")
		}
	}
	if err != nil {
		// Nothing to serve: every request says so until an operator acts.
		var down http.Handler = http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			http.Error(w, "The site couldn't be reopened after an import; see the server's log.", http.StatusServiceUnavailable)
		})
		s.handler.Store(&down)
		return errors.Join(applyErr, err)
	}
	if err := app.Start(s.ctx); err != nil {
		s.cfg.Logger.Warn("replace: starting the app", "err", err)
	}
	s.app.Store(app)
	h := app.Handler()
	s.handler.Store(&h)
	return applyErr
}

// wait waits until at most n requests are in flight, for up to drain.
func (s *Server) wait(ctx context.Context, n int64) error {
	deadline := time.Now().Add(s.drain)
	tick := time.NewTicker(10 * time.Millisecond)
	defer tick.Stop()
	for s.inflight.Load() > n {
		if time.Now().After(deadline) {
			return errBusy
		}
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-tick.C:
		}
	}
	return nil
}
