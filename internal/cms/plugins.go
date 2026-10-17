package cms

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"regexp"
	"slices"
	"strings"
	"sync"
	"time"

	extism "github.com/extism/go-sdk"
)

// Plugins are WebAssembly modules (Extism's ABI, so they can be written in
// Go, Rust, TypeScript, Python, …) that can do only what they declared and a
// person granted. Each one is a single .wasm file; installing it is
// uploading it, and loading it needs no restart.
//
// What a plugin can reach is the host's fixed set of capabilities:
//
//	content:read   lp_content(query) — live pages, entries and globals
//	storage        lp_kv_get / lp_kv_set / lp_kv_delete — its own namespace
//	http           outbound requests, only to the hosts it declared
//	log            lp_log(message) — always
//
// It is called through what its manifest declares: hooks (events such as
// page.published, to its on_event export), routes (served under
// /api/x/<key>/…, to the export each names) and admin screens (described as
// data: forms the admin draws, no code in the admin).
//
// A plugin can't touch the database, the filesystem, other plugins' storage
// or the network beyond its hosts, and a call that runs past its time limit
// is stopped. See docs/plugins.md.

type PluginManifest struct {
	Key         string          `json:"key"`
	Name        string          `json:"name"`
	Version     string          `json:"version"`
	Description string          `json:"description"`
	Permissions PluginGrants    `json:"permissions"`
	Hooks       []string        `json:"hooks"`
	Routes      []PluginRoute   `json:"routes"`
	Admin       json.RawMessage `json:"admin,omitempty"`
	SiteConfig  json.RawMessage `json:"site_config,omitempty"`
}

// PluginGrants is what a plugin asks for, and the subset a person granted.
type PluginGrants struct {
	ContentRead bool     `json:"content:read"`
	Storage     bool     `json:"storage"`
	HTTP        []string `json:"http"`
}

type PluginRoute struct {
	Method string `json:"method"`
	Path   string `json:"path"`
	Export string `json:"export"`
	// Public routes answer anyone (a form's submissions); the rest need a
	// signed-in caller with plugins:read.
	Public bool `json:"public"`
}

type Plugin struct {
	ID          int64
	Key         string
	Name        string
	Version     string
	Description string
	Manifest    JSON
	Granted     PluginGrants
	Enabled     bool
	CreatedAt   Time
	UpdatedAt   Time

	parsed   PluginManifest
	compiled *extism.CompiledPlugin
}

func (p *Plugin) JSON() Obj {
	return O("id", p.ID, "key", p.Key, "name", p.Name, "version", p.Version, "description", p.Description,
		"requested", p.parsed.Permissions, "granted", p.Granted, "enabled", p.Enabled, "hooks", p.parsed.Hooks,
		"routes", p.parsed.Routes, "admin", p.parsed.Admin, "created_at", p.CreatedAt, "updated_at", p.UpdatedAt)
}

type PluginHost struct {
	app     *App
	mu      sync.RWMutex
	plugins map[string]*Plugin
}

var pluginKeyFormat = regexp.MustCompile(`^[a-z][a-z0-9_]{1,40}$`)

const pluginCallTimeout = 10 * time.Second

// LoadAll compiles every enabled plugin; one that fails is left off and
// logged, not fatal: a plugin can't break the site.
func (h *PluginHost) LoadAll() error {
	ctx := context.Background()
	rows, err := h.app.Store.DB.QueryContext(ctx, `SELECT id, key, name, version, COALESCE(description, ''), manifest, granted, enabled, created_at, updated_at, wasm FROM plugins ORDER BY key`)
	if err != nil {
		return err
	}
	type loaded struct {
		p    *Plugin
		wasm []byte
	}
	var all []loaded
	for rows.Next() {
		p := &Plugin{}
		var granted JSON
		var wasm []byte
		if err := rows.Scan(&p.ID, &p.Key, &p.Name, &p.Version, &p.Description, &p.Manifest, &granted, &p.Enabled, &p.CreatedAt, &p.UpdatedAt, &wasm); err != nil {
			rows.Close()
			return err
		}
		json.Unmarshal(p.Manifest, &p.parsed)
		json.Unmarshal(granted, &p.Granted)
		all = append(all, loaded{p, wasm})
	}
	rows.Close()
	h.mu.Lock()
	defer h.mu.Unlock()
	for _, old := range h.plugins {
		if old.compiled != nil {
			old.compiled.Close(ctx)
		}
	}
	h.plugins = map[string]*Plugin{}
	for _, l := range all {
		if l.p.Enabled {
			compiled, err := h.compile(ctx, l.p.Key, l.wasm, l.p.Granted)
			if err != nil {
				h.app.Logger.Warn("plugin failed to load; left off", "plugin", l.p.Key, "err", err)
				l.p.Enabled = false
			}
			l.p.compiled = compiled
		}
		h.plugins[l.p.Key] = l.p
	}
	return nil
}

func (h *PluginHost) Close() {
	h.mu.Lock()
	defer h.mu.Unlock()
	for _, p := range h.plugins {
		if p.compiled != nil {
			p.compiled.Close(context.Background())
		}
	}
	h.plugins = nil
}

func (h *PluginHost) List() []*Plugin {
	h.mu.RLock()
	defer h.mu.RUnlock()
	out := make([]*Plugin, 0, len(h.plugins))
	for _, p := range h.plugins {
		out = append(out, p)
	}
	slices.SortFunc(out, func(a, b *Plugin) int { return strings.Compare(a.Key, b.Key) })
	return out
}

func (h *PluginHost) get(key string) *Plugin {
	h.mu.RLock()
	defer h.mu.RUnlock()
	return h.plugins[key]
}

// compile builds the module with exactly the host functions its grants
// allow; what wasn't granted isn't there to call.
func (h *PluginHost) compile(ctx context.Context, key string, wasm []byte, grants PluginGrants) (*extism.CompiledPlugin, error) {
	manifest := extism.Manifest{
		Wasm:         []extism.Wasm{extism.WasmData{Data: wasm, Name: key}},
		AllowedHosts: grants.HTTP,
		Timeout:      uint64(pluginCallTimeout.Milliseconds()),
		Memory:       &extism.ManifestMemory{MaxPages: 1024, MaxHttpResponseBytes: 4 << 20, MaxVarBytes: 1 << 20},
	}
	if manifest.AllowedHosts == nil {
		manifest.AllowedHosts = []string{}
	}
	return extism.NewCompiledPlugin(ctx, manifest, extism.PluginConfig{EnableWasi: true}, h.hostFunctions(key, grants))
}

func (h *PluginHost) hostFunctions(key string, grants PluginGrants) []extism.HostFunction {
	ptr := []extism.ValueType{extism.ValueTypePTR}
	// fn wraps a host function: input string in, output string out, errors
	// as {"error": "…"} so a plugin can't crash the host.
	fn := func(name string, allowed bool, impl func(ctx context.Context, in string) (any, error)) extism.HostFunction {
		return extism.NewHostFunctionWithStack(name, func(ctx context.Context, p *extism.CurrentPlugin, stack []uint64) {
			in, err := p.ReadString(stack[0])
			var out any
			switch {
			case err != nil:
				out = map[string]any{"error": "couldn't read the input"}
			case !allowed:
				out = map[string]any{"error": name + " wasn't granted to this plugin"}
			default:
				out, err = impl(ctx, in)
				if err != nil {
					out = map[string]any{"error": err.Error()}
				}
			}
			b, _ := json.Marshal(out)
			offs, err := p.WriteBytes(b)
			if err != nil {
				stack[0] = 0
				return
			}
			stack[0] = offs
		}, ptr, ptr)
	}
	return []extism.HostFunction{
		fn("lp_log", true, func(ctx context.Context, in string) (any, error) {
			h.app.Logger.Info("plugin", "plugin", key, "message", truncate(in, 2000))
			return map[string]any{"ok": true}, nil
		}),
		fn("lp_content", grants.ContentRead, func(ctx context.Context, in string) (any, error) { return h.content(ctx, in) }),
		fn("lp_kv_get", grants.Storage, func(ctx context.Context, in string) (any, error) {
			var v []byte
			err := h.app.Store.DB.QueryRowContext(ctx, `SELECT value FROM plugin_kv WHERE plugin_key = ? AND key = ?`, key, in).Scan(&v)
			if errors.Is(err, sql.ErrNoRows) {
				return map[string]any{"found": false}, nil
			}
			return map[string]any{"found": err == nil, "value": string(v)}, err
		}),
		fn("lp_kv_set", grants.Storage, func(ctx context.Context, in string) (any, error) {
			var kvIn struct {
				Key   string `json:"key"`
				Value string `json:"value"`
			}
			if err := json.Unmarshal([]byte(in), &kvIn); err != nil || kvIn.Key == "" {
				return nil, fmt.Errorf(`lp_kv_set takes {"key": "…", "value": "…"}`)
			}
			if len(kvIn.Value) > 1<<20 {
				return nil, fmt.Errorf("a value is at most 1 MB")
			}
			var n int
			h.app.Store.DB.QueryRowContext(ctx, `SELECT count(*) FROM plugin_kv WHERE plugin_key = ?`, key).Scan(&n)
			if n > 100000 {
				return nil, fmt.Errorf("this plugin's storage is full (100,000 keys)")
			}
			_, err := h.app.Store.DB.ExecContext(ctx, `INSERT INTO plugin_kv (plugin_key, key, value, updated_at) VALUES (?,?,?,?)
				ON CONFLICT(plugin_key, key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at`, key, kvIn.Key, []byte(kvIn.Value), Now().DB())
			return map[string]any{"ok": err == nil}, err
		}),
		fn("lp_kv_delete", grants.Storage, func(ctx context.Context, in string) (any, error) {
			_, err := h.app.Store.DB.ExecContext(ctx, `DELETE FROM plugin_kv WHERE plugin_key = ? AND key = ?`, key, in)
			return map[string]any{"ok": err == nil}, err
		}),
		fn("lp_kv_list", grants.Storage, func(ctx context.Context, in string) (any, error) {
			rows, err := h.app.Store.DB.QueryContext(ctx, `SELECT key FROM plugin_kv WHERE plugin_key = ? AND key LIKE ? ORDER BY key LIMIT 1000`, key, in+"%")
			if err != nil {
				return nil, err
			}
			defer rows.Close()
			keys := []string{}
			for rows.Next() {
				var k string
				rows.Scan(&k)
				keys = append(keys, k)
			}
			return map[string]any{"keys": keys}, nil
		}),
	}
}

// content answers lp_content: {"page": "about"}, {"pages": true},
// {"collection": "posts"}, {"collection": "posts", "entry": "hello"},
// {"global": "nav"} — live content only, as the delivery API shows it.
func (h *PluginHost) content(ctx context.Context, in string) (any, error) {
	var q map[string]any
	if err := json.Unmarshal([]byte(in), &q); err != nil {
		return nil, fmt.Errorf("lp_content takes a JSON query")
	}
	a := h.app
	switch {
	case q["page"] != nil:
		p, err := a.PageByPath(ctx, str(q["page"]), true)
		if err != nil {
			return nil, err
		}
		return a.v1PageJSON(ctx, p)
	case q["pages"] != nil:
		list, err := a.Pages(ctx, "status = 'published' ORDER BY path LIMIT 500")
		if err != nil {
			return nil, err
		}
		out := []Obj{}
		for _, p := range list {
			out = append(out, O("id", p.ID, "path", p.Path, "title", p.Title, "locale", p.Locale, "url", a.PublicPath(p), "updated_at", p.UpdatedAt))
		}
		return out, nil
	case q["collection"] != nil:
		col, err := a.CollectionBySlug(ctx, str(q["collection"]))
		if err != nil {
			return nil, err
		}
		if q["entry"] != nil {
			e, err := a.EntryBySlug(ctx, col.ID, str(q["entry"]), true)
			if err != nil {
				return nil, err
			}
			return a.v1EntryJSON(ctx, e)
		}
		list, err := a.Entries(ctx, "e.collection_id = ? AND e.status = 'published' ORDER BY e.published_at DESC LIMIT 500", col.ID)
		if err != nil {
			return nil, err
		}
		out := []Obj{}
		for _, e := range list {
			o, err := a.v1EntryJSON(ctx, e)
			if err != nil {
				return nil, err
			}
			out = append(out, o)
		}
		return out, nil
	case q["global"] != nil:
		g, err := a.GlobalBySlug(ctx, str(q["global"]))
		if err != nil {
			return nil, err
		}
		return v1GlobalJSON(g), nil
	}
	return nil, fmt.Errorf(`lp_content: ask for {"page"}, {"pages"}, {"collection"[, "entry"]} or {"global"}`)
}

func truncate(s string, n int) string {
	if len(s) > n {
		return s[:n] + "…"
	}
	return s
}

// Call runs one export of an enabled plugin with input, in a fresh
// instance, within the time limit.
func (h *PluginHost) Call(ctx context.Context, key, export string, input []byte) ([]byte, error) {
	p := h.get(key)
	if p == nil || !p.Enabled || p.compiled == nil {
		return nil, fmt.Errorf("plugin %s isn't enabled", key)
	}
	ctx, cancel := context.WithTimeout(ctx, pluginCallTimeout)
	defer cancel()
	inst, err := p.compiled.Instance(ctx, extism.PluginInstanceConfig{})
	if err != nil {
		return nil, err
	}
	defer inst.Close(ctx)
	if !inst.FunctionExists(export) {
		return nil, fmt.Errorf("plugin %s has no export %s", key, export)
	}
	exit, out, err := inst.CallWithContext(ctx, export, input)
	if err != nil {
		return nil, fmt.Errorf("plugin %s/%s: %w", key, export, err)
	}
	if exit != 0 {
		return nil, fmt.Errorf("plugin %s/%s exited %d: %s", key, export, exit, inst.GetError())
	}
	return out, nil
}

// Emit hands an event to every enabled plugin that hooks it, in the
// background: a slow or failing plugin never holds up a save.
func (h *PluginHost) Emit(event string, data any) {
	for _, p := range h.List() {
		if !p.Enabled || !slices.Contains(p.parsed.Hooks, event) {
			continue
		}
		go func(p *Plugin) {
			body, _ := json.Marshal(map[string]any{"event": event, "data": data})
			if _, err := h.Call(context.Background(), p.Key, "on_event", body); err != nil {
				h.app.Logger.Warn("plugin hook", "plugin", p.Key, "event", event, "err", err)
			}
		}(p)
	}
}

// Install reads a module's manifest (calling its `manifest` export in a
// sandbox with nothing granted) and stores it, off until a person grants
// what it asks for and enables it.
func (h *PluginHost) Install(ctx context.Context, actor *Actor, wasm []byte) (*Plugin, error) {
	probe, err := h.compile(ctx, "probe", wasm, PluginGrants{})
	if err != nil {
		return nil, &Error{Status: 422, Code: "invalid", Message: "That isn't a WebAssembly plugin this CMS can load: " + err.Error()}
	}
	defer probe.Close(ctx)
	inst, err := probe.Instance(ctx, extism.PluginInstanceConfig{})
	if err != nil {
		return nil, &Error{Status: 422, Code: "invalid", Message: "The plugin wouldn't start: " + err.Error()}
	}
	defer inst.Close(ctx)
	if !inst.FunctionExists("manifest") {
		return nil, &Error{Status: 422, Code: "invalid", Message: "The plugin has no `manifest` export saying what it is and what it needs."}
	}
	_, out, err := inst.CallWithContext(ctx, "manifest", nil)
	if err != nil {
		return nil, &Error{Status: 422, Code: "invalid", Message: "Its manifest export failed: " + err.Error()}
	}
	var m PluginManifest
	if err := json.Unmarshal(out, &m); err != nil {
		return nil, &Error{Status: 422, Code: "invalid", Message: "Its manifest isn't JSON: " + err.Error()}
	}
	inv := Invalid{}
	if !pluginKeyFormat.MatchString(m.Key) {
		inv.Add("key", "must be lowercase letters, digits and _, starting with a letter")
	}
	if m.Name == "" {
		inv.Add("name", "can't be blank")
	}
	if m.Version == "" {
		inv.Add("version", "can't be blank")
	}
	for i, r := range m.Routes {
		if r.Export == "" || !strings.HasPrefix(r.Path, "/") {
			inv.Add(fmt.Sprintf("routes[%d]", i), "needs a path starting with / and an export")
		}
	}
	for _, host := range m.Permissions.HTTP {
		if host == "*" || strings.Contains(host, "/") {
			inv.Add("permissions.http", "names hosts, not \"*\" or URLs: "+host)
		}
	}
	if err := inv.Err(); err != nil {
		return nil, err
	}
	now := Now().DB()
	// A new version of an installed plugin keeps its grants where they're
	// still asked for, and stays off until re-enabled if it asks for more.
	var existing int64
	var oldGranted JSON
	var wasEnabled bool
	err = h.app.Store.DB.QueryRowContext(ctx, `SELECT id, granted, enabled FROM plugins WHERE key = ?`, m.Key).Scan(&existing, &oldGranted, &wasEnabled)
	granted := PluginGrants{}
	enabled := false
	if err == nil {
		var old PluginGrants
		json.Unmarshal(oldGranted, &old)
		granted = intersectGrants(old, m.Permissions)
		enabled = wasEnabled && grantsCover(granted, m.Permissions)
		_, err = h.app.Store.DB.ExecContext(ctx, `UPDATE plugins SET name=?, version=?, description=?, manifest=?, granted=?, enabled=?, wasm=?, updated_at=? WHERE id=?`,
			m.Name, m.Version, m.Description, string(out), string(mustJSON(granted)), enabled, wasm, now, existing)
	} else {
		_, err = h.app.Store.DB.ExecContext(ctx, `INSERT INTO plugins (key, name, version, description, manifest, granted, enabled, wasm, created_at, updated_at) VALUES (?,?,?,?,?,?,0,?,?,?)`,
			m.Key, m.Name, m.Version, m.Description, string(out), string(mustJSON(granted)), wasm, now, now)
	}
	if err != nil {
		return nil, err
	}
	h.app.audit(ctx, actor, "plugin.installed", "Plugin", 0, m.Key+" "+m.Version, map[string]any{"permissions": m.Permissions})
	if err := h.LoadAll(); err != nil {
		return nil, err
	}
	return h.get(m.Key), nil
}

func intersectGrants(granted, asked PluginGrants) PluginGrants {
	out := PluginGrants{ContentRead: granted.ContentRead && asked.ContentRead, Storage: granted.Storage && asked.Storage, HTTP: []string{}}
	for _, host := range granted.HTTP {
		if slices.Contains(asked.HTTP, host) {
			out.HTTP = append(out.HTTP, host)
		}
	}
	return out
}

func grantsCover(granted, asked PluginGrants) bool {
	if asked.ContentRead && !granted.ContentRead || asked.Storage && !granted.Storage {
		return false
	}
	for _, host := range asked.HTTP {
		if !slices.Contains(granted.HTTP, host) {
			return false
		}
	}
	return true
}

// Configure sets what's granted (never more than was asked) and whether
// it's on.
func (h *PluginHost) Configure(ctx context.Context, actor *Actor, key string, grant *PluginGrants, enabled *bool) (*Plugin, error) {
	p := h.get(key)
	if p == nil {
		return nil, errNotFound("No plugin " + key + ".")
	}
	granted := p.Granted
	if grant != nil {
		granted = intersectGrants(*grant, p.parsed.Permissions)
	}
	on := p.Enabled
	if enabled != nil {
		on = *enabled
	}
	if _, err := h.app.Store.DB.ExecContext(ctx, `UPDATE plugins SET granted = ?, enabled = ?, updated_at = ? WHERE key = ?`, string(mustJSON(granted)), on, Now().DB(), key); err != nil {
		return nil, err
	}
	h.app.audit(ctx, actor, "plugin.configured", "Plugin", p.ID, key, map[string]any{"granted": granted, "enabled": on})
	if err := h.LoadAll(); err != nil {
		return nil, err
	}
	p = h.get(key)
	if on && !p.Enabled {
		return p, errConflict("The plugin failed to load and was left off: see the server log.")
	}
	return p, nil
}

func (h *PluginHost) Remove(ctx context.Context, actor *Actor, key string, purgeData bool) error {
	if _, err := h.app.Store.DB.ExecContext(ctx, `DELETE FROM plugins WHERE key = ?`, key); err != nil {
		return err
	}
	if purgeData {
		h.app.Store.DB.ExecContext(ctx, `DELETE FROM plugin_kv WHERE plugin_key = ?`, key)
	}
	h.app.audit(ctx, actor, "plugin.removed", "Plugin", 0, key, map[string]any{"purge_data": purgeData})
	return h.LoadAll()
}

// ---- the API -------------------------------------------------------------

func (a *App) pluginRoutes(h func(string, HandlerFunc, ...func(*route))) {
	h("GET /api/plugins", a.listPlugins)
	h("POST /api/plugins", a.installPlugin)
	h("GET /api/plugins/{key}", a.showPlugin)
	h("PATCH /api/plugins/{key}", a.configurePlugin)
	h("DELETE /api/plugins/{key}", a.removePlugin)
	// A plugin's own routes, as its manifest declares them.
	h("/api/x/{key}/{rest...}", a.pluginRoute, open)
}

func (a *App) listPlugins(c *Ctx) error {
	if err := c.Need("plugins:read"); err != nil {
		return err
	}
	out := []Obj{}
	for _, p := range a.Plugins.List() {
		out = append(out, p.JSON())
	}
	return c.JSON(200, O("plugins", out))
}

func (a *App) showPlugin(c *Ctx) error {
	if err := c.Need("plugins:read"); err != nil {
		return err
	}
	p := a.Plugins.get(c.Param("key"))
	if p == nil {
		return errNotFound("No plugin " + c.Param("key") + ".")
	}
	return c.JSON(200, O("plugin", p.JSON()))
}

func (a *App) installPlugin(c *Ctx) error {
	if err := c.Need("plugins:write"); err != nil {
		return err
	}
	var src io.Reader = c.R.Body
	if strings.HasPrefix(c.R.Header.Get("Content-Type"), "multipart/") {
		f, _, err := c.R.FormFile("file")
		if err != nil {
			return errBadRequest("Upload the .wasm file as \"file\".")
		}
		defer f.Close()
		src = f
	}
	wasm, err := io.ReadAll(io.LimitReader(src, 64<<20))
	if err != nil {
		return err
	}
	if len(wasm) < 8 || string(wasm[:4]) != "\x00asm" {
		return errBadRequest("That isn't a .wasm file.")
	}
	p, err := a.Plugins.Install(c.R.Context(), c.Actor, wasm)
	if err != nil {
		return err
	}
	c.Summary = fmt.Sprintf("Installed %s %s, off until its permissions are granted.", p.Name, p.Version)
	return c.JSON(201, O("plugin", p.JSON()))
}

func (a *App) configurePlugin(c *Ctx) error {
	if err := c.Need("plugins:write"); err != nil {
		return err
	}
	var body struct {
		Plugin struct {
			Granted *PluginGrants `json:"granted"`
			Enabled *bool         `json:"enabled"`
		} `json:"plugin"`
	}
	if err := c.Body(&body); err != nil {
		return err
	}
	p, err := a.Plugins.Configure(c.R.Context(), c.Actor, c.Param("key"), body.Plugin.Granted, body.Plugin.Enabled)
	if err != nil {
		return err
	}
	return c.JSON(200, O("plugin", p.JSON()))
}

func (a *App) removePlugin(c *Ctx) error {
	if err := c.Need("plugins:write"); err != nil {
		return err
	}
	if a.Plugins.get(c.Param("key")) == nil {
		return errNotFound("No plugin " + c.Param("key") + ".")
	}
	if err := a.Plugins.Remove(c.R.Context(), c.Actor, c.Param("key"), c.truthy("purge_data")); err != nil {
		return err
	}
	return c.NoContent()
}

// pluginRoute hands a request to the plugin export its manifest names. The
// plugin gets {method, path, query, headers, body, actor} and answers
// {status, headers, body} (or anything else, sent as JSON).
func (a *App) pluginRoute(c *Ctx) error {
	p := a.Plugins.get(c.Param("key"))
	if p == nil || !p.Enabled {
		return errNotFound("No plugin " + c.Param("key") + ".")
	}
	path := "/" + c.Param("rest")
	var rt *PluginRoute
	for i := range p.parsed.Routes {
		r := &p.parsed.Routes[i]
		if r.Path == path && (r.Method == "" || strings.EqualFold(r.Method, c.R.Method)) {
			rt = r
			break
		}
	}
	if rt == nil {
		return errNotFound("Plugin " + p.Key + " has no route " + c.R.Method + " " + path + ".")
	}
	if !rt.Public {
		if err := c.Need("plugins:read"); err != nil {
			return err
		}
	}
	body, _ := io.ReadAll(io.LimitReader(c.R.Body, 1<<20))
	headers := map[string]string{}
	for _, k := range []string{"Content-Type", "Accept", "User-Agent", "Referer", "Origin"} {
		if v := c.R.Header.Get(k); v != "" {
			headers[k] = v
		}
	}
	var actor any
	if c.Actor != nil {
		actor = O("name", c.Actor.Name, "type", c.Actor.Type(), "capabilities", c.Actor.Role.Capabilities())
	}
	in, _ := json.Marshal(O("method", c.R.Method, "path", path, "query", c.R.URL.Query(), "headers", headers, "body", string(body), "ip", c.ip(), "actor", actor))
	out, err := a.Plugins.Call(c.R.Context(), p.Key, rt.Export, in)
	if err != nil {
		a.Logger.Warn("plugin route", "plugin", p.Key, "err", err)
		return &Error{Status: 502, Code: "plugin_error", Message: "The plugin failed to answer."}
	}
	var resp struct {
		Status  int               `json:"status"`
		Headers map[string]string `json:"headers"`
		Body    *string           `json:"body"`
	}
	if json.Unmarshal(out, &resp) == nil && resp.Status != 0 {
		for k, v := range resp.Headers {
			if !strings.EqualFold(k, "Set-Cookie") {
				c.W.Header().Set(k, v)
			}
		}
		if c.W.Header().Get("Content-Type") == "" {
			c.W.Header().Set("Content-Type", "application/json; charset=utf-8")
		}
		c.W.Header().Set("Content-Security-Policy", "sandbox")
		c.W.WriteHeader(resp.Status)
		if resp.Body != nil {
			c.W.Write([]byte(*resp.Body))
		}
		return nil
	}
	c.W.Header().Set("Content-Type", "application/json; charset=utf-8")
	c.W.WriteHeader(http.StatusOK)
	_, err = c.W.Write(out)
	return err
}
