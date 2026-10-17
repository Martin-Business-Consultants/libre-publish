package cms

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"
)

// Version is this build's: set from the release tag (make dist VERSION=…),
// "dev" otherwise. The API it serves is frozen whatever the version.
var Version = "dev"

// Config is what an install is started with; everything else lives in the
// database.
type Config struct {
	DataDir string // the database, uploaded files, the secret key
	Addr    string
	// The CMS's own address, which asset URLs start with (APP_HOST).
	BaseURL string
	// SITE_KEY: the tenant name webhooks carry.
	SiteKey string
	// Requests a minute per token across /api/v1; 0 for none.
	DeliveryRateLimit int
	// TrustProxy reads the client's address from X-Forwarded-For, as it
	// must behind a proxy and mustn't when facing the internet directly
	// (anyone could claim any address, and dodge the rate limits).
	TrustProxy bool
	Logger     *slog.Logger
}

// App is one install: one site, one database, one process.
type App struct {
	Config
	Store   *Store
	Secrets *Secrets
	Hooks   *Webhooks
	Deploys *Deploys
	Plugins *PluginHost
	Admin   http.Handler

	limiter *rateLimiter
	stop    chan struct{}
	once    sync.Once
}

func NewApp(cfg Config) (*App, error) {
	if cfg.Logger == nil {
		cfg.Logger = slog.New(slog.NewTextHandler(os.Stderr, nil))
	}
	if cfg.DeliveryRateLimit == 0 {
		cfg.DeliveryRateLimit = 1200
	}
	if cfg.DeliveryRateLimit < 0 {
		cfg.DeliveryRateLimit = 0
	}
	if err := os.MkdirAll(filepath.Join(cfg.DataDir, "storage"), 0o755); err != nil {
		return nil, err
	}
	store, err := OpenStore(filepath.Join(cfg.DataDir, "cms.sqlite3"))
	if err != nil {
		return nil, err
	}
	secrets, err := LoadSecrets(cfg.DataDir)
	if err != nil {
		return nil, err
	}
	a := &App{Config: cfg, Store: store, Secrets: secrets, stop: make(chan struct{})}
	a.limiter = newRateLimiter(cfg.DeliveryRateLimit)
	a.Hooks = &Webhooks{app: a}
	a.Deploys = &Deploys{app: a}
	a.Plugins = &PluginHost{app: a}
	if err := a.seed(); err != nil {
		return nil, fmt.Errorf("seed: %w", err)
	}
	if err := a.Plugins.LoadAll(); err != nil {
		a.Logger.Warn("plugins", "err", err)
	}
	go a.scheduler()
	return a, nil
}

func (a *App) Close() {
	a.once.Do(func() { close(a.stop) })
	a.Plugins.Close()
	a.Store.Close()
}

// ---- request context -----------------------------------------------------

// Ctx is one request: who's asking, and how to answer.
type Ctx struct {
	App   *App
	W     http.ResponseWriter
	R     *http.Request
	Actor *Actor

	// The agent envelope's summary and next steps, when a handler has them.
	Summary string
	Crumbs  []Crumb
	// Delivery answers carry an ETag and honor If-None-Match.
	etag     bool
	etagFrom string
}

type Crumb struct {
	Description string `json:"description"`
	Command     string `json:"command"`
}

func crumb(desc, cmd string) Crumb { return Crumb{desc, cmd} }

type HandlerFunc func(*Ctx) error

// Error is every /api error, one shape: {"error": code, "message": …}.
type Error struct {
	Status     int
	Code       string
	Message    string
	Errors     map[string][]string
	Capability string
	Extra      map[string]any
}

func (e *Error) Error() string { return e.Code + ": " + e.Message }

func errBadRequest(msg string) *Error { return &Error{Status: 400, Code: "bad_request", Message: msg} }
func errNotFound(msg string) *Error   { return &Error{Status: 404, Code: "not_found", Message: msg} }
func errConflict(msg string) *Error   { return &Error{Status: 409, Code: "conflict", Message: msg} }
func errForbidden(capability string) *Error {
	return &Error{Status: 403, Code: "forbidden", Message: "Your role doesn't grant " + capability + ".", Capability: capability}
}

// Invalid collects per-field problems into a 422.
type Invalid map[string][]string

func (v Invalid) Add(field, msg string) { v[field] = append(v[field], msg) }
func (v Invalid) Err() error {
	if len(v) == 0 {
		return nil
	}
	return &Error{Status: 422, Code: "invalid", Message: "Validation failed", Errors: v}
}

func (c *Ctx) fail(err error) {
	var e *Error
	switch {
	case errors.As(err, &e):
	case errors.Is(err, ErrNotFound):
		e = errNotFound("Couldn't find that.")
	default:
		c.App.Logger.Error("request", "path", c.R.URL.Path, "err", err)
		e = &Error{Status: 500, Code: "internal_error", Message: "Something went wrong on our side."}
	}
	body := map[string]any{"error": e.Code}
	if e.Message != "" {
		body["message"] = e.Message
	}
	if e.Errors != nil {
		body["errors"] = e.Errors
	}
	if e.Capability != "" {
		body["capability"] = e.Capability
	}
	for k, v := range e.Extra {
		body[k] = v
	}
	c.JSON(e.Status, body)
}

func (c *Ctx) envelope() bool {
	if c.R.Header.Get("X-Agent-Envelope") == "1" {
		return true
	}
	switch strings.ToLower(c.R.URL.Query().Get("envelope")) {
	case "1", "true", "yes":
		return true
	}
	return false
}

// JSON answers with v, in the agent envelope when the caller asked for it.
func (c *Ctx) JSON(status int, v any) error {
	if c.envelope() {
		ok := status < 400
		summary := c.Summary
		if summary == "" {
			summary = defaultSummary(c.R, status, v)
		}
		crumbs := c.Crumbs
		if crumbs == nil || !ok {
			crumbs = []Crumb{}
		}
		v = map[string]any{"status": map[bool]string{true: "ok", false: "error"}[ok], "summary": summary, "data": v, "breadcrumbs": crumbs}
	}
	body, err := json.Marshal(v)
	if err != nil {
		return err
	}
	h := c.W.Header()
	h.Set("Content-Type", "application/json; charset=utf-8")
	if c.etag && status == 200 {
		src := c.etagFrom
		if src == "" {
			src = string(body)
		}
		sum := sha256.Sum256([]byte(src + "|" + c.R.Header.Get("X-Agent-Envelope")))
		tag := `W/"` + hex.EncodeToString(sum[:16]) + `"`
		h.Set("ETag", tag)
		if match := c.R.Header.Get("If-None-Match"); match != "" && strings.Contains(match, tag) {
			c.W.WriteHeader(http.StatusNotModified)
			return nil
		}
	}
	c.W.WriteHeader(status)
	_, err = c.W.Write(body)
	return err
}

func defaultSummary(r *http.Request, status int, v any) string {
	if status >= 400 {
		if m, ok := v.(map[string]any); ok {
			if msg, ok := m["message"].(string); ok {
				return msg
			}
			return fmt.Sprint(m["error"])
		}
		return http.StatusText(status)
	}
	return r.Method + " " + r.URL.Path + " — " + http.StatusText(status) + "."
}

func (c *Ctx) NoContent() error {
	c.W.WriteHeader(http.StatusNoContent)
	return nil
}

// Body decodes the request's JSON into v; a body that isn't JSON is a 400.
func (c *Ctx) Body(v any) error {
	data, err := io.ReadAll(io.LimitReader(c.R.Body, 32<<20))
	if err != nil {
		return errBadRequest("Couldn't read the request body.")
	}
	if len(strings.TrimSpace(string(data))) == 0 {
		return errBadRequest("The request needs a JSON body.")
	}
	if err := json.Unmarshal(data, v); err != nil {
		return errBadRequest("The body isn't JSON: " + err.Error())
	}
	return nil
}

// Wrapped decodes {"<key>": {…}} into a map, 400 when the key is missing,
// as Rails' params.require did.
func (c *Ctx) Wrapped(key string) (map[string]any, error) {
	var body map[string]any
	if err := c.Body(&body); err != nil {
		return nil, err
	}
	inner, ok := body[key].(map[string]any)
	if !ok {
		return nil, errBadRequest("param is missing or the value is empty: " + key)
	}
	return inner, nil
}

func (c *Ctx) Query(key string) string { return c.R.URL.Query().Get(key) }

func (c *Ctx) Param(key string) string { return c.R.PathValue(key) }

func (c *Ctx) IntParam(key string) (int64, error) {
	n, err := strconv.ParseInt(c.R.PathValue(key), 10, 64)
	if err != nil {
		return 0, errNotFound("Couldn't find " + key + " " + c.R.PathValue(key) + ".")
	}
	return n, nil
}

func (c *Ctx) truthy(key string) bool {
	switch strings.ToLower(c.Query(key)) {
	case "1", "true", "yes":
		return true
	}
	return false
}

// paging reads ?page= and ?per= with the given default and cap.
func (c *Ctx) paging(def, max int) (page, per int) {
	page, _ = strconv.Atoi(c.Query("page"))
	per, _ = strconv.Atoi(c.Query("per"))
	if page < 1 {
		page = 1
	}
	if page > 100000 {
		page = 100000
	}
	if per < 1 {
		per = def
	}
	if per > max {
		per = max
	}
	return
}

// Need refuses unless the caller's role grants capability.
func (c *Ctx) Need(capability string) error {
	if c.Actor == nil {
		return &Error{Status: 401, Code: "unauthorized", Message: "Sign in, or send Authorization: Bearer <token>."}
	}
	if !c.Actor.Can(capability) {
		return errForbidden(capability)
	}
	return nil
}

func (c *Ctx) can(capability string) bool { return c.Actor != nil && c.Actor.Can(capability) }

func (c *Ctx) ip() string {
	if fwd := c.R.Header.Get("X-Forwarded-For"); fwd != "" && c.App.TrustProxy {
		return strings.TrimSpace(strings.Split(fwd, ",")[0])
	}
	host := c.R.RemoteAddr
	if i := strings.LastIndex(host, ":"); i > 0 {
		host = host[:i]
	}
	return strings.Trim(host, "[]")
}

// ---- routing -------------------------------------------------------------

type route struct {
	auth bool // false: open to anyone (device login, public posts)
}

func (a *App) handle(mux *http.ServeMux, pattern string, h HandlerFunc, opts ...func(*route)) {
	rt := route{auth: true}
	for _, o := range opts {
		o(&rt)
	}
	mux.HandleFunc(pattern, func(w http.ResponseWriter, r *http.Request) {
		c := &Ctx{App: a, W: w, R: r}
		defer func() {
			if rec := recover(); rec != nil {
				c.fail(fmt.Errorf("panic: %v", rec))
			}
		}()
		actor, err := a.authenticate(c)
		if err != nil && rt.auth {
			c.fail(err)
			return
		}
		c.Actor = actor
		if rt.auth && actor == nil {
			c.fail(&Error{Status: 401, Code: "unauthorized", Message: "Sign in, or send Authorization: Bearer <token>."})
			return
		}
		if err := h(c); err != nil {
			c.fail(err)
		}
	})
}

func open(r *route) { r.auth = false }

// Handler is the whole install: the API, the admin, the files.
func (a *App) Handler() http.Handler {
	mux := http.NewServeMux()
	a.routes(mux)
	a.deliveryRoutes(mux)

	mux.Handle("GET /files/", http.HandlerFunc(a.serveFile))
	mux.HandleFunc("GET /up", func(w http.ResponseWriter, r *http.Request) {
		if err := a.Store.DB.PingContext(r.Context()); err != nil {
			http.Error(w, "down", 500)
			return
		}
		w.Write([]byte("ok"))
	})
	mux.HandleFunc("GET /robots.txt", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/plain; charset=utf-8")
		w.Write([]byte("User-agent: *\nDisallow: /\n"))
	})
	if a.Admin != nil {
		mux.Handle("/cms/", a.Admin)
	}
	// "/" is blank: a headless install's own address shows nothing, not even
	// where the admin is. Any other /api path is the API's 404, in its shape.
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if strings.HasPrefix(r.URL.Path, "/api/") || r.URL.Path == "/api" {
			c := &Ctx{App: a, W: w, R: r}
			c.fail(errNotFound("No route matches " + r.Method + " " + r.URL.Path + "."))
			return
		}
		if r.URL.Path == "/" {
			w.Header().Set("Content-Type", "text/html; charset=utf-8")
			w.Write([]byte("<!doctype html><title></title>"))
			return
		}
		http.NotFound(w, r)
	})
	return a.cors(securityHeaders(mux))
}

func securityHeaders(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		h := w.Header()
		h.Set("X-Content-Type-Options", "nosniff")
		h.Set("Referrer-Policy", "strict-origin-when-cross-origin")
		if strings.HasPrefix(r.URL.Path, "/cms") {
			h.Set("X-Frame-Options", "DENY")
		}
		next.ServeHTTP(w, r)
	})
}

// CORS for what a site's browser calls: the delivery API and public posts,
// from the origins in Settings › General (and the public site's own).
func (a *App) cors(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		origin := r.Header.Get("Origin")
		if origin != "" && (strings.HasPrefix(r.URL.Path, "/api/v1/") || strings.HasPrefix(r.URL.Path, "/api/public/") || r.URL.Path == "/api/quote_requests") && a.originAllowed(origin) {
			h := w.Header()
			h.Set("Access-Control-Allow-Origin", origin)
			h.Set("Vary", "Origin")
			h.Set("Access-Control-Allow-Headers", "Authorization, Content-Type, If-None-Match")
			h.Set("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
			h.Set("Access-Control-Expose-Headers", "ETag, Cache-Tag")
			if r.Method == http.MethodOptions {
				w.WriteHeader(http.StatusNoContent)
				return
			}
		}
		next.ServeHTTP(w, r)
	})
}

func (a *App) originAllowed(origin string) bool {
	g := a.general()
	allowed := []string{strings.TrimRight(str(g["site_base_url"]), "/")}
	for _, o := range strings.FieldsFunc(str(g["cors_origins"]), func(r rune) bool { return r == ',' || r == '\n' || r == ' ' }) {
		allowed = append(allowed, strings.TrimRight(strings.TrimSpace(o), "/"))
	}
	for _, o := range allowed {
		if o != "" && strings.EqualFold(o, origin) {
			return true
		}
	}
	return false
}

// ---- rate limit ----------------------------------------------------------

type rateLimiter struct {
	mu     sync.Mutex
	limit  int
	window map[string]*bucket
}

type bucket struct {
	start time.Time
	count int
}

func newRateLimiter(limit int) *rateLimiter {
	return &rateLimiter{limit: limit, window: map[string]*bucket{}}
}

// allow counts one request for key; the seconds to wait when it's over.
func (l *rateLimiter) allow(key string) (bool, int) {
	if l.limit <= 0 {
		return true, 0
	}
	l.mu.Lock()
	defer l.mu.Unlock()
	now := time.Now()
	b := l.window[key]
	if b == nil || now.Sub(b.start) >= time.Minute {
		b = &bucket{start: now}
		l.window[key] = b
		if len(l.window) > 10000 {
			for k, v := range l.window {
				if now.Sub(v.start) >= time.Minute {
					delete(l.window, k)
				}
			}
		}
	}
	b.count++
	if b.count > l.limit {
		return false, int(time.Minute.Seconds()-now.Sub(b.start).Seconds()) + 1
	}
	return true, 0
}

// ---- small helpers -------------------------------------------------------

func str(v any) string {
	switch x := v.(type) {
	case nil:
		return ""
	case string:
		return x
	case float64:
		return strconv.FormatFloat(x, 'f', -1, 64)
	default:
		return fmt.Sprint(x)
	}
}

func boolOf(v any) bool {
	switch x := v.(type) {
	case bool:
		return x
	case string:
		return x == "1" || x == "true" || x == "yes" || x == "on"
	case float64:
		return x != 0
	}
	return false
}

// intOf reads an id from JSON: a number or a numeric string; ok false for
// null or "".
func intOf(v any) (int64, bool) {
	switch x := v.(type) {
	case float64:
		return int64(x), true
	case string:
		n, err := strconv.ParseInt(strings.TrimSpace(x), 10, 64)
		return n, err == nil
	case json.Number:
		n, err := x.Int64()
		return n, err == nil
	}
	return 0, false
}

func has(m map[string]any, key string) bool {
	_, ok := m[key]
	return ok
}

func firstOf(m map[string]any, keys ...string) any {
	for _, k := range keys {
		if v, ok := m[k]; ok && v != nil && v != "" {
			return v
		}
	}
	return nil
}
