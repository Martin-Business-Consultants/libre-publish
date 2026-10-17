package cms

import (
	"context"
	"encoding/base64"
	"fmt"
	"net/http"
	"slices"
	"sort"
	"strconv"
	"strings"
	"time"
)

// The delivery API, /api/v1: what a site reads to build and serve itself,
// read-only, frozen, and only ever what's live. One answer shape:
//
//	{"data": …, "meta": {…}, "included": {"assets": {id: asset}}}
//
// It's on unless Settings › General says otherwise: this core has no theme,
// so "website" (the Rails default, where a theme drew the site) serves only
// what's chosen, as "website_api" does.

func (a *App) deliveryRoutes(mux *http.ServeMux) {
	h := func(pattern string, fn HandlerFunc) {
		a.handle(mux, pattern, func(c *Ctx) error {
			key := c.ip()
			if c.Actor.ServiceID != 0 {
				key = fmt.Sprintf("svc:%d", c.Actor.ServiceID)
			} else if c.Actor.UserID != 0 {
				key = fmt.Sprintf("user:%d", c.Actor.UserID)
			}
			if ok, wait := a.limiter.allow(key); !ok {
				c.W.Header().Set("Retry-After", strconv.Itoa(wait))
				return &Error{Status: 429, Code: "rate_limited", Message: "Over the delivery API's rate limit (CMS_DELIVERY_RATE_LIMIT)."}
			}
			c.etag = true
			return fn(c)
		})
	}
	h("GET /api/v1/site", a.v1Site)
	h("GET /api/v1/content", a.v1Content)
	h("GET /api/v1/pages", a.v1Pages)
	h("GET /api/v1/pages/{path...}", a.v1Page)
	h("GET /api/v1/collections", a.v1Collections)
	h("GET /api/v1/collections/{slug}", a.v1Collection)
	h("GET /api/v1/collections/{slug}/entries", a.v1Entries)
	h("GET /api/v1/collections/{slug}/entries/{entry}", a.v1Entry)
	h("GET /api/v1/globals", a.v1Globals)
	h("GET /api/v1/globals/{slug}", a.v1Global)
	h("GET /api/v1/schema", a.v1Schema)
	h("GET /api/v1/sitemap", a.v1Sitemap)
	h("GET /api/v1/robots", a.v1Robots)
	h("GET /api/v1/robots.txt", a.v1RobotsTxt)
	h("GET /api/v1/redirects", a.v1Redirects)
	h("GET /api/v1/redirects.txt", a.v1RedirectsTxt)
	h("GET /api/v1/site_health", a.v1SiteHealth)
}

// ---- serving -------------------------------------------------------------

func (a *App) servingMode() string {
	switch m := str(a.general()["serving"]); m {
	case "website_api", "api_only":
		return m
	case "website":
		return "website_api"
	}
	return "api_only"
}

func (a *App) servesPages() bool {
	return a.servingMode() == "api_only" || boolOf(a.general()["api_pages"])
}

func (a *App) servesCollection(col *Collection) bool {
	return a.servingMode() == "api_only" || col.APIEnabled
}

func notServed(msg string) error { return errNotFound(msg) }

func requirePages(c *Ctx) error {
	if !c.App.servesPages() {
		return notServed("Pages aren't served over the API: Settings › General › How the site is served.")
	}
	return nil
}

// ---- the answer ----------------------------------------------------------

func (c *Ctx) deliver(data any, meta Obj, assets map[string]Obj, tags ...string) error {
	if meta == nil {
		meta = O()
	}
	body := O("data", data, "meta", meta)
	if assets != nil {
		body = body.Set("included", O("assets", assets))
	}
	if len(tags) > 0 {
		seen := []string{}
		for _, t := range tags {
			if t != "" && !slices.Contains(seen, t) {
				seen = append(seen, t)
			}
		}
		c.W.Header().Set("Cache-Tag", strings.Join(seen, ","))
	}
	return c.JSON(200, body)
}

func (c *Ctx) deliveryPaging(total int) (page, per int, meta Obj) {
	page, per = c.paging(50, 100)
	var next any
	if page*per < total {
		next = page + 1
	}
	return page, per, O("page", page, "per", per, "total", total, "next_page", next)
}

// ---- records as a site renders them --------------------------------------

func (a *App) v1PageJSON(ctx context.Context, p *Content) (Obj, error) {
	cat, tags, err := a.taxonomy(ctx, p)
	if err != nil {
		return nil, err
	}
	tr, err := a.translations(ctx, p)
	if err != nil {
		return nil, err
	}
	return O("id", p.ID, "path", p.Path, "slug", p.Slug, "title", p.Title, "locale", p.Locale, "url", a.PublicPath(p),
		"blocks", a.ExpandBlocks(ctx, p.Blocks.List(), true), "frontmatter", p.Frontmatter, "seo", p.Seo,
		"published_at", p.PublishedAt, "updated_at", p.UpdatedAt, "category", cat, "tags", tags, "translations", tr), nil
}

func (a *App) v1EntryJSON(ctx context.Context, e *Content) (Obj, error) {
	cat, tags, err := a.taxonomy(ctx, e)
	if err != nil {
		return nil, err
	}
	tr, err := a.translations(ctx, e)
	if err != nil {
		return nil, err
	}
	return O("id", e.ID, "slug", e.Slug, "title", e.Title, "locale", e.Locale, "collection", e.CollectionSlug, "url", a.PublicPath(e),
		"frontmatter", e.Frontmatter, "body_markdown", e.BodyMarkdown, "blocks", e.Blocks, "seo", e.Seo,
		"published_at", e.PublishedAt, "updated_at", e.UpdatedAt, "category", cat, "tags", tags, "translations", tr), nil
}

func v1GlobalJSON(g *Global) Obj {
	return O("id", g.ID, "slug", g.Slug, "name", g.Name, "data", Redact(g.Data.Map()), "updated_at", g.UpdatedAt)
}

func blockCacheTags(blocks []any) []string {
	var out []string
	for _, b := range blocks {
		m, ok := b.(map[string]any)
		if !ok {
			continue
		}
		switch str(m["type"]) {
		case "collection_list":
			if data, ok := m["data"].(map[string]any); ok && str(data["collection_slug"]) != "" {
				out = append(out, "collection:"+str(data["collection_slug"]))
			}
		case "contact_info":
			out = append(out, "site")
		case "pattern":
			out = append(out, "patterns")
		}
	}
	return out
}

// ---- block expansion -----------------------------------------------------

var contactKeys = []string{"title", "phone", "email", "address_line1", "city", "state", "zip"}
var entrySortable = []string{"published_at", "updated_at", "created_at", "title"}

// ExpandBlocks resolves what blocks pull in: a collection_list's entries, a
// contact_info's details, a synced pattern's blocks. live: only published
// entries, whatever the block says (the delivery API's).
func (a *App) ExpandBlocks(ctx context.Context, blocks []any, live bool) []any {
	blocks = a.withPatterns(ctx, blocks)
	out := make([]any, 0, len(blocks))
	for _, item := range blocks {
		b, ok := item.(map[string]any)
		if !ok {
			out = append(out, item)
			continue
		}
		data, _ := b["data"].(map[string]any)
		if data == nil {
			data = map[string]any{}
		}
		switch str(b["type"]) {
		case "collection_list":
			b["resolved"] = a.collectionList(ctx, data, live)
		case "contact_info":
			g := a.general()
			contact := map[string]any{}
			for _, k := range contactKeys {
				if v, ok := g[k]; ok {
					contact[k] = v
				}
			}
			b["resolved"] = map[string]any{"contact": contact}
		}
		out = append(out, b)
	}
	return out
}

func (a *App) withPatterns(ctx context.Context, blocks []any) []any {
	var out []any
	for _, item := range blocks {
		b, ok := item.(map[string]any)
		if !ok || str(b["type"]) != "pattern" {
			out = append(out, item)
			continue
		}
		data, _ := b["data"].(map[string]any)
		var pb JSON
		if a.Store.DB.QueryRowContext(ctx, `SELECT blocks FROM block_patterns WHERE slug = ?`, str(data["pattern"])).Scan(&pb) == nil {
			out = append(out, pb.List()...)
		}
	}
	if out == nil {
		out = []any{}
	}
	return out
}

func (a *App) collectionList(ctx context.Context, data map[string]any, live bool) map[string]any {
	slug := str(data["collection_slug"])
	col, err := a.CollectionBySlug(ctx, slug)
	if err != nil {
		return map[string]any{"error": "collection not found", "slug": slug, "entries": []any{}, "total": 0}
	}
	where, args := "e.collection_id = ?", []any{col.ID}
	if live || str(data["filter_status"]) != "any" {
		where += " AND e.status = 'published'"
	}
	if tags := str(data["filter_tags"]); tags != "" && col.TagsCollectionID.Valid {
		slugs := []any{}
		for _, s := range strings.Split(tags, ",") {
			if s = strings.TrimSpace(s); s != "" {
				slugs = append(slugs, s)
			}
		}
		if len(slugs) > 0 {
			where += ` AND (SELECT count(DISTINCT t.tag_entry_id) FROM taggings t JOIN collection_entries te ON te.id = t.tag_entry_id
				WHERE t.taggable_type = 'CollectionEntry' AND t.taggable_id = e.id AND te.collection_id = ? AND te.slug IN (` + placeholders(len(slugs)) + `)) = ?`
			args = append(append(append(args, col.TagsCollectionID.Int64), slugs...), len(slugs))
		}
	}
	sortBy := str(data["sort_by"])
	if !slices.Contains(entrySortable, sortBy) {
		sortBy = "published_at"
	}
	dir := "DESC"
	if str(data["sort_dir"]) == "asc" {
		dir = "ASC"
	}
	var total int
	a.Store.DB.QueryRowContext(ctx, "SELECT count(*) FROM collection_entries e WHERE e.deleted_at IS NULL AND "+where, args...).Scan(&total)
	q := where + fmt.Sprintf(" ORDER BY e.%s %s, e.id %s", sortBy, dir, dir)
	if limit, ok := intOf(data["limit"]); ok && limit > 0 {
		q += fmt.Sprintf(" LIMIT %d", limit)
	}
	list, err := a.Entries(ctx, q, args...)
	if err != nil {
		return map[string]any{"error": err.Error(), "entries": []any{}, "total": 0}
	}
	entries := []any{}
	for _, e := range list {
		cat, tags, _ := a.taxonomy(ctx, e)
		entries = append(entries, O("id", e.ID, "slug", e.Slug, "title", e.Title, "status", e.Status, "locale", e.Locale,
			"collection", e.CollectionSlug, "url", a.PublicPath(e), "frontmatter", e.Frontmatter, "seo", e.Seo,
			"published_at", e.PublishedAt, "updated_at", e.UpdatedAt, "category", cat, "tags", tags))
	}
	out := map[string]any{"collection": map[string]any{"slug": col.Slug, "name": col.Name}, "entries": entries, "total": total}
	if g := str(data["group_by"]); g != "" {
		out["groups"] = a.groupEntries(ctx, col, entries, g)
	}
	return out
}

func (a *App) groupEntries(ctx context.Context, col *Collection, entries []any, key string) []any {
	groups := []any{}
	bucket := func(match func(Obj) bool) []any {
		var out []any
		for _, e := range entries {
			if match(e.(Obj)) {
				out = append(out, e)
			}
		}
		return out
	}
	pool := func(id NullInt, multi bool) {
		if !id.Valid {
			return
		}
		refs, _ := a.Entries(ctx, "e.collection_id = ? AND e.status = 'published' ORDER BY e.title", id.Int64)
		for _, ref := range refs {
			b := bucket(func(e Obj) bool {
				if multi {
					for _, t := range e.Get("tags").([]Obj) {
						if t.Get("slug") == ref.Slug {
							return true
						}
					}
					return false
				}
				cat, _ := e.Get("category").(Obj)
				return cat != nil && cat.Get("slug") == ref.Slug
			})
			if len(b) > 0 {
				groups = append(groups, map[string]any{"key": ref.Slug, "label": ref.Title, "entries": b})
			}
		}
	}
	switch key {
	case "category":
		pool(col.CategoriesCollectionID, false)
	case "tags":
		pool(col.TagsCollectionID, true)
	default:
		order := []string{}
		byValue := map[string][]any{}
		for _, e := range entries {
			v := str(e.(Obj).Get("frontmatter").(JSON).Map()[key])
			if _, ok := byValue[v]; !ok {
				order = append(order, v)
			}
			byValue[v] = append(byValue[v], e)
		}
		for _, v := range order {
			groups = append(groups, map[string]any{"key": v, "label": v, "entries": byValue[v]})
		}
	}
	return groups
}

// ---- endpoints -----------------------------------------------------------

func (a *App) siteLocales(ctx context.Context) []string {
	locales := []string{a.defaultLocale()}
	rows, err := a.Store.DB.QueryContext(ctx, `SELECT DISTINCT locale FROM pages WHERE status = 'published' AND deleted_at IS NULL
		UNION SELECT DISTINCT locale FROM collection_entries WHERE status = 'published' AND deleted_at IS NULL`)
	if err == nil {
		defer rows.Close()
		for rows.Next() {
			var l string
			rows.Scan(&l)
			if l != "" && !slices.Contains(locales, l) {
				locales = append(locales, l)
			}
		}
	}
	return locales
}

func (a *App) v1Site(c *Ctx) error {
	if err := c.Need("pages:read"); err != nil {
		return err
	}
	g := a.general()
	contact := map[string]any{}
	for _, k := range contactKeys {
		if v, ok := g[k]; ok {
			contact[k] = v
		}
	}
	plugins, config := []string{}, map[string]any{}
	for _, p := range a.Plugins.List() {
		if p.Enabled {
			plugins = append(plugins, p.Key)
			if sc := p.Manifest.Map()["site_config"]; sc != nil {
				config[p.Key] = sc
			}
		}
	}
	return c.deliver(O("name", str(g["title"]), "url", str(g["site_base_url"]), "default_locale", a.defaultLocale(),
		"locales", a.siteLocales(c.R.Context()), "contact", contact, "plugins", plugins, "plugin_config", config, "api_version", "v1"),
		O("cms_url", a.BaseURL), nil, "site")
}

func (a *App) v1Pages(c *Ctx) error {
	if err := c.Need("pages:read"); err != nil {
		return err
	}
	if err := requirePages(c); err != nil {
		return err
	}
	ctx := c.R.Context()
	where, args := "status = 'published'", []any{}
	if l := c.Query("locale"); l != "" {
		where, args = where+" AND locale = ?", append(args, l)
	}
	var total int
	a.Store.DB.QueryRowContext(ctx, "SELECT count(*) FROM pages WHERE deleted_at IS NULL AND "+where, args...).Scan(&total)
	page, per, meta := c.deliveryPaging(total)
	list, err := a.Pages(ctx, where+fmt.Sprintf(" ORDER BY id LIMIT %d OFFSET %d", per, (page-1)*per), args...)
	if err != nil {
		return err
	}
	data, ids, tags := []Obj{}, []int64{}, []string{"pages"}
	for _, p := range list {
		o, err := a.v1PageJSON(ctx, p)
		if err != nil {
			return err
		}
		data = append(data, o)
		ids = append(ids, p.ID)
		tags = append(tags, "page:"+p.Path)
		tags = append(tags, blockCacheTags(p.Blocks.List())...)
	}
	return c.deliver(data, meta, a.resolveAssets(ctx, a.assetIDs(ctx, "Page", ids)), tags...)
}

func (a *App) v1Page(c *Ctx) error {
	if err := c.Need("pages:read"); err != nil {
		return err
	}
	if err := requirePages(c); err != nil {
		return err
	}
	ctx := c.R.Context()
	p, err := a.PageByPath(ctx, c.Param("path"), true)
	if err != nil {
		return err
	}
	o, err := a.v1PageJSON(ctx, p)
	if err != nil {
		return err
	}
	return c.deliver(o, nil, a.resolveAssets(ctx, a.assetIDs(ctx, "Page", []int64{p.ID})), append([]string{"page:" + p.Path}, blockCacheTags(p.Blocks.List())...)...)
}

func (a *App) servedCollections(ctx context.Context) ([]*Collection, error) {
	all, err := a.Collections(ctx, "1=1 ORDER BY slug")
	if err != nil {
		return nil, err
	}
	out := []*Collection{}
	for _, col := range all {
		if a.servesCollection(col) {
			out = append(out, col)
		}
	}
	return out, nil
}

func (a *App) v1CollectionJSON(col *Collection) Obj {
	return O("id", col.ID, "slug", col.Slug, "name", col.Name, "enable_blocks", col.EnableBlocks, "fields", col.FieldsJSON())
}

func (a *App) v1Collections(c *Ctx) error {
	if err := c.Need("collections:read"); err != nil {
		return err
	}
	list, err := a.servedCollections(c.R.Context())
	if err != nil {
		return err
	}
	data, tags := []Obj{}, []string{}
	for _, col := range list {
		data = append(data, a.v1CollectionJSON(col))
		tags = append(tags, "collection:"+col.Slug)
	}
	return c.deliver(data, nil, nil, tags...)
}

func (a *App) v1ServedCollection(c *Ctx) (*Collection, error) {
	col, err := a.CollectionBySlug(c.R.Context(), c.Param("slug"))
	if err != nil {
		return nil, err
	}
	if !a.servesCollection(col) {
		return nil, notServed("The " + col.Slug + " collection isn't served over the API: its settings › Available over the API.")
	}
	return col, nil
}

func (a *App) v1Collection(c *Ctx) error {
	if err := c.Need("collections:read"); err != nil {
		return err
	}
	col, err := a.v1ServedCollection(c)
	if err != nil {
		return err
	}
	return c.deliver(a.v1CollectionJSON(col), nil, nil, "collection:"+col.Slug)
}

func (a *App) v1Entries(c *Ctx) error {
	if err := c.Need("entries:read"); err != nil {
		return err
	}
	col, err := a.v1ServedCollection(c)
	if err != nil {
		return err
	}
	ctx := c.R.Context()
	where, args := "e.collection_id = ? AND e.status = 'published'", []any{col.ID}
	if l := c.Query("locale"); l != "" {
		where, args = where+" AND e.locale = ?", append(args, l)
	}
	var total int
	a.Store.DB.QueryRowContext(ctx, "SELECT count(*) FROM collection_entries e WHERE e.deleted_at IS NULL AND "+where, args...).Scan(&total)
	page, per, meta := c.deliveryPaging(total)
	list, err := a.Entries(ctx, where+fmt.Sprintf(" ORDER BY e.published_at DESC, e.id DESC LIMIT %d OFFSET %d", per, (page-1)*per), args...)
	if err != nil {
		return err
	}
	data, ids := []Obj{}, []int64{}
	for _, e := range list {
		o, err := a.v1EntryJSON(ctx, e)
		if err != nil {
			return err
		}
		data = append(data, o)
		ids = append(ids, e.ID)
	}
	return c.deliver(data, meta, a.resolveAssets(ctx, a.assetIDs(ctx, "CollectionEntry", ids)), "collection:"+col.Slug)
}

func (a *App) v1Entry(c *Ctx) error {
	if err := c.Need("entries:read"); err != nil {
		return err
	}
	col, err := a.v1ServedCollection(c)
	if err != nil {
		return err
	}
	ctx := c.R.Context()
	e, err := a.EntryBySlug(ctx, col.ID, c.Param("entry"), true)
	if err != nil {
		return err
	}
	o, err := a.v1EntryJSON(ctx, e)
	if err != nil {
		return err
	}
	return c.deliver(o, nil, a.resolveAssets(ctx, a.assetIDs(ctx, "CollectionEntry", []int64{e.ID})), "entry:"+col.Slug+"/"+e.Slug)
}

func (a *App) v1Globals(c *Ctx) error {
	if err := c.Need("globals:read"); err != nil {
		return err
	}
	if err := requirePages(c); err != nil {
		return err
	}
	ctx := c.R.Context()
	list, err := a.Globals(ctx, "1=1 ORDER BY slug")
	if err != nil {
		return err
	}
	data, ids, tags := []Obj{}, []int64{}, []string{}
	for _, g := range list {
		data = append(data, v1GlobalJSON(g))
		ids = append(ids, g.ID)
		tags = append(tags, "global:"+g.Slug)
	}
	return c.deliver(data, nil, a.resolveAssets(ctx, a.assetIDs(ctx, "Global", ids)), tags...)
}

func (a *App) v1Global(c *Ctx) error {
	if err := c.Need("globals:read"); err != nil {
		return err
	}
	if err := requirePages(c); err != nil {
		return err
	}
	ctx := c.R.Context()
	g, err := a.GlobalBySlug(ctx, c.Param("slug"))
	if err != nil {
		return err
	}
	return c.deliver(v1GlobalJSON(g), nil, a.resolveAssets(ctx, a.assetIDs(ctx, "Global", []int64{g.ID})), "global:"+g.Slug)
}

// v1Content is every live page, entry and global, or — given a previous
// read's cursor — what changed since, with what stopped being live.
func (a *App) v1Content(c *Ctx) error {
	if err := c.Need("pages:read"); err != nil {
		return err
	}
	ctx := c.R.Context()
	now := time.Now().UTC()
	var since *time.Time
	if cur := c.Query("since"); cur != "" {
		if raw, err := base64.RawURLEncoding.DecodeString(cur); err == nil {
			if t, err := time.Parse(time.RFC3339Nano, string(raw)); err == nil && now.Sub(t) < 30*24*time.Hour {
				since = &t
			}
		}
	}
	full := since == nil
	changed := func(col string) (string, []any) {
		if full {
			return "1=1", nil
		}
		return col + " > ?", []any{TimeOf(*since).DB()}
	}

	pages, entries, globals := []Obj{}, []Obj{}, []Obj{}
	removed := map[string][]any{"pages": {}, "entries": {}, "globals": {}}
	var pageIDs, entryIDs, globalIDs []int64

	if a.servesPages() {
		w, args := changed("updated_at")
		list, err := a.Pages(ctx, "status = 'published' AND "+w+" ORDER BY id", args...)
		if err != nil {
			return err
		}
		for _, p := range list {
			o, err := a.v1PageJSON(ctx, p)
			if err != nil {
				return err
			}
			pages = append(pages, o)
			pageIDs = append(pageIDs, p.ID)
		}
		if !full {
			gone, _ := a.Pages(ctx, "(deleted_at IS NOT NULL OR status != 'published') AND updated_at > ? AND (deleted_at IS NULL OR deleted_at IS NOT NULL)", TimeOf(*since).DB())
			for _, p := range gone {
				removed["pages"] = append(removed["pages"], O("id", p.ID, "path", p.Path))
			}
		}
	}
	if c.can("entries:read") {
		cols, err := a.servedCollections(ctx)
		if err != nil {
			return err
		}
		for _, col := range cols {
			w, args := changed("e.updated_at")
			list, err := a.Entries(ctx, "e.collection_id = ? AND e.status = 'published' AND "+w+" ORDER BY e.id", append([]any{col.ID}, args...)...)
			if err != nil {
				return err
			}
			for _, e := range list {
				o, err := a.v1EntryJSON(ctx, e)
				if err != nil {
					return err
				}
				entries = append(entries, o)
				entryIDs = append(entryIDs, e.ID)
			}
			if !full {
				gone, _ := a.Entries(ctx, "e.collection_id = ? AND (e.deleted_at IS NOT NULL OR e.status != 'published') AND e.updated_at > ? AND (e.deleted_at IS NULL OR e.deleted_at IS NOT NULL)", col.ID, TimeOf(*since).DB())
				for _, e := range gone {
					removed["entries"] = append(removed["entries"], O("id", e.ID, "collection", e.CollectionSlug, "slug", e.Slug))
				}
			}
		}
	}
	if c.can("globals:read") && a.servesPages() {
		w, args := changed("updated_at")
		list, err := a.Globals(ctx, w+" ORDER BY slug", args...)
		if err != nil {
			return err
		}
		for _, g := range list {
			globals = append(globals, v1GlobalJSON(g))
			globalIDs = append(globalIDs, g.ID)
		}
		if !full {
			gone, _ := a.Globals(ctx, "deleted_at IS NOT NULL AND deleted_at > ?", TimeOf(*since).DB())
			for _, g := range gone {
				removed["globals"] = append(removed["globals"], O("id", g.ID, "slug", g.Slug))
			}
		}
	}

	assets := map[string]Obj{}
	for k, v := range a.resolveAssets(ctx, a.assetIDs(ctx, "Page", pageIDs)) {
		assets[k] = v
	}
	for k, v := range a.resolveAssets(ctx, a.assetIDs(ctx, "CollectionEntry", entryIDs)) {
		assets[k] = v
	}
	for k, v := range a.resolveAssets(ctx, a.assetIDs(ctx, "Global", globalIDs)) {
		assets[k] = v
	}
	data := O("pages", pages, "entries", entries, "globals", globals)
	if !full {
		data = data.Set("removed", removed)
	}
	cursor := base64.RawURLEncoding.EncodeToString([]byte(now.Format(time.RFC3339Nano)))
	// The tag stands for the content it was built from, not the bytes: each
	// read carries a fresh cursor.
	c.etagFrom = a.contentVersion(ctx) + "|" + c.Query("since") + "|" + fmt.Sprint(c.can("entries:read"), c.can("globals:read"))
	return c.deliver(data, O("cursor", cursor, "full", full, "since", c.Query("since")), assets, "content")
}

// contentVersion changes whenever anything /content is built from does.
func (a *App) contentVersion(ctx context.Context) string {
	var v string
	a.Store.DB.QueryRowContext(ctx, `SELECT
		COALESCE((SELECT max(updated_at) FROM pages), '') || '/' || (SELECT count(*) FROM pages) || '/' ||
		COALESCE((SELECT max(updated_at) FROM collection_entries), '') || '/' || (SELECT count(*) FROM collection_entries) || '/' ||
		COALESCE((SELECT max(updated_at) FROM globals), '') || '/' || COALESCE((SELECT max(deleted_at) FROM globals), '') || '/' ||
		COALESCE((SELECT max(updated_at) FROM collections), '') || '/' || COALESCE((SELECT max(updated_at) FROM assets), '') || '/' ||
		COALESCE((SELECT max(updated_at) FROM settings), '')`).Scan(&v)
	return v
}

func (a *App) v1Schema(c *Ctx) error {
	if err := c.Need("block_types:read"); err != nil {
		return err
	}
	ctx := c.R.Context()
	bts, err := a.BlockTypesList(ctx, "1=1 ORDER BY slug")
	if err != nil {
		return err
	}
	blocks := map[string]any{}
	for _, b := range bts {
		s := b.Schema()
		s["$schema"] = "https://json-schema.org/draft/2020-12/schema"
		blocks[b.Slug] = s
	}
	cols, err := a.servedCollections(ctx)
	if err != nil {
		return err
	}
	collections := map[string]any{}
	for _, col := range cols {
		s := JSONSchema(col.Fields())
		s["title"] = col.Name
		collections[col.Slug] = s
	}
	globals := map[string]any{}
	if gs, err := a.Globals(ctx, "1=1"); err == nil {
		for _, g := range gs {
			s := JSONSchema(g.Fields())
			s["title"] = g.Name
			globals[g.Slug] = s
		}
	}
	pages := map[string]any{}
	if ps, err := a.Pages(ctx, "status = 'published'"); err == nil {
		for _, p := range ps {
			if fs := ParseFields(p.Schema); len(fs) > 0 {
				pages[p.Path] = JSONSchema(fs)
			}
		}
	}
	seo := JSONSchema(ParseFields([]any{
		map[string]any{"name": "meta_title", "label": "Meta title", "type": "string"},
		map[string]any{"name": "meta_description", "label": "Meta description", "type": "text"},
		map[string]any{"name": "canonical_url", "label": "Canonical URL", "type": "url"},
		map[string]any{"name": "focus_keyword", "label": "Focus keyword", "type": "string"},
		map[string]any{"name": "noindex", "label": "Hide from search engines", "type": "boolean"},
		map[string]any{"name": "nofollow", "label": "Ask search engines not to follow links", "type": "boolean"},
		map[string]any{"name": "og_image_id", "label": "Social share image", "type": "asset"},
		map[string]any{"name": "og_title", "label": "Title override", "type": "string"},
		map[string]any{"name": "og_description", "label": "Description override", "type": "text"},
		map[string]any{"name": "og_type", "label": "Open Graph type", "type": "string"},
		map[string]any{"name": "twitter_card", "label": "Twitter card", "type": "string"},
		map[string]any{"name": "schema_type", "label": "schema.org type", "type": "string"},
	}))
	return c.deliver(O("$schema", "https://json-schema.org/draft/2020-12/schema", "blocks", blocks, "collections", collections,
		"globals", globals, "pages", pages, "seo", seo), nil, nil, "schema")
}

// Sitemap is every URL on the public site, with hreflang alternates.
func (a *App) Sitemap(ctx context.Context) ([]Obj, error) {
	var recs []*Content
	if a.servesPages() {
		ps, err := a.Pages(ctx, "status = 'published' ORDER BY path")
		if err != nil {
			return nil, err
		}
		recs = append(recs, ps...)
	}
	cols, err := a.servedCollections(ctx)
	if err != nil {
		return nil, err
	}
	for _, col := range cols {
		es, err := a.Entries(ctx, "e.collection_id = ? AND e.status = 'published' ORDER BY e.slug", col.ID)
		if err != nil {
			return nil, err
		}
		recs = append(recs, es...)
	}
	out := []Obj{}
	for _, r := range recs {
		seo := r.Seo.Map()
		if boolOf(seo["noindex"]) || boolOf(seo["exclude_from_sitemap"]) {
			continue
		}
		alts := []Obj{}
		tr, _ := a.translations(ctx, r)
		for _, t := range tr {
			alts = append(alts, O("hreflang", t.Get("locale"), "href", t.Get("path")))
		}
		out = append(out, O("loc", a.PublicURL(r), "path", a.PublicPath(r), "lastmod", r.UpdatedAt.ISO(), "locale", r.Locale,
			"type", r.Kind, "alternates", alts))
	}
	return out, nil
}

func (a *App) v1Sitemap(c *Ctx) error {
	if err := c.Need("pages:read"); err != nil {
		return err
	}
	urls, err := a.Sitemap(c.R.Context())
	if err != nil {
		return err
	}
	return c.deliver(urls, O("total", len(urls)), nil, "sitemap")
}

func (a *App) robotsText(ctx context.Context) (string, string) {
	s := a.Setting(ctx, "search")
	if custom := str(s["robots_txt"]); custom != "" {
		return custom, "custom"
	}
	text := "User-agent: *\nAllow: /\n"
	if base := strings.TrimRight(str(a.general()["site_base_url"]), "/"); base != "" {
		text += "\nSitemap: " + base + "/sitemap.xml\n"
	}
	return text, "generated"
}

func (a *App) v1Robots(c *Ctx) error {
	if err := c.Need("pages:read"); err != nil {
		return err
	}
	text, mode := a.robotsText(c.R.Context())
	return c.deliver(O("text", text, "mode", mode), nil, nil, "robots")
}

func (a *App) v1RobotsTxt(c *Ctx) error {
	if err := c.Need("pages:read"); err != nil {
		return err
	}
	text, _ := a.robotsText(c.R.Context())
	c.W.Header().Set("Content-Type", "text/plain; charset=utf-8")
	c.W.Header().Set("Cache-Tag", "robots")
	_, err := c.W.Write([]byte(text))
	return err
}

func (a *App) v1Redirects(c *Ctx) error {
	if err := c.Need("redirects:read"); err != nil {
		return err
	}
	list, err := a.orderedRedirects(c.R.Context())
	if err != nil {
		return err
	}
	data := []Obj{}
	for _, r := range list {
		data = append(data, O("source", r.Source, "destination", r.Destination, "status", r.Status, "wildcard", r.Wildcard))
	}
	return c.deliver(data, nil, nil, "redirects")
}

// orderedRedirects: exact rules first, then wildcards longest first, as an
// edge applies them.
func (a *App) orderedRedirects(ctx context.Context) ([]*Redirect, error) {
	list, err := a.Redirects(ctx, "active = 1")
	if err != nil {
		return nil, err
	}
	sort.SliceStable(list, func(i, j int) bool {
		if list[i].Wildcard != list[j].Wildcard {
			return !list[i].Wildcard
		}
		if list[i].Wildcard {
			return len(list[i].Source) > len(list[j].Source)
		}
		return list[i].ID < list[j].ID
	})
	return list, nil
}

// v1RedirectsTxt is a Cloudflare _redirects file.
func (a *App) v1RedirectsTxt(c *Ctx) error {
	if err := c.Need("redirects:read"); err != nil {
		return err
	}
	list, err := a.orderedRedirects(c.R.Context())
	if err != nil {
		return err
	}
	var b strings.Builder
	for _, r := range list {
		dest := r.Destination
		if r.Wildcard && !strings.Contains(dest, ":splat") && strings.HasSuffix(dest, "*") {
			dest = strings.TrimSuffix(dest, "*") + ":splat"
		}
		status := r.Status
		if status == 410 {
			status = 404
		}
		fmt.Fprintf(&b, "%s %s %d\n", r.Source, dest, status)
	}
	c.W.Header().Set("Content-Type", "text/plain; charset=utf-8")
	c.W.Header().Set("Cache-Tag", "redirects")
	_, err = c.W.Write([]byte(b.String()))
	return err
}

// ---- site health ---------------------------------------------------------

func (a *App) healthChecks(ctx context.Context) []Obj {
	var checks []Obj
	add := func(key, state, message string) {
		checks = append(checks, O("key", key, "state", state, "message", message))
	}
	g := a.general()
	if str(g["site_base_url"]) == "" {
		add("site_url", "fails", "Settings › General has no public site URL: webhooks and the sitemap can only give relative addresses.")
	} else {
		add("site_url", "passes", "The public site URL is set.")
	}
	pages, _ := a.Pages(ctx, "status = 'published'")
	var noDesc, longTitle []string
	for _, p := range pages {
		seo := p.Seo.Map()
		if str(seo["meta_description"]) == "" {
			noDesc = append(noDesc, p.Path)
		}
		if t := str(seo["meta_title"]); len([]rune(t)) > 60 || (t == "" && len([]rune(p.Title)) > 60) {
			longTitle = append(longTitle, p.Path)
		}
	}
	if len(noDesc) > 0 {
		add("meta_descriptions", "fails", fmt.Sprintf("%d live pages have no meta description: %s", len(noDesc), strings.Join(firstN(noDesc, 5), ", ")))
	} else {
		add("meta_descriptions", "passes", "Every live page has a meta description.")
	}
	if len(longTitle) > 0 {
		add("title_length", "yours_to_judge", fmt.Sprintf("%d page titles are over 60 characters: %s", len(longTitle), strings.Join(firstN(longTitle, 5), ", ")))
	} else {
		add("title_length", "passes", "Page titles fit in search results.")
	}
	var home int
	a.Store.DB.QueryRowContext(ctx, `SELECT count(*) FROM pages WHERE path = 'home' AND status = 'published' AND deleted_at IS NULL`).Scan(&home)
	if home == 0 {
		add("home_page", "fails", "There's no live page at \"home\" (the site's /).")
	} else {
		add("home_page", "passes", "The home page is live.")
	}
	var noAlt int
	a.Store.DB.QueryRowContext(ctx, `SELECT count(*) FROM assets a JOIN content_references r ON r.ref_type = 'asset' AND r.ref_id = CAST(a.id AS TEXT)
		JOIN active_storage_attachments att ON att.record_type = 'Asset' AND att.record_id = a.id JOIN active_storage_blobs b ON b.id = att.blob_id
		WHERE a.deleted_at IS NULL AND COALESCE(a.alt, '') = '' AND b.content_type LIKE 'image/%'`).Scan(&noAlt)
	if noAlt > 0 {
		add("image_alt", "fails", fmt.Sprintf("%d images in use have no alt text.", noAlt))
	} else {
		add("image_alt", "passes", "Every image in use has alt text.")
	}
	return checks
}

func firstN(l []string, n int) []string {
	if len(l) > n {
		return l[:n]
	}
	return l
}

func (a *App) v1SiteHealth(c *Ctx) error {
	if err := c.Need("pages:read"); err != nil {
		return err
	}
	return c.deliver(a.healthChecks(c.R.Context()), nil, nil, "site")
}

func (a *App) siteHealth(c *Ctx) error {
	if err := c.Need("pages:read"); err != nil {
		return err
	}
	checks := a.healthChecks(c.R.Context())
	fails := 0
	for _, ch := range checks {
		if ch.Get("state") == "fails" {
			fails++
		}
	}
	c.Summary = fmt.Sprintf("%d checks, %d failing.", len(checks), fails)
	return c.JSON(200, O("checks", checks, "failing", fails))
}
