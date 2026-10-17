package cms

import (
	"archive/tar"
	"compress/gzip"
	"context"
	"database/sql"
	"encoding/csv"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"net/http"
	"net/mail"
	"os"
	"path/filepath"
	"slices"
	"sort"
	"strconv"
	"strings"
	"time"
)

func (a *App) adminRoutes(h func(string, HandlerFunc, ...func(*route))) {
	h("GET /api/redirects", a.edgeRedirects)
	h("GET /api/redirects/all", a.allRedirects)
	h("GET /api/redirects/resolve", a.resolveRedirect)
	h("GET /api/redirects/export", a.exportRedirects)
	h("POST /api/redirects/import", a.importRedirects)
	h("POST /api/redirects", a.createRedirect)
	h("PATCH /api/redirects/{id}", a.updateRedirect)
	h("PUT /api/redirects/{id}", a.updateRedirect)
	h("DELETE /api/redirects/{id}", a.destroyRedirect)

	h("GET /api/settings", a.listSettings)
	h("POST /api/settings", a.createSetting)
	h("GET /api/settings/{key}", a.showSetting)
	h("PATCH /api/settings/{key}", a.updateSetting)
	h("POST /api/settings/email/test", a.sendTestMail)
	h("PUT /api/settings/{key}", a.updateSetting)
	h("DELETE /api/settings/{key}", a.destroySetting)

	h("GET /api/deploy", a.showDeploy)
	h("PATCH /api/deploy", a.updateDeploy)
	h("POST /api/deploy/trigger", a.triggerDeploy)
	h("GET /api/frontend", a.showFrontend)
	h("POST /api/frontend/builds", a.reportBuild)

	h("GET /api/audit_log", a.listAudit)

	h("GET /api/trash", a.listTrash)
	h("POST /api/trash/{kind}/{id}/restore", a.restoreTrash)
	h("DELETE /api/trash/{kind}/{id}", a.purgeTrash)

	h("GET /api/webhooks", a.listWebhooks)
	h("POST /api/webhooks", a.createWebhook)
	h("GET /api/webhooks/{id}", a.showWebhook)
	h("PATCH /api/webhooks/{id}", a.updateWebhook)
	h("PUT /api/webhooks/{id}", a.updateWebhook)
	h("DELETE /api/webhooks/{id}", a.destroyWebhook)
	h("POST /api/webhooks/{id}/rotate_secret", a.rotateWebhookSecret)
	h("POST /api/webhooks/{id}/test", a.testWebhook)
	h("GET /api/webhooks/{id}/deliveries", a.webhookDeliveries)

	h("GET /api/service_tokens", a.listServiceTokens)
	h("POST /api/service_tokens", a.createServiceToken)
	h("GET /api/service_tokens/{id}", a.showServiceToken)
	h("POST /api/service_tokens/{id}/reveal", a.revealServiceToken)
	h("POST /api/service_tokens/{id}/rotate", a.rotateServiceToken)
	h("POST /api/service_tokens/{id}/revoke", a.revokeServiceToken)

	h("GET /api/users", a.listUsers)
	h("POST /api/users", a.createUser)
	h("PATCH /api/users/{id}", a.updateUser)
	h("DELETE /api/users/{id}", a.destroyUser)
	h("GET /api/roles", a.listRoles)
	h("POST /api/roles", a.createRole)
	h("PATCH /api/roles/{id}", a.updateRole)
	h("DELETE /api/roles/{id}", a.destroyRole)

	h("POST /api/search", a.search)
	h("GET /api/search", a.search)
	h("GET /api/references", a.references)
	h("GET /api/sitemap", a.managementSitemap)
	h("GET /api/site_health", a.siteHealth)
	h("GET /api/tools/backup", a.backup)

	h("POST /api/device/code", a.deviceCode, open)
	h("POST /api/device/token", a.deviceToken, open)
	h("POST /api/device/approve", a.deviceApprove)
	h("GET /api/device/{code}", a.deviceShow)

	h("GET /api/session", a.showSession, open)
	h("POST /api/session", a.createSession, open)
	h("DELETE /api/session", a.destroySession)
	h("POST /api/setup", a.setup, open)
	h("POST /api/password/forgot", a.forgotPassword, open)
	h("POST /api/password/reset", a.resetPassword, open)
	h("POST /api/email/confirm", a.confirmEmail, open)
	h("DELETE /api/users/{id}/pending_email", a.cancelEmailChange)
	h("POST /api/locks", a.acquireLock)
	h("DELETE /api/locks/{type}/{id}", a.releaseLock)
	h("GET /api/autosaves", a.showAutosave)
	h("PUT /api/autosaves", a.putAutosave)
	h("DELETE /api/autosaves", a.deleteAutosave)
	h("GET /api/me/preferences", a.showPreferences)
	h("PATCH /api/me/preferences", a.updatePreferences)
	h("GET /api/site_health/info", a.siteHealthInfo)

	a.pluginRoutes(h)
}

// ---- identity ------------------------------------------------------------

func (a *App) getMe(c *Ctx) error {
	ctx := c.R.Context()
	body := O()
	var token any
	if c.Actor.TokenID != 0 {
		token = a.tokenRow(ctx, "api_tokens", c.Actor.TokenID)
	} else if c.Actor.ServiceID != 0 {
		token = a.tokenRow(ctx, "service_tokens", c.Actor.ServiceID)
	}
	caps := []string{}
	if c.Actor.Role != nil {
		caps = c.Actor.Role.Capabilities()
	}
	body = append(body, kv{"token", token}, kv{"capabilities", caps})
	if c.Actor.ServiceID != 0 {
		roleName := ""
		if c.Actor.Role != nil {
			roleName = c.Actor.Role.Name
		}
		body = append(body, kv{"service", O("id", c.Actor.ServiceID, "name", c.Actor.Name, "role", roleName)})
	} else {
		body = append(body, kv{"user", O("id", c.Actor.UserID, "name", c.Actor.Name, "email", c.Actor.Email)})
	}
	c.Summary = fmt.Sprintf("%s, with %d capabilities.", c.Actor.Label(), len(caps))
	c.Crumbs = []Crumb{crumb("The shape of this CMS", "cms manifest"), crumb("The house voice, before writing copy", "cms brand")}
	return c.JSON(200, body)
}

func (a *App) tokenRow(ctx context.Context, table string, id int64) Obj {
	var prefix string
	var created, used Time
	var ip sql.NullString
	if a.Store.DB.QueryRowContext(ctx, `SELECT prefix, created_at, last_used_at, last_used_ip FROM `+table+` WHERE id = ?`, id).Scan(&prefix, &created, &used, &ip) != nil {
		return nil
	}
	return O("id", id, "prefix", prefix, "created_at", created.ISO(), "last_used_at", used.ISO(), "last_used_ip", nullStr(ip))
}

func nullStr(s sql.NullString) any {
	if !s.Valid {
		return nil
	}
	return s.String
}

// MintUserToken replaces the user's personal token (one per user: rotating
// is revoking) and returns the plaintext.
func (a *App) MintUserToken(ctx context.Context, userID int64) (string, int64, error) {
	plain := "lp_" + randomToken(32)
	now := Now().DB()
	var id int64
	err := a.Store.Tx(ctx, func(tx *sql.Tx) error {
		if _, err := tx.ExecContext(ctx, `DELETE FROM api_tokens WHERE user_id = ?`, userID); err != nil {
			return err
		}
		res, err := tx.ExecContext(ctx, `INSERT INTO api_tokens (user_id, prefix, token, token_digest, created_at, updated_at) VALUES (?,?,?,?,?,?)`,
			userID, plain[:11], a.Secrets.Seal(plain), digest(plain), now, now)
		if err != nil {
			return err
		}
		id, _ = res.LastInsertId()
		return nil
	})
	return plain, id, err
}

// userToken is the user's token as it stands, minting one when there's none
// or it can't be shown again.
func (a *App) userToken(ctx context.Context, userID int64) (string, error) {
	var sealed sql.NullString
	err := a.Store.DB.QueryRowContext(ctx, `SELECT token FROM api_tokens WHERE user_id = ?`, userID).Scan(&sealed)
	if err == nil && sealed.Valid {
		if plain, ok := a.Secrets.Open(sealed.String); ok {
			return plain, nil
		}
	}
	plain, _, err := a.MintUserToken(ctx, userID)
	return plain, err
}

func (a *App) rotateMyToken(c *Ctx) error {
	if c.Actor.UserID == 0 {
		return &Error{Status: 403, Code: "forbidden", Message: "A service token is rotated from Settings › Service tokens (cms service-token rotate <id>)."}
	}
	plain, id, err := a.MintUserToken(c.R.Context(), c.Actor.UserID)
	if err != nil {
		return err
	}
	a.audit(c.R.Context(), c.Actor, "api_token.rotated", "ApiToken", id, c.Actor.Name, nil)
	c.Summary = "Rotated: the old token stopped working just now."
	return c.JSON(200, O("token", append(a.tokenRow(c.R.Context(), "api_tokens", id), kv{"token", plain})))
}

// ---- manifest ------------------------------------------------------------

func (a *App) getManifest(c *Ctx) error {
	ctx := c.R.Context()
	count := func(q string) int {
		var n int
		a.Store.DB.QueryRowContext(ctx, q).Scan(&n)
		return n
	}
	bts, err := a.BlockTypesList(ctx, "deprecated = 0 ORDER BY category, label")
	if err != nil {
		return err
	}
	blocks := []Obj{}
	for _, b := range bts {
		blocks = append(blocks, O("slug", b.Slug, "label", b.Label, "description", b.Description, "category", b.Category, "icon", b.Icon,
			"version", b.Version, "fields", b.Fields, "defaults", b.Defaults, "json_schema", b.Schema()))
	}
	gs, err := a.Globals(ctx, "1=1 ORDER BY name")
	if err != nil {
		return err
	}
	globals := []Obj{}
	for _, g := range gs {
		globals = append(globals, O("slug", g.Slug, "name", g.Name, "description", g.Description, "fields", g.FieldsJSON(), "json_schema", JSONSchema(g.Fields())))
	}
	cols, err := a.Collections(ctx, "1=1 ORDER BY slug")
	if err != nil {
		return err
	}
	collections := []Obj{}
	for _, col := range cols {
		var n int
		a.Store.DB.QueryRowContext(ctx, `SELECT count(*) FROM collection_entries WHERE collection_id = ? AND deleted_at IS NULL`, col.ID).Scan(&n)
		collections = append(collections, O("slug", col.Slug, "name", col.Name, "enable_blocks", col.EnableBlocks, "api_enabled", col.APIEnabled,
			"fields", col.FieldsJSON(), "frontmatter_json_schema", JSONSchema(col.Fields()), "entry_count", n,
			"categories_collection_id", col.CategoriesCollectionID, "tags_collection_id", col.TagsCollectionID))
	}
	plugins := []Obj{}
	for _, p := range a.Plugins.List() {
		plugins = append(plugins, O("key", p.Key, "name", p.Name, "version", p.Version, "enabled", p.Enabled))
	}
	c.Summary = fmt.Sprintf("%d collections, %d block types, %d globals.", len(collections), len(blocks), len(globals))
	c.Crumbs = []Crumb{crumb("Every page", "cms pages"), crumb("The house voice", "cms brand")}
	return c.JSON(200, O(
		"tenant", a.Hooks.tenant(),
		"generated_at", time.Now().UTC().Format(time.RFC3339),
		"brand", brandBrief(a.Setting(ctx, "brand")),
		"counts", O("pages", count(`SELECT count(*) FROM pages WHERE deleted_at IS NULL`), "collections", count(`SELECT count(*) FROM collections`),
			"entries", count(`SELECT count(*) FROM collection_entries WHERE deleted_at IS NULL`), "block_types", count(`SELECT count(*) FROM block_types`),
			"globals", count(`SELECT count(*) FROM globals WHERE deleted_at IS NULL`)),
		"block_types", blocks,
		"globals", globals,
		"collections", collections,
		"version", Version,
		"plugins", plugins,
	))
}

// ---- redirects -----------------------------------------------------------

type Redirect struct {
	ID                   int64
	Source, Destination  string
	Status               int
	Active, Wildcard     bool
	Hits                 int
	LastHitAt            Time
	Notes                string
	CreatedAt, UpdatedAt Time
}

func (r *Redirect) JSON() Obj {
	return O("id", r.ID, "source_path", r.Source, "destination_url", r.Destination, "status_code", r.Status, "active", r.Active,
		"wildcard", r.Wildcard, "hit_count", r.Hits, "last_hit_at", r.LastHitAt, "notes", r.Notes, "created_at", r.CreatedAt, "updated_at", r.UpdatedAt)
}

func (a *App) Redirects(ctx context.Context, where string, args ...any) ([]*Redirect, error) {
	rows, err := a.Store.DB.QueryContext(ctx, `SELECT id, source_path, destination_url, status_code, active, wildcard, hit_count, last_hit_at, COALESCE(notes, ''), created_at, updated_at
		FROM redirects WHERE `+where, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []*Redirect{}
	for rows.Next() {
		r := &Redirect{}
		if err := rows.Scan(&r.ID, &r.Source, &r.Destination, &r.Status, &r.Active, &r.Wildcard, &r.Hits, &r.LastHitAt, &r.Notes, &r.CreatedAt, &r.UpdatedAt); err != nil {
			return nil, err
		}
		out = append(out, r)
	}
	return out, rows.Err()
}

// edgeRedirects is the build's shape: only what applying a rule needs.
func (a *App) edgeRedirects(c *Ctx) error {
	if err := c.Need("redirects:read"); err != nil {
		return err
	}
	list, err := a.Redirects(c.R.Context(), "active = 1 ORDER BY wildcard, length(source_path) DESC, id")
	if err != nil {
		return err
	}
	out := []Obj{}
	for _, r := range list {
		out = append(out, O("source", r.Source, "destination", r.Destination, "status", r.Status, "wildcard", r.Wildcard))
	}
	return c.JSON(200, O("redirects", out))
}

func (a *App) allRedirects(c *Ctx) error {
	if err := c.Need("redirects:read"); err != nil {
		return err
	}
	list, err := a.Redirects(c.R.Context(), "1=1 ORDER BY id")
	if err != nil {
		return err
	}
	out := []Obj{}
	for _, r := range list {
		out = append(out, r.JSON())
	}
	c.Summary = fmt.Sprintf("%d redirect %s.", len(out), plural(len(out), "rule"))
	return c.JSON(200, O("redirects", out))
}

// MatchRedirect finds the rule for path: exact first, then the longest
// wildcard ("/blog/*").
func (a *App) MatchRedirect(ctx context.Context, path string) (*Redirect, string) {
	list, err := a.Redirects(ctx, "active = 1 ORDER BY wildcard, length(source_path) DESC, id")
	if err != nil {
		return nil, ""
	}
	path = "/" + strings.Trim(path, "/")
	for _, r := range list {
		src := "/" + strings.Trim(strings.TrimSuffix(r.Source, "*"), "/")
		if !r.Wildcard && src == path {
			return r, r.Destination
		}
		if r.Wildcard && (path == src || strings.HasPrefix(path, strings.TrimSuffix(src, "/")+"/")) {
			splat := strings.TrimPrefix(strings.TrimPrefix(path, strings.TrimSuffix(src, "/")), "/")
			return r, strings.ReplaceAll(strings.ReplaceAll(r.Destination, ":splat", splat), "*", splat)
		}
	}
	return nil, ""
}

func (a *App) resolveRedirect(c *Ctx) error {
	if err := c.Need("redirects:read"); err != nil {
		return err
	}
	r, dest := a.MatchRedirect(c.R.Context(), c.Query("path"))
	if r == nil {
		return errNotFound("No redirect for " + c.Query("path") + ".")
	}
	a.Store.DB.ExecContext(c.R.Context(), `UPDATE redirects SET hit_count = hit_count + 1, last_hit_at = ? WHERE id = ?`, Now().DB(), r.ID)
	return c.JSON(200, O("source", r.Source, "destination", dest, "status", r.Status))
}

func (a *App) saveRedirect(c *Ctx, r *Redirect, p map[string]any) error {
	creating := r.ID == 0
	if creating {
		r.Status, r.Active = 301, true
	}
	if has(p, "source_path") {
		r.Source = strings.TrimSpace(str(p["source_path"]))
	}
	if has(p, "destination_url") {
		r.Destination = strings.TrimSpace(str(p["destination_url"]))
	}
	if v, ok := intOf(p["status_code"]); ok {
		r.Status = int(v)
	}
	if has(p, "active") {
		r.Active = boolOf(p["active"])
	}
	if has(p, "notes") {
		r.Notes = str(p["notes"])
	}
	r.Wildcard = strings.HasSuffix(r.Source, "*")
	inv := Invalid{}
	if !strings.HasPrefix(r.Source, "/") {
		inv.Add("source_path", "must start with /")
	}
	if r.Destination == "" {
		inv.Add("destination_url", "can't be blank")
	}
	if !slices.Contains([]int{301, 302, 307, 308, 410}, r.Status) {
		inv.Add("status_code", "must be 301, 302, 307, 308 or 410")
	}
	if strings.TrimRight(r.Source, "/") == strings.TrimRight(r.Destination, "/") {
		inv.Add("destination_url", "can't be the same as the source")
	}
	var clash int
	a.Store.DB.QueryRowContext(c.R.Context(), `SELECT count(*) FROM redirects WHERE source_path = ? AND id != ?`, r.Source, r.ID).Scan(&clash)
	if clash > 0 {
		inv.Add("source_path", "has already been taken")
	}
	if err := inv.Err(); err != nil {
		return err
	}
	now := Now()
	if creating {
		res, err := a.Store.DB.ExecContext(c.R.Context(), `INSERT INTO redirects (source_path, destination_url, status_code, active, wildcard, notes, created_at, updated_at) VALUES (?,?,?,?,?,?,?,?)`,
			r.Source, r.Destination, r.Status, r.Active, r.Wildcard, r.Notes, now.DB(), now.DB())
		if err != nil {
			return err
		}
		r.ID, _ = res.LastInsertId()
		r.CreatedAt = now
	} else if _, err := a.Store.DB.ExecContext(c.R.Context(), `UPDATE redirects SET source_path=?, destination_url=?, status_code=?, active=?, wildcard=?, notes=?, updated_at=? WHERE id=?`,
		r.Source, r.Destination, r.Status, r.Active, r.Wildcard, r.Notes, now.DB(), r.ID); err != nil {
		return err
	}
	r.UpdatedAt = now
	a.audit(c.R.Context(), c.Actor, map[bool]string{true: "redirect.created", false: "redirect.updated"}[creating], "Redirect", r.ID, r.Source+" → "+r.Destination, nil)
	a.Deploys.Changed("redirects")
	return nil
}

func (a *App) createRedirect(c *Ctx) error {
	if err := c.Need("redirects:write"); err != nil {
		return err
	}
	p, err := c.Wrapped("redirect")
	if err != nil {
		return err
	}
	r := &Redirect{}
	if err := a.saveRedirect(c, r, p); err != nil {
		return err
	}
	c.Summary = fmt.Sprintf("%s → %s (%d).", r.Source, r.Destination, r.Status)
	return c.JSON(201, O("redirect", r.JSON()))
}

func (a *App) redirectByID(c *Ctx) (*Redirect, error) {
	id, err := c.IntParam("id")
	if err != nil {
		return nil, err
	}
	list, err := a.Redirects(c.R.Context(), "id = ?", id)
	if err != nil {
		return nil, err
	}
	if len(list) == 0 {
		return nil, errNotFound("Couldn't find redirect " + c.Param("id") + ".")
	}
	return list[0], nil
}

func (a *App) updateRedirect(c *Ctx) error {
	if err := c.Need("redirects:write"); err != nil {
		return err
	}
	r, err := a.redirectByID(c)
	if err != nil {
		return err
	}
	p, err := c.Wrapped("redirect")
	if err != nil {
		return err
	}
	if err := a.saveRedirect(c, r, p); err != nil {
		return err
	}
	return c.JSON(200, O("redirect", r.JSON()))
}

func (a *App) destroyRedirect(c *Ctx) error {
	if err := c.Need("redirects:delete"); err != nil {
		return err
	}
	r, err := a.redirectByID(c)
	if err != nil {
		return err
	}
	if _, err := a.Store.DB.ExecContext(c.R.Context(), `DELETE FROM redirects WHERE id = ?`, r.ID); err != nil {
		return err
	}
	a.audit(c.R.Context(), c.Actor, "redirect.deleted", "Redirect", r.ID, r.Source, nil)
	a.Deploys.Changed("redirects")
	return c.NoContent()
}

func (a *App) exportRedirects(c *Ctx) error {
	if err := c.Need("redirects:read"); err != nil {
		return err
	}
	list, err := a.Redirects(c.R.Context(), "1=1 ORDER BY id")
	if err != nil {
		return err
	}
	c.W.Header().Set("Content-Type", "text/csv; charset=utf-8")
	c.W.Header().Set("Content-Disposition", `attachment; filename="redirects.csv"`)
	w := csv.NewWriter(c.W)
	w.Write([]string{"source_path", "destination_url", "status_code", "active", "notes"})
	for _, r := range list {
		w.Write([]string{r.Source, r.Destination, strconv.Itoa(r.Status), strconv.FormatBool(r.Active), r.Notes})
	}
	w.Flush()
	return nil
}

func (a *App) importRedirects(c *Ctx) error {
	if err := c.Need("redirects:write"); err != nil {
		return err
	}
	var src io.Reader = c.R.Body
	if strings.HasPrefix(c.R.Header.Get("Content-Type"), "multipart/") {
		f, _, err := c.R.FormFile("file")
		if err != nil {
			return errBadRequest("Upload the CSV as \"file\".")
		}
		defer f.Close()
		src = f
	}
	rows, err := csv.NewReader(src).ReadAll()
	if err != nil {
		return errBadRequest("That isn't CSV: " + err.Error())
	}
	created, skipped, problems := 0, 0, []Obj{}
	for i, row := range rows {
		if len(row) < 2 || (i == 0 && row[0] == "source_path") {
			continue
		}
		p := map[string]any{"source_path": row[0], "destination_url": row[1]}
		if len(row) > 2 && row[2] != "" {
			p["status_code"] = row[2]
		}
		if len(row) > 4 {
			p["notes"] = row[4]
		}
		if err := a.saveRedirect(c, &Redirect{}, p); err != nil {
			var e *Error
			if errors.As(err, &e) && e.Status == 422 {
				skipped++
				problems = append(problems, O("row", i+1, "errors", e.Errors))
				continue
			}
			return err
		}
		created++
	}
	return c.JSON(200, O("ok", true, "created", created, "skipped", skipped, "errors", problems))
}

// ---- settings ------------------------------------------------------------

func (a *App) settingJSON(ctx context.Context, key string) (Obj, error) {
	var id int64
	var data JSON
	var created, updated Time
	err := a.Store.DB.QueryRowContext(ctx, `SELECT id, data, created_at, updated_at FROM settings WHERE key = ?`, key).Scan(&id, &data, &created, &updated)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, errNotFound("No setting " + key + ".")
		}
		return nil, err
	}
	return O("id", id, "key", key, "created_at", created, "updated_at", updated, "data", Redact(data.Map())), nil
}

// adminOnlySettings hold what only someone with settings:write may read.
var internalSettings = []string{"deploy_status"}

func (a *App) listSettings(c *Ctx) error {
	if err := c.Need("settings:read"); err != nil {
		return err
	}
	rows, err := a.Store.DB.QueryContext(c.R.Context(), `SELECT key FROM settings ORDER BY key`)
	if err != nil {
		return err
	}
	var keys []string
	for rows.Next() {
		var k string
		rows.Scan(&k)
		keys = append(keys, k)
	}
	rows.Close()
	out := []Obj{}
	for _, k := range keys {
		if o, err := a.settingJSON(c.R.Context(), k); err == nil {
			out = append(out, o)
		}
	}
	return c.JSON(200, O("settings", out))
}

func (a *App) showSetting(c *Ctx) error {
	if err := c.Need("settings:read"); err != nil {
		return err
	}
	key := c.Param("key")
	// The frontend's repo lives under settings/github; reading an unset
	// key is {} rather than a 404, so `cms get /settings/github` answers.
	o, err := a.settingJSON(c.R.Context(), key)
	if err != nil {
		var e *Error
		if errors.As(err, &e) && e.Status == 404 {
			o = O("id", nil, "key", key, "created_at", nil, "updated_at", nil, "data", map[string]any{})
		} else {
			return err
		}
	}
	return c.JSON(200, O("setting", o))
}

func (a *App) writeSetting(c *Ctx, key string, replace bool) error {
	if err := c.Need("settings:write"); err != nil {
		return err
	}
	if key == "" || strings.ContainsAny(key, " /") {
		return &Error{Status: 422, Code: "invalid", Message: "Validation failed", Errors: Invalid{"key": {"is invalid"}}}
	}
	var body map[string]any
	if err := c.Body(&body); err != nil {
		return err
	}
	data := body
	if s, ok := body["setting"].(map[string]any); ok {
		data = s
		if k := str(s["key"]); k != "" && key == "" {
			key = k
		}
	}
	if d, ok := data["data"].(map[string]any); ok {
		data = d
	}
	if _, err := a.PutSetting(c.R.Context(), c.Actor, key, data, replace); err != nil {
		return err
	}
	o, err := a.settingJSON(c.R.Context(), key)
	if err != nil {
		return err
	}
	return c.JSON(200, O("setting", o))
}

func (a *App) createSetting(c *Ctx) error {
	if err := c.Need("settings:write"); err != nil {
		return err
	}
	var body map[string]any
	if err := c.Body(&body); err != nil {
		return err
	}
	s, _ := body["setting"].(map[string]any)
	key := str(s["key"])
	data, _ := s["data"].(map[string]any)
	if key == "" {
		return &Error{Status: 422, Code: "invalid", Message: "Validation failed", Errors: Invalid{"key": {"can't be blank"}}}
	}
	if _, err := a.PutSetting(c.R.Context(), c.Actor, key, data, true); err != nil {
		return err
	}
	o, _ := a.settingJSON(c.R.Context(), key)
	return c.JSON(201, O("setting", o))
}

func (a *App) updateSetting(c *Ctx) error {
	return a.writeSetting(c, c.Param("key"), c.R.Method == http.MethodPut)
}

func (a *App) destroySetting(c *Ctx) error {
	if err := c.Need("settings:write"); err != nil {
		return err
	}
	if _, err := a.Store.DB.ExecContext(c.R.Context(), `DELETE FROM settings WHERE key = ? AND key != 'general'`, c.Param("key")); err != nil {
		return err
	}
	a.audit(c.R.Context(), c.Actor, "setting.deleted", "Setting", 0, c.Param("key"), nil)
	return c.NoContent()
}

// ---- deploy --------------------------------------------------------------

func (a *App) deployJSON(ctx context.Context) Obj {
	cfg := a.Setting(ctx, "deploy")
	status := a.Setting(ctx, "deploy_status")
	return O("config", Redact(cfg), "frontend", Redact(a.Setting(ctx, "frontend")), "last", status,
		"configured", str(cfg["hook_url"]) != "" || str(a.Setting(ctx, "frontend")["webhook_url"]) != "")
}

func (a *App) showDeploy(c *Ctx) error {
	if err := c.Need("settings:read"); err != nil {
		return err
	}
	d := a.deployJSON(c.R.Context())
	if last, ok := d.Get("last").(map[string]any); ok && len(last) > 0 {
		c.Summary = fmt.Sprintf("Last deploy: %s at %s.", str(last["status"]), str(last["at"]))
	} else {
		c.Summary = "No deploy has run yet."
	}
	c.Crumbs = []Crumb{crumb("Rebuild now", "cms deploy now")}
	return c.JSON(200, O("deploy", d))
}

func (a *App) updateDeploy(c *Ctx) error {
	if err := c.Need("settings:write"); err != nil {
		return err
	}
	var body map[string]any
	if err := c.Body(&body); err != nil {
		return err
	}
	data := body
	if d, ok := body["deploy"].(map[string]any); ok {
		data = d
	}
	if _, err := a.PutSetting(c.R.Context(), c.Actor, "deploy", data, false); err != nil {
		return err
	}
	return c.JSON(200, O("deploy", a.deployJSON(c.R.Context())))
}

func (a *App) triggerDeploy(c *Ctx) error {
	if err := c.Need("pages:publish"); err != nil {
		return err
	}
	status, err := a.Deploys.Trigger(c.R.Context(), "manual")
	a.audit(c.R.Context(), c.Actor, "deploy.triggered", "Deploy", 0, "manual", nil)
	if err != nil {
		return &Error{Status: 502, Code: "deploy_failed", Message: err.Error(), Extra: map[string]any{"deploy": status}}
	}
	c.Summary = "Deploy " + str(status["status"]) + "."
	c.Crumbs = []Crumb{crumb("Whether it worked", "cms deploy")}
	return c.JSON(202, O("ok", true, "deploy", status))
}

func (a *App) showFrontend(c *Ctx) error {
	if err := c.Need("pages:read"); err != nil {
		return err
	}
	return c.JSON(200, O("frontend", Redact(a.Setting(c.R.Context(), "frontend")), "last_build", a.Setting(c.R.Context(), "frontend_build")))
}

// reportBuild: a build says how it renders and where purges go. Keeping a
// static site rebuilt on publish is taken as is; switching to purges, or
// moving where they go, waits for someone with settings:write.
func (a *App) reportBuild(c *Ctx) error {
	if err := c.Need("pages:read"); err != nil {
		return err
	}
	var body map[string]any
	if err := c.Body(&body); err != nil {
		return err
	}
	report := map[string]any{"render": body["render"], "webhook_url": body["webhook_url"], "content_cursor": body["content_cursor"],
		"reported_at": time.Now().UTC().Format(time.RFC3339), "by": c.Actor.Label()}
	if _, err := a.PutSetting(c.R.Context(), nil, "frontend_build", report, true); err != nil {
		return err
	}
	front := a.Setting(c.R.Context(), "frontend")
	pending := str(body["render"]) != "static" && (str(front["render"]) != str(body["render"]) || str(front["webhook_url"]) != str(body["webhook_url"]))
	if pending && c.can("settings:write") {
		a.PutSetting(c.R.Context(), c.Actor, "frontend", map[string]any{"render": body["render"], "webhook_url": body["webhook_url"]}, false)
		pending = false
	}
	return c.JSON(201, O("ok", true, "approval_pending", pending))
}

// ---- audit log -----------------------------------------------------------

func (a *App) listAudit(c *Ctx) error {
	if err := c.Need("audit_log:read"); err != nil {
		return err
	}
	where, args := []string{"1=1"}, []any{}
	if v := c.Query("actor"); v != "" {
		where, args = append(where, "actor_label LIKE ?"), append(args, "%"+v+"%")
	}
	if v := c.Query("action"); v != "" {
		where, args = append(where, "action LIKE ?"), append(args, v+"%")
	}
	if v := c.Query("target_type"); v != "" {
		where, args = append(where, "target_type = ?"), append(args, v)
	}
	page, per := c.paging(50, 200)
	cond := strings.Join(where, " AND ")
	var total int
	a.Store.DB.QueryRowContext(c.R.Context(), "SELECT count(*) FROM audit_logs WHERE "+cond, args...).Scan(&total)
	rows, err := a.Store.DB.QueryContext(c.R.Context(), `SELECT id, action, actor_type, actor_id, actor_label, target_type, target_id, target_label, metadata, ip, created_at
		FROM audit_logs WHERE `+cond+fmt.Sprintf(" ORDER BY id DESC LIMIT %d OFFSET %d", per, (page-1)*per), args...)
	if err != nil {
		return err
	}
	defer rows.Close()
	out := []Obj{}
	for rows.Next() {
		var id int64
		var action, actorLabel, targetLabel string
		var actorType, targetType, ip sql.NullString
		var actorID, targetID NullInt
		var meta JSON
		var at Time
		if err := rows.Scan(&id, &action, &actorType, &actorID, &actorLabel, &targetType, &targetID, &targetLabel, &meta, &ip, &at); err != nil {
			return err
		}
		out = append(out, O("id", id, "action", action, "actor", O("type", nullStr(actorType), "id", actorID, "label", actorLabel),
			"target", O("type", nullStr(targetType), "id", targetID, "label", targetLabel), "metadata", meta.Or("{}"), "ip", nullStr(ip), "created_at", at))
	}
	return c.JSON(200, O("audit_logs", out, "page", page, "per", per, "total", total))
}

// ---- trash ---------------------------------------------------------------

var trashKinds = []string{"page", "entry", "global", "asset"}

func (a *App) listTrash(c *Ctx) error {
	if err := c.Need("trash:read"); err != nil {
		return err
	}
	ctx := c.R.Context()
	type item struct {
		at  Time
		obj Obj
	}
	var items []item
	counts := O()
	if pages, err := a.Pages(ctx, "deleted_at IS NOT NULL"); err == nil {
		counts = append(counts, kv{"page", len(pages)})
		for _, p := range pages {
			items = append(items, item{p.DeletedAt, O("kind", "page", "id", p.ID, "label", p.Label(), "deleted_at", p.DeletedAt.ISO(), "created_at", p.CreatedAt.ISO(), "meta", O("path", p.Path, "status", p.Status))})
		}
	}
	if entries, err := a.Entries(ctx, "e.deleted_at IS NOT NULL"); err == nil {
		counts = append(counts, kv{"entry", len(entries)})
		for _, e := range entries {
			items = append(items, item{e.DeletedAt, O("kind", "entry", "id", e.ID, "label", e.Label(), "deleted_at", e.DeletedAt.ISO(), "created_at", e.CreatedAt.ISO(), "meta", O("collection", e.CollectionSlug, "slug", e.Slug, "status", e.Status))})
		}
	}
	if globals, err := a.Globals(ctx, "deleted_at IS NOT NULL"); err == nil {
		counts = append(counts, kv{"global", len(globals)})
		for _, g := range globals {
			items = append(items, item{g.DeletedAt, O("kind", "global", "id", g.ID, "label", g.Name, "deleted_at", g.DeletedAt.ISO(), "created_at", g.CreatedAt.ISO(), "meta", O("slug", g.Slug))})
		}
	}
	if assets, err := a.Assets(ctx, "a.deleted_at IS NOT NULL"); err == nil {
		counts = append(counts, kv{"asset", len(assets)})
		for _, as := range assets {
			items = append(items, item{as.DeletedAt, O("kind", "asset", "id", as.ID, "label", as.Filename, "deleted_at", as.DeletedAt.ISO(), "created_at", as.CreatedAt.ISO(), "meta", O("folder", as.Folder))})
		}
	}
	sort.Slice(items, func(i, j int) bool { return items[i].at.After(items[j].at.Time) })
	out := []Obj{}
	for _, it := range items {
		out = append(out, it.obj)
	}
	c.Summary = fmt.Sprintf("%d in the trash.", len(out))
	if len(out) > 0 {
		c.Crumbs = []Crumb{crumb("Restore one", fmt.Sprintf("cms restore %s %v", out[0].Get("kind"), out[0].Get("id")))}
	}
	return c.JSON(200, O("entries", out, "counts", counts, "kinds", trashKinds))
}

func (a *App) restoreTrash(c *Ctx) error {
	if err := c.Need("trash:write"); err != nil {
		return err
	}
	ctx := c.R.Context()
	id, err := c.IntParam("id")
	if err != nil {
		return err
	}
	switch kind := c.Param("kind"); kind {
	case "page", "entry":
		rec, err := a.contentByID(ctx, kind, id, true)
		if err != nil || !rec.DeletedAt.Valid {
			return errNotFound("Nothing in the trash by that id.")
		}
		if err := a.RestoreContent(ctx, c.Actor, rec); err != nil {
			return err
		}
	case "global":
		g, err := a.Globals(ctx, "id = ? AND deleted_at IS NOT NULL", id)
		if err != nil || len(g) == 0 {
			return errNotFound("Nothing in the trash by that id.")
		}
		var clash int
		a.Store.DB.QueryRowContext(ctx, `SELECT count(*) FROM globals WHERE slug = ? AND deleted_at IS NULL`, g[0].Slug).Scan(&clash)
		if clash > 0 {
			return errConflict("Another global has the slug " + g[0].Slug + " now.")
		}
		a.Store.DB.ExecContext(ctx, `UPDATE globals SET deleted_at = NULL WHERE id = ?`, id)
		a.audit(ctx, c.Actor, "global.restored", "Global", id, g[0].Name, nil)
	case "asset":
		if _, err := a.Store.DB.ExecContext(ctx, `UPDATE assets SET deleted_at = NULL WHERE id = ?`, id); err != nil {
			return err
		}
		a.audit(ctx, c.Actor, "asset.restored", "Asset", id, "", nil)
	default:
		return errNotFound("Trash has no kind " + kind + ": one of " + strings.Join(trashKinds, ", ") + ".")
	}
	return c.JSON(200, O("ok", true, "kind", c.Param("kind"), "id", id))
}

func (a *App) purgeTrash(c *Ctx) error {
	if err := c.Need("trash:write"); err != nil {
		return err
	}
	ctx := c.R.Context()
	id, err := c.IntParam("id")
	if err != nil {
		return err
	}
	switch kind := c.Param("kind"); kind {
	case "page", "entry":
		rec, err := a.contentByID(ctx, kind, id, true)
		if err != nil || !rec.DeletedAt.Valid {
			return errNotFound("Nothing in the trash by that id.")
		}
		if err := a.PurgeContent(ctx, c.Actor, rec); err != nil {
			return err
		}
	case "global":
		a.Store.DB.ExecContext(ctx, `DELETE FROM global_versions WHERE global_id = ?`, id)
		a.Store.DB.ExecContext(ctx, `DELETE FROM content_references WHERE owner_type = 'Global' AND owner_id = ?`, id)
		res, err := a.Store.DB.ExecContext(ctx, `DELETE FROM globals WHERE id = ? AND deleted_at IS NOT NULL`, id)
		if err != nil {
			return err
		}
		if n, _ := res.RowsAffected(); n == 0 {
			return errNotFound("Nothing in the trash by that id.")
		}
		a.audit(ctx, c.Actor, "global.purged", "Global", id, "", nil)
	case "asset":
		as, err := a.AssetByID(ctx, id, true)
		if err != nil || !as.DeletedAt.Valid {
			return errNotFound("Nothing in the trash by that id.")
		}
		if err := a.PurgeAsset(ctx, c.Actor, as); err != nil {
			return err
		}
	default:
		return errNotFound("Trash has no kind " + kind + ".")
	}
	return c.NoContent()
}

// ---- webhooks ------------------------------------------------------------

func (a *App) listWebhooks(c *Ctx) error {
	if err := c.Need("webhooks:read"); err != nil {
		return err
	}
	list, err := a.Hooks.list(c.R.Context(), "")
	if err != nil {
		return err
	}
	out := []Obj{}
	for _, h := range list {
		out = append(out, h.JSON())
	}
	return c.JSON(200, O("webhooks", out))
}

func (a *App) webhookByID(c *Ctx) (*Webhook, error) {
	id, err := c.IntParam("id")
	if err != nil {
		return nil, err
	}
	list, err := a.Hooks.list(c.R.Context(), "id = ?", id)
	if err != nil {
		return nil, err
	}
	if len(list) == 0 {
		return nil, errNotFound("Couldn't find webhook " + c.Param("id") + ".")
	}
	return list[0], nil
}

func (a *App) showWebhook(c *Ctx) error {
	if err := c.Need("webhooks:read"); err != nil {
		return err
	}
	h, err := a.webhookByID(c)
	if err != nil {
		return err
	}
	return c.JSON(200, O("webhook", h.JSON()))
}

func (a *App) saveWebhook(c *Ctx, h *Webhook, p map[string]any) (string, error) {
	creating := h.ID == 0
	secret := ""
	if creating {
		h.Active, h.Events, h.Headers, h.EventFilters = true, JSON("[]"), JSON("{}"), JSON("{}")
		secret = str(p["secret"])
		if secret == "" {
			secret = randomToken(32)
		}
		h.Secret = a.Secrets.Seal(secret)
	}
	if has(p, "name") {
		h.Name = strings.TrimSpace(str(p["name"]))
	}
	if has(p, "url") {
		h.URL = strings.TrimSpace(str(p["url"]))
	}
	if has(p, "active") {
		h.Active = boolOf(p["active"])
	}
	if has(p, "events") {
		h.Events = mustJSON(p["events"]).Or("[]")
	}
	if has(p, "headers") {
		old := h.Headers.Map()
		next := map[string]any{}
		if m, ok := p["headers"].(map[string]any); ok {
			keepMasked(next, old, m)
		}
		h.Headers = mustJSON(next)
	}
	if has(p, "event_filters") {
		h.EventFilters = mustJSON(p["event_filters"]).Or("{}")
	}
	inv := Invalid{}
	if h.Name == "" {
		inv.Add("name", "can't be blank")
	}
	if checkOutboundURL(h.URL) != nil {
		inv.Add("url", "must be an http(s) URL")
	}
	if err := inv.Err(); err != nil {
		return "", err
	}
	now := Now()
	if creating {
		res, err := a.Store.DB.ExecContext(c.R.Context(), `INSERT INTO webhooks (name, url, secret, events, headers, event_filters, active, created_at, updated_at) VALUES (?,?,?,?,?,?,?,?,?)`,
			h.Name, h.URL, h.Secret, string(h.Events), string(h.Headers), string(h.EventFilters), h.Active, now.DB(), now.DB())
		if err != nil {
			return "", err
		}
		h.ID, _ = res.LastInsertId()
		h.CreatedAt = now
	} else if _, err := a.Store.DB.ExecContext(c.R.Context(), `UPDATE webhooks SET name=?, url=?, events=?, headers=?, event_filters=?, active=?, updated_at=? WHERE id=?`,
		h.Name, h.URL, string(h.Events), string(h.Headers), string(h.EventFilters), h.Active, now.DB(), h.ID); err != nil {
		return "", err
	}
	h.UpdatedAt = now
	a.audit(c.R.Context(), c.Actor, map[bool]string{true: "webhook.created", false: "webhook.updated"}[creating], "Webhook", h.ID, h.Name, nil)
	return secret, nil
}

func (a *App) createWebhook(c *Ctx) error {
	if err := c.Need("webhooks:write"); err != nil {
		return err
	}
	p, err := c.Wrapped("webhook")
	if err != nil {
		return err
	}
	h := &Webhook{}
	secret, err := a.saveWebhook(c, h, p)
	if err != nil {
		return err
	}
	c.Summary = "Created. The signing secret is shown once: keep it with the receiver."
	return c.JSON(201, O("webhook", append(h.JSON(), kv{"secret", secret})))
}

func (a *App) updateWebhook(c *Ctx) error {
	if err := c.Need("webhooks:write"); err != nil {
		return err
	}
	h, err := a.webhookByID(c)
	if err != nil {
		return err
	}
	p, err := c.Wrapped("webhook")
	if err != nil {
		return err
	}
	if _, err := a.saveWebhook(c, h, p); err != nil {
		return err
	}
	return c.JSON(200, O("webhook", h.JSON()))
}

func (a *App) destroyWebhook(c *Ctx) error {
	if err := c.Need("webhooks:delete"); err != nil {
		return err
	}
	h, err := a.webhookByID(c)
	if err != nil {
		return err
	}
	a.Store.DB.ExecContext(c.R.Context(), `DELETE FROM webhook_deliveries WHERE webhook_id = ?`, h.ID)
	if _, err := a.Store.DB.ExecContext(c.R.Context(), `DELETE FROM webhooks WHERE id = ?`, h.ID); err != nil {
		return err
	}
	a.audit(c.R.Context(), c.Actor, "webhook.deleted", "Webhook", h.ID, h.Name, nil)
	return c.NoContent()
}

func (a *App) rotateWebhookSecret(c *Ctx) error {
	if err := c.Need("webhooks:write"); err != nil {
		return err
	}
	h, err := a.webhookByID(c)
	if err != nil {
		return err
	}
	secret := randomToken(32)
	if _, err := a.Store.DB.ExecContext(c.R.Context(), `UPDATE webhooks SET secret = ?, updated_at = ? WHERE id = ?`, a.Secrets.Seal(secret), Now().DB(), h.ID); err != nil {
		return err
	}
	a.audit(c.R.Context(), c.Actor, "webhook.secret_rotated", "Webhook", h.ID, h.Name, nil)
	return c.JSON(200, O("webhook", append(h.JSON(), kv{"secret", secret})))
}

func (a *App) testWebhook(c *Ctx) error {
	if err := c.Need("webhooks:write"); err != nil {
		return err
	}
	h, err := a.webhookByID(c)
	if err != nil {
		return err
	}
	status, err := a.Hooks.send(c.R.Context(), h, "webhook.test", O("message", "A test delivery from Libre Publish.", "webhook_id", h.ID))
	body := O("ok", err == nil && status >= 200 && status < 300, "response_status", status)
	if err != nil {
		body = append(body, kv{"error", err.Error()})
	}
	return c.JSON(200, body)
}

func (a *App) webhookDeliveries(c *Ctx) error {
	if err := c.Need("webhooks:read"); err != nil {
		return err
	}
	h, err := a.webhookByID(c)
	if err != nil {
		return err
	}
	rows, err := a.Store.DB.QueryContext(c.R.Context(), `SELECT id, event, response_status, success, duration_ms, error, created_at FROM webhook_deliveries WHERE webhook_id = ? ORDER BY id DESC LIMIT 100`, h.ID)
	if err != nil {
		return err
	}
	defer rows.Close()
	out := []Obj{}
	for rows.Next() {
		var id int64
		var event string
		var status, ms NullInt
		var ok bool
		var errText sql.NullString
		var at Time
		rows.Scan(&id, &event, &status, &ok, &ms, &errText, &at)
		out = append(out, O("id", id, "event", event, "response_status", status, "success", ok, "duration_ms", ms, "error", nullStr(errText), "created_at", at))
	}
	return c.JSON(200, O("deliveries", out))
}

// ---- service tokens ------------------------------------------------------

func (a *App) serviceTokenJSON(ctx context.Context, id int64) (Obj, error) {
	var name, prefix string
	var desc, ip sql.NullString
	var roleID int64
	var created, used, revoked Time
	err := a.Store.DB.QueryRowContext(ctx, `SELECT name, description, prefix, role_id, created_at, last_used_at, last_used_ip, revoked_at FROM service_tokens WHERE id = ?`, id).
		Scan(&name, &desc, &prefix, &roleID, &created, &used, &ip, &revoked)
	if err != nil {
		return nil, notFound(err)
	}
	roleName := ""
	if r, err := a.role(ctx, roleID); err == nil {
		roleName = r.Name
	}
	return O("id", id, "name", name, "description", nullStr(desc), "prefix", prefix, "role", O("id", roleID, "name", roleName),
		"created_at", created.ISO(), "last_used_at", used.ISO(), "last_used_ip", nullStr(ip), "revoked_at", revoked.ISO(), "active", !revoked.Valid), nil
}

func (a *App) listServiceTokens(c *Ctx) error {
	if err := c.Need("settings:read"); err != nil {
		return err
	}
	rows, err := a.Store.DB.QueryContext(c.R.Context(), `SELECT id FROM service_tokens ORDER BY id`)
	if err != nil {
		return err
	}
	var ids []int64
	for rows.Next() {
		var id int64
		rows.Scan(&id)
		ids = append(ids, id)
	}
	rows.Close()
	out := []Obj{}
	for _, id := range ids {
		if o, err := a.serviceTokenJSON(c.R.Context(), id); err == nil {
			out = append(out, o)
		}
	}
	roles, err := a.rolesList(c.R.Context())
	if err != nil {
		return err
	}
	roleNames := []Obj{}
	for _, r := range roles {
		roleNames = append(roleNames, O("id", r.ID, "name", r.Name))
	}
	return c.JSON(200, O("service_tokens", out, "roles", roleNames))
}

func (a *App) showServiceToken(c *Ctx) error {
	if err := c.Need("settings:read"); err != nil {
		return err
	}
	id, err := c.IntParam("id")
	if err != nil {
		return err
	}
	o, err := a.serviceTokenJSON(c.R.Context(), id)
	if err != nil {
		return err
	}
	return c.JSON(200, O("service_token", o))
}

// CreateServiceToken issues one on a role; the plaintext is returned once.
func (a *App) CreateServiceToken(ctx context.Context, actor *Actor, name, description string, roleID int64) (int64, string, error) {
	plain := "lps_" + randomToken(32)
	var by any
	if actor != nil && actor.UserID != 0 {
		by = actor.UserID
	}
	res, err := a.Store.DB.ExecContext(ctx, `INSERT INTO service_tokens (name, description, role_id, created_by_id, prefix, token, token_digest, created_at, updated_at) VALUES (?,?,?,?,?,?,?,?,?)`,
		name, description, roleID, by, plain[:12], a.Secrets.Seal(plain), digest(plain), Now().DB(), Now().DB())
	if err != nil {
		return 0, "", err
	}
	id, _ := res.LastInsertId()
	a.audit(ctx, actor, "service_token.created", "ServiceToken", id, name, nil)
	return id, plain, nil
}

func (a *App) createServiceToken(c *Ctx) error {
	if err := c.Need("settings:write"); err != nil {
		return err
	}
	var body map[string]any
	if err := c.Body(&body); err != nil {
		return err
	}
	p := body
	if s, ok := body["service_token"].(map[string]any); ok {
		p = s
	}
	name := strings.TrimSpace(str(p["name"]))
	if name == "" {
		return &Error{Status: 422, Code: "invalid", Message: "Validation failed", Errors: Invalid{"name": {"can't be blank"}}}
	}
	var role *Role
	var err error
	if id, ok := intOf(p["role_id"]); ok {
		role, err = a.role(c.R.Context(), id)
	} else {
		roleName := str(p["role"])
		if roleName == "" {
			roleName = "Production site"
		}
		role, err = a.roleByName(c.R.Context(), roleName)
	}
	if err != nil {
		return &Error{Status: 422, Code: "invalid", Message: "Validation failed", Errors: Invalid{"role": {"isn't a role"}}}
	}
	if role.System && !c.Actor.Role.System {
		return errForbidden(Wildcard)
	}
	id, plain, err := a.CreateServiceToken(c.R.Context(), c.Actor, name, str(p["description"]), role.ID)
	if err != nil {
		return err
	}
	o, _ := a.serviceTokenJSON(c.R.Context(), id)
	c.Summary = "Issued. The secret is shown once here: store it in the site's environment, never in a repo."
	return c.JSON(201, O("service_token", append(o, kv{"token", plain})))
}

func (a *App) revealServiceToken(c *Ctx) error {
	if err := c.Need("settings:write"); err != nil {
		return err
	}
	id, err := c.IntParam("id")
	if err != nil {
		return err
	}
	var sealed sql.NullString
	if err := a.Store.DB.QueryRowContext(c.R.Context(), `SELECT token FROM service_tokens WHERE id = ? AND revoked_at IS NULL`, id).Scan(&sealed); err != nil {
		return errNotFound("No active service token " + c.Param("id") + ".")
	}
	plain, ok := a.Secrets.Open(sealed.String)
	if !ok {
		return errConflict("This token can't be shown again (it was issued before this install's key): rotate it for a new one.")
	}
	o, _ := a.serviceTokenJSON(c.R.Context(), id)
	a.audit(c.R.Context(), c.Actor, "service_token.revealed", "ServiceToken", id, str(o.Get("name")), nil)
	return c.JSON(200, O("service_token", append(o, kv{"token", plain})))
}

func (a *App) rotateServiceToken(c *Ctx) error {
	if err := c.Need("settings:write"); err != nil {
		return err
	}
	id, err := c.IntParam("id")
	if err != nil {
		return err
	}
	plain := "lps_" + randomToken(32)
	res, err := a.Store.DB.ExecContext(c.R.Context(), `UPDATE service_tokens SET prefix = ?, token = ?, token_digest = ?, updated_at = ? WHERE id = ? AND revoked_at IS NULL`,
		plain[:12], a.Secrets.Seal(plain), digest(plain), Now().DB(), id)
	if err != nil {
		return err
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return errNotFound("No active service token " + c.Param("id") + ".")
	}
	o, _ := a.serviceTokenJSON(c.R.Context(), id)
	a.audit(c.R.Context(), c.Actor, "service_token.rotated", "ServiceToken", id, str(o.Get("name")), nil)
	c.Summary = "Rotated: the old secret stopped working just now."
	return c.JSON(200, O("service_token", append(o, kv{"token", plain})))
}

func (a *App) revokeServiceToken(c *Ctx) error {
	if err := c.Need("settings:write"); err != nil {
		return err
	}
	id, err := c.IntParam("id")
	if err != nil {
		return err
	}
	if _, err := a.Store.DB.ExecContext(c.R.Context(), `UPDATE service_tokens SET revoked_at = ?, token = NULL WHERE id = ? AND revoked_at IS NULL`, Now().DB(), id); err != nil {
		return err
	}
	o, err := a.serviceTokenJSON(c.R.Context(), id)
	if err != nil {
		return err
	}
	a.audit(c.R.Context(), c.Actor, "service_token.revoked", "ServiceToken", id, str(o.Get("name")), nil)
	return c.JSON(200, O("service_token", o))
}

// ---- users & roles -------------------------------------------------------

func (a *App) rolesList(ctx context.Context) ([]*Role, error) {
	rows, err := a.Store.DB.QueryContext(ctx, `SELECT id FROM roles ORDER BY system DESC, name`)
	if err != nil {
		return nil, err
	}
	var ids []int64
	for rows.Next() {
		var id int64
		rows.Scan(&id)
		ids = append(ids, id)
	}
	rows.Close()
	out := []*Role{}
	for _, id := range ids {
		if r, err := a.role(ctx, id); err == nil {
			out = append(out, r)
		}
	}
	return out, nil
}

func (a *App) listRoles(c *Ctx) error {
	if err := c.Need("roles:read"); err != nil {
		return err
	}
	roles, err := a.rolesList(c.R.Context())
	if err != nil {
		return err
	}
	catalog := []Obj{}
	for _, g := range Catalog {
		catalog = append(catalog, O("group", g.Group, "capabilities", g.Caps))
	}
	for _, g := range PluginCaps() {
		catalog = append(catalog, O("group", g.Group, "capabilities", g.Caps, "labels", g.Labels, "plugin", true))
	}
	return c.JSON(200, O("roles", roles, "catalog", catalog))
}

func (a *App) saveRole(c *Ctx, r *Role, p map[string]any) error {
	if has(p, "name") {
		r.Name = strings.TrimSpace(str(p["name"]))
	}
	if has(p, "description") {
		r.Description = str(p["description"])
	}
	if has(p, "permissions") {
		if r.System {
			return errConflict("The Administrator role holds everything; its permissions can't change.")
		}
		r.Permissions = []string{}
		all := AllCapabilities()
		for _, v := range asList(p["permissions"]) {
			if s := str(v); slices.Contains(all, s) {
				r.Permissions = append(r.Permissions, s)
			}
		}
	}
	if r.Name == "" {
		return &Error{Status: 422, Code: "invalid", Message: "Validation failed", Errors: Invalid{"name": {"can't be blank"}}}
	}
	perms := mustJSON(r.Permissions)
	now := Now()
	if r.ID == 0 {
		res, err := a.Store.DB.ExecContext(c.R.Context(), `INSERT INTO roles (name, description, permissions, system, created_at, updated_at) VALUES (?,?,?,0,?,?)`, r.Name, r.Description, string(perms), now.DB(), now.DB())
		if err != nil {
			return err
		}
		r.ID, _ = res.LastInsertId()
		r.CreatedAt = now
	} else if _, err := a.Store.DB.ExecContext(c.R.Context(), `UPDATE roles SET name=?, description=?, permissions=?, updated_at=? WHERE id=?`, r.Name, r.Description, string(perms), now.DB(), r.ID); err != nil {
		return err
	}
	r.UpdatedAt = now
	a.audit(c.R.Context(), c.Actor, "role.saved", "Role", r.ID, r.Name, map[string]any{"permissions": r.Permissions})
	return nil
}

func (a *App) createRole(c *Ctx) error {
	if err := c.Need("roles:write"); err != nil {
		return err
	}
	p, err := c.Wrapped("role")
	if err != nil {
		return err
	}
	r := &Role{Permissions: []string{}}
	if err := a.saveRole(c, r, p); err != nil {
		return err
	}
	return c.JSON(201, O("role", r))
}

func (a *App) updateRole(c *Ctx) error {
	if err := c.Need("roles:write"); err != nil {
		return err
	}
	id, err := c.IntParam("id")
	if err != nil {
		return err
	}
	r, err := a.role(c.R.Context(), id)
	if err != nil {
		return err
	}
	p, err := c.Wrapped("role")
	if err != nil {
		return err
	}
	if err := a.saveRole(c, r, p); err != nil {
		return err
	}
	return c.JSON(200, O("role", r))
}

func (a *App) destroyRole(c *Ctx) error {
	if err := c.Need("roles:delete"); err != nil {
		return err
	}
	id, err := c.IntParam("id")
	if err != nil {
		return err
	}
	r, err := a.role(c.R.Context(), id)
	if err != nil {
		return err
	}
	var users, tokens int
	a.Store.DB.QueryRowContext(c.R.Context(), `SELECT count(*) FROM users WHERE role_id = ?`, id).Scan(&users)
	a.Store.DB.QueryRowContext(c.R.Context(), `SELECT count(*) FROM service_tokens WHERE role_id = ? AND revoked_at IS NULL`, id).Scan(&tokens)
	if r.System || users > 0 || tokens > 0 {
		return errConflict(fmt.Sprintf("%s is in use (%d users, %d service tokens) or built in.", r.Name, users, tokens))
	}
	if _, err := a.Store.DB.ExecContext(c.R.Context(), `DELETE FROM roles WHERE id = ?`, id); err != nil {
		return err
	}
	a.audit(c.R.Context(), c.Actor, "role.deleted", "Role", id, r.Name, nil)
	return c.NoContent()
}

func (a *App) userJSON(ctx context.Context, id int64) (Obj, error) {
	var name, email string
	var roleID NullInt
	var created Time
	var totp bool
	if err := a.Store.DB.QueryRowContext(ctx, `SELECT name, email, role_id, totp_enabled, created_at FROM users WHERE id = ?`, id).Scan(&name, &email, &roleID, &totp, &created); err != nil {
		return nil, notFound(err)
	}
	var role any
	if roleID.Valid {
		if r, err := a.role(ctx, roleID.Int64); err == nil {
			role = O("id", r.ID, "name", r.Name)
		}
	}
	return O("id", id, "name", name, "email", email, "pending_email", a.pendingEmail(ctx, id), "role", role, "two_factor", totp, "created_at", created), nil
}

func (a *App) listUsers(c *Ctx) error {
	if err := c.Need("users:read"); err != nil {
		return err
	}
	rows, err := a.Store.DB.QueryContext(c.R.Context(), `SELECT id FROM users ORDER BY name`)
	if err != nil {
		return err
	}
	var ids []int64
	for rows.Next() {
		var id int64
		rows.Scan(&id)
		ids = append(ids, id)
	}
	rows.Close()
	out := []Obj{}
	for _, id := range ids {
		if o, err := a.userJSON(c.R.Context(), id); err == nil {
			out = append(out, o)
		}
	}
	return c.JSON(200, O("users", out))
}

// CreateUser makes a person who can sign in.
func (a *App) CreateUser(ctx context.Context, actor *Actor, name, email, password string, roleID int64) (int64, error) {
	inv := Invalid{}
	email = strings.ToLower(strings.TrimSpace(email))
	if strings.TrimSpace(name) == "" {
		inv.Add("name", "can't be blank")
	}
	if _, err := mail.ParseAddress(email); err != nil {
		inv.Add("email", "is invalid")
	}
	if len(password) < 10 {
		inv.Add("password", "is too short (minimum is 10 characters)")
	}
	var clash int
	a.Store.DB.QueryRowContext(ctx, `SELECT count(*) FROM users WHERE lower(email) = ?`, email).Scan(&clash)
	if clash > 0 {
		inv.Add("email", "has already been taken")
	}
	if err := inv.Err(); err != nil {
		return 0, err
	}
	hash, err := hashPassword(password)
	if err != nil {
		return 0, err
	}
	res, err := a.Store.DB.ExecContext(ctx, `INSERT INTO users (name, email, password_digest, role_id, verified, created_at, updated_at) VALUES (?,?,?,?,1,?,?)`,
		strings.TrimSpace(name), email, hash, roleID, Now().DB(), Now().DB())
	if err != nil {
		return 0, err
	}
	id, _ := res.LastInsertId()
	a.audit(ctx, actor, "user.created", "User", id, name, nil)
	return id, nil
}

func (a *App) createUser(c *Ctx) error {
	if err := c.Need("users:write"); err != nil {
		return err
	}
	p, err := c.Wrapped("user")
	if err != nil {
		return err
	}
	roleID, _ := intOf(p["role_id"])
	r, err := a.role(c.R.Context(), roleID)
	if err != nil {
		return &Error{Status: 422, Code: "invalid", Message: "Validation failed", Errors: Invalid{"role_id": {"isn't a role"}}}
	}
	if r.System && !c.Actor.Role.System {
		return errForbidden(Wildcard)
	}
	id, err := a.CreateUser(c.R.Context(), c.Actor, str(p["name"]), str(p["email"]), str(p["password"]), roleID)
	if err != nil {
		return err
	}
	o, _ := a.userJSON(c.R.Context(), id)
	return c.JSON(201, O("user", o))
}

func (a *App) updateUser(c *Ctx) error {
	id, err := c.IntParam("id")
	if err != nil {
		return err
	}
	// Anyone may change their own name and password.
	if id != c.Actor.UserID {
		if err := c.Need("users:write"); err != nil {
			return err
		}
	}
	p, err := c.Wrapped("user")
	if err != nil {
		return err
	}
	ctx := c.R.Context()
	if has(p, "name") && strings.TrimSpace(str(p["name"])) != "" {
		a.Store.DB.ExecContext(ctx, `UPDATE users SET name = ?, updated_at = ? WHERE id = ?`, strings.TrimSpace(str(p["name"])), Now().DB(), id)
	}
	// A new address waits for its confirmation link (account.go).
	if has(p, "email") && strings.TrimSpace(str(p["email"])) != "" {
		if err := a.requestEmailChange(ctx, c.Actor, id, str(p["email"])); err != nil {
			return err
		}
	}
	if pw := str(p["password"]); pw != "" {
		if len(pw) < 10 {
			return &Error{Status: 422, Code: "invalid", Message: "Validation failed", Errors: Invalid{"password": {"is too short (minimum is 10 characters)"}}}
		}
		if id == c.Actor.UserID {
			var current string
			a.Store.DB.QueryRowContext(ctx, `SELECT password_digest FROM users WHERE id = ?`, id).Scan(&current)
			if !checkPassword(current, str(p["current_password"])) {
				return &Error{Status: 422, Code: "invalid", Message: "Validation failed", Errors: Invalid{"current_password": {"is wrong"}}}
			}
		}
		hash, err := hashPassword(pw)
		if err != nil {
			return err
		}
		a.Store.DB.ExecContext(ctx, `UPDATE users SET password_digest = ?, updated_at = ? WHERE id = ?`, hash, Now().DB(), id)
		a.Store.DB.ExecContext(ctx, `DELETE FROM admin_sessions WHERE user_id = ? AND (? = 0 OR id != ?)`, id, sessionID(c), sessionID(c))
	}
	if roleID, ok := intOf(p["role_id"]); ok && c.can("users:write") {
		if id == c.Actor.UserID {
			return errConflict("You can't change your own role.")
		}
		r, err := a.role(ctx, roleID)
		if err != nil || (r.System && !c.Actor.Role.System) {
			return errForbidden(Wildcard)
		}
		a.Store.DB.ExecContext(ctx, `UPDATE users SET role_id = ?, updated_at = ? WHERE id = ?`, roleID, Now().DB(), id)
	}
	a.audit(ctx, c.Actor, "user.updated", "User", id, "", map[string]any{"keys": keysOf(p)})
	o, err := a.userJSON(ctx, id)
	if err != nil {
		return err
	}
	return c.JSON(200, O("user", o))
}

func sessionID(c *Ctx) int64 {
	if c.Actor.Session != nil {
		return c.Actor.Session.ID
	}
	return 0
}

func (a *App) destroyUser(c *Ctx) error {
	if err := c.Need("users:delete"); err != nil {
		return err
	}
	id, err := c.IntParam("id")
	if err != nil {
		return err
	}
	if id == c.Actor.UserID {
		return errConflict("You can't delete yourself.")
	}
	ctx := c.R.Context()
	err = a.Store.Tx(ctx, func(tx *sql.Tx) error {
		for _, s := range []string{`DELETE FROM api_tokens WHERE user_id = ?`, `DELETE FROM admin_sessions WHERE user_id = ?`, `DELETE FROM sessions WHERE user_id = ?`,
			`UPDATE page_versions SET author_id = NULL WHERE author_id = ?`, `UPDATE collection_entry_versions SET author_id = NULL WHERE author_id = ?`,
			`DELETE FROM device_authorizations WHERE user_id = ?`, `DELETE FROM users WHERE id = ?`} {
			if _, err := tx.ExecContext(ctx, s, id); err != nil {
				return err
			}
		}
		return nil
	})
	if err != nil {
		return err
	}
	a.audit(ctx, c.Actor, "user.deleted", "User", id, "", nil)
	return c.NoContent()
}

// ---- search & references -------------------------------------------------

func (a *App) search(c *Ctx) error {
	q := c.Query("q")
	if c.R.Method == http.MethodPost {
		var body map[string]any
		if err := c.Body(&body); err != nil {
			return err
		}
		q = str(firstOf(body, "query", "q"))
	}
	q = strings.TrimSpace(q)
	if q == "" {
		return errBadRequest("param is missing or the value is empty: query")
	}
	ctx := c.R.Context()
	like := "%" + q + "%"
	results := []Obj{}
	if c.can("pages:read") {
		where := "(title LIKE ? OR path LIKE ? OR blocks LIKE ? OR frontmatter LIKE ?)"
		if !c.can("pages:write") {
			where += " AND status = 'published'"
		}
		pages, err := a.Pages(ctx, where+" ORDER BY updated_at DESC LIMIT 25", like, like, like, like)
		if err != nil {
			return err
		}
		for _, p := range pages {
			results = append(results, O("type", "page", "id", p.ID, "title", p.Title, "path", p.Path, "status", p.Status, "snippet", snippet(string(p.Blocks), q)))
		}
	}
	if c.can("entries:read") {
		where := "(e.title LIKE ? OR e.slug LIKE ? OR e.body_markdown LIKE ? OR e.frontmatter LIKE ? OR e.blocks LIKE ?)"
		if !c.can("entries:write") {
			where += " AND e.status = 'published'"
		}
		entries, err := a.Entries(ctx, where+" ORDER BY e.updated_at DESC LIMIT 25", like, like, like, like, like)
		if err != nil {
			return err
		}
		for _, e := range entries {
			results = append(results, O("type", "entry", "id", e.ID, "title", e.Title, "path", e.CollectionSlug+"/"+e.Slug, "collection", e.CollectionSlug,
				"status", e.Status, "snippet", snippet(e.BodyMarkdown+" "+string(e.Frontmatter), q)))
		}
	}
	if c.can("globals:read") {
		globals, err := a.Globals(ctx, "(name LIKE ? OR slug LIKE ? OR data LIKE ?) LIMIT 10", like, like, like)
		if err != nil {
			return err
		}
		for _, g := range globals {
			results = append(results, O("type", "global", "id", g.ID, "title", g.Name, "path", g.Slug, "snippet", snippet(string(g.Data), q)))
		}
	}
	if c.can("assets:read") {
		assets, err := a.Assets(ctx, "(a.name LIKE ? OR a.alt LIKE ? OR b.filename LIKE ?) LIMIT 10", like, like, like)
		if err != nil {
			return err
		}
		for _, as := range assets {
			results = append(results, O("type", "asset", "id", as.ID, "title", as.Filename, "path", as.Folder, "snippet", as.Alt))
		}
	}
	c.Summary = fmt.Sprintf("%d results for %q.", len(results), q)
	return c.JSON(200, O("query", q, "results", results, "total", len(results)))
}

func snippet(text, q string) string {
	i := strings.Index(strings.ToLower(text), strings.ToLower(q))
	if i < 0 {
		return ""
	}
	start, end := max(0, i-60), min(len(text), i+len(q)+60)
	return strings.TrimSpace(text[start:end])
}

// references: GET /api/references?type=page&id=<path or id> — what points at
// a record.
func (a *App) references(c *Ctx) error {
	if err := c.Need("pages:read"); err != nil {
		return err
	}
	ctx := c.R.Context()
	typ, id := strings.ToLower(c.Query("type")), c.Query("id")
	if typ == "" || id == "" {
		return errBadRequest("Name the record: ?type=page|entry|asset|global&id=<id or path>.")
	}
	var refType, refID, label string
	switch typ {
	case "page":
		p, err := a.refPage(ctx, id)
		if err != nil {
			return err
		}
		refType, refID, label = "page", p.Path, "/"+p.Path
	case "entry", "collectionentry", "collection_entry":
		col, slug, ok := strings.Cut(id, "/")
		if !ok {
			n, err := strconv.ParseInt(id, 10, 64)
			if err != nil {
				return errBadRequest("An entry is named by collection/slug or its id.")
			}
			e, err := a.contentByID(ctx, "entry", n, false)
			if err != nil {
				return err
			}
			col, slug = e.CollectionSlug, e.Slug
		}
		refType, refID, label = col, slug, col+"/"+slug
	case "asset":
		refType, refID, label = "asset", id, "asset "+id
	case "url", "link":
		refType, refID, label = "url", id, id
	default:
		return errBadRequest("type is one of page, entry, asset, url.")
	}
	used, err := a.usedBy(c, refType, refID)
	if err != nil {
		return err
	}
	page, per := c.paging(50, 200)
	total := len(used)
	from, to := min((page-1)*per, total), min(page*per, total)
	c.Summary = fmt.Sprintf("%d %s point at %s.", total, plural(total, "record"), label)
	return c.JSON(200, O("references", used[from:to], "page", page, "per", per, "total", total, "total_pages", (total+per-1)/per))
}

func (a *App) refPage(ctx context.Context, id string) (*Content, error) {
	if n, err := strconv.ParseInt(id, 10, 64); err == nil {
		if p, err := a.contentByID(ctx, "page", n, false); err == nil {
			return p, nil
		}
	}
	return a.PageByPath(ctx, id, false)
}

func (a *App) managementSitemap(c *Ctx) error {
	if err := c.Need("pages:read"); err != nil {
		return err
	}
	urls, err := a.Sitemap(c.R.Context())
	if err != nil {
		return err
	}
	return c.JSON(200, O("urls", urls, "total", len(urls)))
}

// ---- backup --------------------------------------------------------------

// backup streams a .tar.gz: a consistent copy of the database and every
// uploaded file. Restoring is unpacking it into a data directory.
func (a *App) backup(c *Ctx) error {
	if err := c.Need("tools:use"); err != nil {
		return err
	}
	tmp, err := os.MkdirTemp("", "lp-backup-")
	if err != nil {
		return err
	}
	defer os.RemoveAll(tmp)
	snap := filepath.Join(tmp, "cms.sqlite3")
	if _, err := a.Store.DB.ExecContext(c.R.Context(), `VACUUM INTO ?`, snap); err != nil {
		return err
	}
	a.audit(c.R.Context(), c.Actor, "backup.downloaded", "Site", 0, "backup", nil)
	c.W.Header().Set("Content-Type", "application/gzip")
	c.W.Header().Set("Content-Disposition", fmt.Sprintf(`attachment; filename="librepublish-%s.tar.gz"`, time.Now().UTC().Format("20060102-150405")))
	gz := gzip.NewWriter(c.W)
	tw := tar.NewWriter(gz)
	add := func(path, name string) error {
		st, err := os.Stat(path)
		if err != nil {
			return err
		}
		hdr, _ := tar.FileInfoHeader(st, "")
		hdr.Name = name
		if err := tw.WriteHeader(hdr); err != nil {
			return err
		}
		f, err := os.Open(path)
		if err != nil {
			return err
		}
		defer f.Close()
		_, err = io.Copy(tw, f)
		return err
	}
	if err := add(snap, "cms.sqlite3"); err != nil {
		return err
	}
	root := filepath.Join(a.DataDir, "storage")
	filepath.WalkDir(root, func(p string, d fs.DirEntry, err error) error {
		if err != nil || d.IsDir() {
			return nil
		}
		rel, _ := filepath.Rel(a.DataDir, p)
		return add(p, filepath.ToSlash(rel))
	})
	tw.Close()
	return gz.Close()
}

// ---- device login (cms login) --------------------------------------------

const devicePollInterval = 5

func (a *App) deviceCode(c *Ctx) error {
	var body map[string]any
	c.Body(&body)
	purpose := str(body["purpose"])
	if purpose != "site" {
		purpose = "user"
	}
	device := randomToken(32)
	letters := "BCDFGHJKLMNPQRSTVWXZ"
	raw := randomBytes(8)
	code := make([]byte, 0, 9)
	for i, b := range raw {
		if i == 4 {
			code = append(code, '-')
		}
		code = append(code, letters[int(b)%len(letters)])
	}
	expires := TimeOf(time.Now().Add(15 * time.Minute))
	_, err := a.Store.DB.ExecContext(c.R.Context(), `INSERT INTO device_authorizations (device_code, user_code, hostname, label, purpose, expires_at, created_at, updated_at) VALUES (?,?,?,?,?,?,?,?)`,
		digest(device), string(code), str(body["hostname"]), str(body["label"]), purpose, expires.DB(), Now().DB(), Now().DB())
	if err != nil {
		return err
	}
	return c.JSON(200, O("status", "ok", "user_code", string(code), "device_code", device,
		"verification_url", a.BaseURL+"/cms/#/connect?code="+string(code), "interval", devicePollInterval,
		"expires_in", int(time.Until(expires.Time).Seconds()), "account", a.Hooks.tenant()))
}

func (a *App) deviceShow(c *Ctx) error {
	var host, label, purpose sql.NullString
	var expires Time
	err := a.Store.DB.QueryRowContext(c.R.Context(), `SELECT hostname, label, purpose, expires_at FROM device_authorizations WHERE user_code = ? AND approved_at IS NULL AND denied_at IS NULL`,
		strings.ToUpper(c.Param("code"))).Scan(&host, &label, &purpose, &expires)
	if err != nil || time.Now().After(expires.Time) {
		return errNotFound("That code has expired or was already used. Run `cms login` again.")
	}
	return c.JSON(200, O("hostname", nullStr(host), "label", nullStr(label), "purpose", nullStr(purpose)))
}

func (a *App) deviceApprove(c *Ctx) error {
	if c.Actor.UserID == 0 {
		return errForbidden("a person's sign-in")
	}
	var body map[string]any
	if err := c.Body(&body); err != nil {
		return err
	}
	code := strings.ToUpper(strings.TrimSpace(str(body["user_code"])))
	var purpose string
	if err := a.Store.DB.QueryRowContext(c.R.Context(), `SELECT purpose FROM device_authorizations WHERE user_code = ? AND approved_at IS NULL AND denied_at IS NULL AND expires_at > ?`, code, Now().DB()).Scan(&purpose); err != nil {
		return errNotFound("That code has expired or was already used.")
	}
	if purpose == "site" {
		if err := c.Need("settings:write"); err != nil {
			return err
		}
	}
	col := "approved_at"
	if body["approve"] != nil && !boolOf(body["approve"]) {
		col = "denied_at"
	}
	_, err := a.Store.DB.ExecContext(c.R.Context(), `UPDATE device_authorizations SET `+col+` = ?, user_id = ?, updated_at = ? WHERE user_code = ?`, Now().DB(), c.Actor.UserID, Now().DB(), code)
	if err != nil {
		return err
	}
	a.audit(c.R.Context(), c.Actor, "device."+strings.TrimSuffix(col, "_at"), "DeviceAuthorization", 0, code, nil)
	return c.JSON(200, O("ok", true, "status", strings.TrimSuffix(col, "_at")))
}

func (a *App) deviceToken(c *Ctx) error {
	var body map[string]any
	if err := c.Body(&body); err != nil {
		return err
	}
	fail := func(code string) error { return c.JSON(400, O("status", "error", "error", code)) }
	var id int64
	var purpose string
	var label, host sql.NullString
	var userID NullInt
	var approved, denied, expires Time
	err := a.Store.DB.QueryRowContext(c.R.Context(), `SELECT id, purpose, label, hostname, user_id, approved_at, denied_at, expires_at FROM device_authorizations WHERE device_code = ?`,
		digest(str(body["device_code"]))).Scan(&id, &purpose, &label, &host, &userID, &approved, &denied, &expires)
	switch {
	case err != nil:
		return fail("invalid_grant")
	case denied.Valid:
		return fail("access_denied")
	case time.Now().After(expires.Time):
		return fail("expired_token")
	case !approved.Valid:
		return c.JSON(200, O("status", "pending", "interval", devicePollInterval))
	}
	// One use: the code is spent once it hands out a credential.
	a.Store.DB.ExecContext(c.R.Context(), `DELETE FROM device_authorizations WHERE id = ?`, id)
	user, err := a.actorForUser(c.R.Context(), userID.Int64)
	if err != nil || user == nil {
		return fail("invalid_grant")
	}
	out := O("status", "ok")
	if purpose == "site" {
		role, err := a.roleByName(c.R.Context(), "Production site")
		if err != nil {
			return err
		}
		name := label.String
		if name == "" {
			name = "PRODUCTION"
		}
		_, plain, err := a.CreateServiceToken(c.R.Context(), user, name, "Issued by `cms login` on "+host.String, role.ID)
		if err != nil {
			return err
		}
		out = append(out, kv{"token", plain}, kv{"purpose", "site"}, kv{"token_name", name})
	} else {
		plain, err := a.userToken(c.R.Context(), user.UserID)
		if err != nil {
			return err
		}
		out = append(out, kv{"token", plain}, kv{"purpose", "user"})
	}
	return c.JSON(200, append(out, kv{"user", O("name", user.Name, "email", user.Email)}, kv{"account", a.Hooks.tenant()}, kv{"api_url", a.BaseURL}))
}

// ---- sessions (the admin) ------------------------------------------------

func (a *App) showSession(c *Ctx) error {
	var users int
	a.Store.DB.QueryRowContext(c.R.Context(), `SELECT count(*) FROM users`).Scan(&users)
	if c.Actor == nil || c.Actor.Session == nil {
		return c.JSON(200, O("signed_in", false, "needs_setup", users == 0, "site", str(a.general()["title"]), "version", Version))
	}
	caps := []string{}
	if c.Actor.Role != nil {
		caps = c.Actor.Role.Capabilities()
	}
	return c.JSON(200, O("signed_in", true, "csrf", c.Actor.Session.CSRF, "user", O("id", c.Actor.UserID, "name", c.Actor.Name, "email", c.Actor.Email, "pending_email", a.pendingEmail(c.R.Context(), c.Actor.UserID)),
		"capabilities", caps, "site", str(a.general()["title"]), "version", Version, "preferences", a.preferences(c.R.Context(), c.Actor.UserID)))
}

var signInLimiter = newRateLimiter(10)

func (a *App) createSession(c *Ctx) error {
	if ok, wait := signInLimiter.allow("signin:" + c.ip()); !ok {
		c.W.Header().Set("Retry-After", strconv.Itoa(wait))
		return &Error{Status: 429, Code: "rate_limited", Message: "Too many sign-in attempts. Try again in a minute."}
	}
	var body map[string]any
	if err := c.Body(&body); err != nil {
		return err
	}
	var id int64
	var hash string
	var totp bool
	err := a.Store.DB.QueryRowContext(c.R.Context(), `SELECT id, password_digest, totp_enabled FROM users WHERE lower(email) = lower(?)`, strings.TrimSpace(str(body["email"]))).Scan(&id, &hash, &totp)
	if err != nil || !checkPassword(hash, str(body["password"])) {
		return &Error{Status: 401, Code: "unauthorized", Message: "That email and password don't match."}
	}
	// Two-factor secrets were sealed with the Rails core's key, which this
	// core can't read: signing in on the password alone would quietly drop
	// the second factor, so it doesn't.
	if totp {
		return &Error{Status: 403, Code: "two_factor_unavailable", Message: "This account uses two-factor sign-in, which this core doesn't support yet. An administrator can turn it off with `librepublish user disable-2fa --email …`, knowingly."}
	}
	csrf, err := a.signIn(c, id)
	if err != nil {
		return err
	}
	user, _ := a.actorForUser(c.R.Context(), id)
	a.audit(c.R.Context(), user, "session.created", "User", id, user.Name, map[string]any{"ip": c.ip()})
	return c.JSON(201, O("signed_in", true, "csrf", csrf))
}

func (a *App) destroySession(c *Ctx) error {
	if c.Actor.Session != nil {
		a.Store.DB.ExecContext(c.R.Context(), `DELETE FROM admin_sessions WHERE id = ?`, c.Actor.Session.ID)
	}
	http.SetCookie(c.W, &http.Cookie{Name: sessionCookie, Value: "", Path: "/", MaxAge: -1})
	return c.NoContent()
}

// setup makes the first administrator, once, on an empty install.
func (a *App) setup(c *Ctx) error {
	var users int
	a.Store.DB.QueryRowContext(c.R.Context(), `SELECT count(*) FROM users`).Scan(&users)
	if users > 0 {
		return errForbidden("setup (this install already has an administrator)")
	}
	var body map[string]any
	if err := c.Body(&body); err != nil {
		return err
	}
	admin, err := a.roleByName(c.R.Context(), "Administrator")
	if err != nil {
		return err
	}
	id, err := a.CreateUser(c.R.Context(), nil, str(body["name"]), str(body["email"]), str(body["password"]), admin.ID)
	if err != nil {
		return err
	}
	if t := strings.TrimSpace(str(body["site"])); t != "" {
		a.PutSetting(c.R.Context(), nil, "general", map[string]any{"title": t}, false)
	}
	csrf, err := a.signIn(c, id)
	if err != nil {
		return err
	}
	return c.JSON(201, O("signed_in", true, "csrf", csrf))
}

// CreateUserWithRole is the command line's: a person on a role by name.
func (a *App) CreateUserWithRole(ctx context.Context, name, email, password, roleName string) (int64, error) {
	r, err := a.roleByName(ctx, roleName)
	if err != nil {
		return 0, fmt.Errorf("no role %q", roleName)
	}
	id, err := a.CreateUser(ctx, nil, name, email, password, r.ID)
	var e *Error
	if errors.As(err, &e) && e.Errors != nil {
		return 0, fmt.Errorf("%v", e.Errors)
	}
	return id, err
}

// CreateServiceTokenForRole is the command line's: a token on a role by name.
func (a *App) CreateServiceTokenForRole(ctx context.Context, name, roleName string) (string, error) {
	r, err := a.roleByName(ctx, roleName)
	if err != nil {
		return "", fmt.Errorf("no role %q", roleName)
	}
	_, plain, err := a.CreateServiceToken(ctx, nil, name, "Issued from the command line", r.ID)
	return plain, err
}

// brandBrief is the brief the owners wrote: voice, audience, facts, house
// style — the keys that are filled in.
func brandBrief(data map[string]any) map[string]any {
	out := map[string]any{}
	for _, k := range []string{"brand_voice", "audience", "key_facts", "style_notes"} {
		if v := strings.TrimSpace(str(data[k])); v != "" {
			out[k] = v
		}
	}
	return out
}

// DisableTwoFactor turns a user's second factor off: the command line's,
// for an account moved from the Rails core.
func (a *App) DisableTwoFactor(ctx context.Context, email string) error {
	res, err := a.Store.DB.ExecContext(ctx, `UPDATE users SET totp_enabled = 0, totp_secret = NULL, totp_enabled_at = NULL, recovery_code_digests = '[]', updated_at = ? WHERE lower(email) = lower(?)`, Now().DB(), email)
	if err != nil {
		return err
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return fmt.Errorf("no user %s", email)
	}
	a.audit(ctx, nil, "user.two_factor_disabled", "User", 0, email, nil)
	return nil
}

// SetPassword is the command line's way back in for someone locked out.
func (a *App) SetPassword(ctx context.Context, email, password string) error {
	if len(password) < 10 {
		return fmt.Errorf("the password needs at least 10 characters")
	}
	hash, err := hashPassword(password)
	if err != nil {
		return err
	}
	var id int64
	if err := a.Store.DB.QueryRowContext(ctx, `SELECT id FROM users WHERE lower(email) = lower(?)`, email).Scan(&id); err != nil {
		return fmt.Errorf("no user %s", email)
	}
	a.Store.DB.ExecContext(ctx, `UPDATE users SET password_digest = ?, updated_at = ? WHERE id = ?`, hash, Now().DB(), id)
	a.Store.DB.ExecContext(ctx, `DELETE FROM admin_sessions WHERE user_id = ?`, id)
	a.audit(ctx, nil, "user.password_reset", "User", id, email, map[string]any{"via": "command line"})
	return nil
}
