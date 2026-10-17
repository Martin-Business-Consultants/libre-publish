package cms

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"strconv"
	"strings"
)

// ---- shaping a delivery answer -------------------------------------------

// What a site asks for, beside the records themselves:
//
//	?fields=title,slug,seo.meta_title   only those keys (and id) of each record
//	?include=assets,entries,pages       what the records point at, in
//	                                    "included" (assets by default;
//	                                    include=none for nothing)
//
// Lists also say how many there are in headers (X-Total-Count,
// X-Total-Pages and a Link with first, prev, next and last), and OPTIONS on a
// resource answers its JSON Schema.

// deliveryOwner is what a delivery answer's records are, for include=.
type deliveryOwner struct {
	typ string
	ids []int64
}

func (c *Ctx) owns(typ string, ids ...int64) { c.owner = &deliveryOwner{typ, ids} }

func (c *Ctx) includes() map[string]bool {
	raw := c.Query("include")
	if raw == "" {
		return map[string]bool{"assets": true}
	}
	out := map[string]bool{}
	for _, k := range strings.Split(raw, ",") {
		out[strings.TrimSpace(k)] = true
	}
	return out
}

// included is the "included" block: the assets the handler resolved, and
// the entries and pages the records point at, when asked for.
func (c *Ctx) included(assets map[string]Obj) Obj {
	inc := c.includes()
	out := O()
	if inc["assets"] && assets != nil {
		out = out.Set("assets", assets)
	}
	if c.owner != nil && (inc["entries"] || inc["pages"]) {
		entries, pages := c.App.referenced(c.R.Context(), c.owner.typ, c.owner.ids)
		if inc["entries"] {
			out = out.Set("entries", entries)
		}
		if inc["pages"] {
			out = out.Set("pages", pages)
		}
	}
	if len(out) == 0 {
		return nil
	}
	return out
}

// referenced is the live entries ({"<collection>/<slug>": entry}) and pages
// ({path: page}) that records point at through their fields and blocks.
func (a *App) referenced(ctx context.Context, ownerType string, ids []int64) (map[string]Obj, map[string]Obj) {
	entries, pages := map[string]Obj{}, map[string]Obj{}
	if len(ids) == 0 {
		return entries, pages
	}
	args := []any{ownerType}
	for _, id := range ids {
		args = append(args, id)
	}
	rows, err := a.Store.DB.QueryContext(ctx, `SELECT DISTINCT kind, ref_type, ref_id FROM content_references WHERE owner_type = ? AND kind IN ('record', 'page') AND owner_id IN (`+placeholders(len(ids))+`) LIMIT 500`, args...)
	if err != nil {
		return entries, pages
	}
	var refs [][3]string
	for rows.Next() {
		var r [3]string
		rows.Scan(&r[0], &r[1], &r[2])
		refs = append(refs, r)
	}
	rows.Close()
	cols := map[string]*Collection{}
	for _, r := range refs {
		switch r[0] {
		case "page":
			if p, err := a.PageByPath(ctx, r[2], true); err == nil && a.servesPages() {
				if o, err := a.v1PageJSON(ctx, p); err == nil {
					pages[p.Path] = o
				}
			}
		case "record":
			col, ok := cols[r[1]]
			if !ok {
				col, _ = a.CollectionBySlug(ctx, r[1])
				cols[r[1]] = col
			}
			if col == nil || !a.servesCollection(col) {
				continue
			}
			if e, err := a.EntryBySlug(ctx, col.ID, r[2], true); err == nil {
				if o, err := a.v1EntryJSON(ctx, e); err == nil {
					entries[col.Slug+"/"+e.Slug] = o
				}
			}
		}
	}
	return entries, pages
}

// sparse keeps only the asked-for keys of each record (id always): top
// level names, or dot paths into objects (seo.meta_title).
func (c *Ctx) sparse(data any) any {
	raw := strings.TrimSpace(c.Query("fields"))
	if raw == "" {
		return data
	}
	var paths [][]string
	for _, f := range strings.Split(raw, ",") {
		if f = strings.TrimSpace(f); f != "" {
			paths = append(paths, strings.Split(f, "."))
		}
	}
	pick := func(o Obj) Obj {
		var m map[string]any
		b, _ := json.Marshal(o)
		json.Unmarshal(b, &m)
		out := O("id", m["id"])
		for _, p := range paths {
			if p[0] == "id" && len(p) == 1 {
				continue
			}
			v, ok := digPath(m, p)
			if !ok {
				continue
			}
			if len(p) == 1 {
				out = out.Set(p[0], v)
				continue
			}
			// Rebuild the nesting: seo.meta_title → {"seo": {"meta_title": …}}.
			top, _ := out.Get(p[0]).(map[string]any)
			if top == nil {
				top = map[string]any{}
			}
			cur := top
			for _, k := range p[1 : len(p)-1] {
				next, _ := cur[k].(map[string]any)
				if next == nil {
					next = map[string]any{}
					cur[k] = next
				}
				cur = next
			}
			cur[p[len(p)-1]] = v
			out = out.Set(p[0], top)
		}
		return out
	}
	switch d := data.(type) {
	case Obj:
		return pick(d)
	case []Obj:
		out := make([]Obj, len(d))
		for i, o := range d {
			out[i] = pick(o)
		}
		return out
	}
	return data
}

func digPath(m map[string]any, path []string) (any, bool) {
	var cur any = m
	for _, k := range path {
		mm, ok := cur.(map[string]any)
		if !ok {
			return nil, false
		}
		if cur, ok = mm[k]; !ok {
			return nil, false
		}
	}
	return cur, true
}

// pagingHeaders says how many there are, and links the other pages.
func (c *Ctx) pagingHeaders(page, per, total int) {
	pages := (total + per - 1) / per
	if pages < 1 {
		pages = 1
	}
	h := c.W.Header()
	h.Set("X-Total-Count", strconv.Itoa(total))
	h.Set("X-Total-Pages", strconv.Itoa(pages))
	link := func(n int, rel string) string {
		q := c.R.URL.Query()
		q.Set("page", strconv.Itoa(n))
		q.Set("per", strconv.Itoa(per))
		u := url.URL{Path: c.R.URL.Path, RawQuery: q.Encode()}
		return fmt.Sprintf("<%s%s>; rel=%q", strings.TrimRight(c.App.BaseURL, "/"), u.String(), rel)
	}
	links := []string{link(1, "first")}
	if page > 1 {
		links = append(links, link(page-1, "prev"))
	}
	if page < pages {
		links = append(links, link(page+1, "next"))
	}
	links = append(links, link(pages, "last"))
	h.Set("Link", strings.Join(links, ", "))
}

// ---- OPTIONS: a resource's schema ----------------------------------------

var deliveryParams = O(
	"fields", "Comma-separated keys to keep (id always kept); dot paths reach into objects: seo.meta_title.",
	"include", "What to put in \"included\": assets (the default), entries, pages, or none.",
	"locale", "Only records in this locale.",
	"page", "The page of a list, from 1.",
	"per", "Records a page, at most 100.",
)

func (a *App) optionsAnswer(c *Ctx, resource string, list bool, item map[string]any) error {
	c.W.Header().Set("Allow", "GET, OPTIONS")
	schema := item
	if list {
		schema = map[string]any{"type": "array", "items": item}
	}
	params := deliveryParams
	if !list {
		params = O("fields", deliveryParams.Get("fields"), "include", deliveryParams.Get("include"))
	}
	return c.JSON(http.StatusOK, O("resource", resource, "methods", []string{"GET"}, "params", params,
		"schema", O("$schema", "https://json-schema.org/draft/2020-12/schema", "type", "object",
			"properties", O("data", schema, "meta", map[string]any{"type": "object"}, "included", map[string]any{"type": "object"}))))
}

func recordSchema(props map[string]any) map[string]any {
	base := map[string]any{
		"id": map[string]any{"type": "integer"}, "slug": map[string]any{"type": "string"}, "title": map[string]any{"type": "string"},
		"locale": map[string]any{"type": "string"}, "url": map[string]any{"type": "string"},
		"seo": seoSchema(), "published_at": map[string]any{"type": []string{"string", "null"}, "format": "date-time"},
		"updated_at": map[string]any{"type": "string", "format": "date-time"},
		"category":   map[string]any{"type": []string{"object", "null"}}, "tags": map[string]any{"type": "array"},
		"translations": map[string]any{"type": "array"},
	}
	for k, v := range props {
		base[k] = v
	}
	return map[string]any{"type": "object", "properties": base}
}

func (a *App) v1PagesOptions(c *Ctx) error {
	if err := c.Need("pages:read"); err != nil {
		return err
	}
	item := recordSchema(map[string]any{"path": map[string]any{"type": "string"}, "blocks": map[string]any{"type": "array", "description": "See /api/v1/schema for each block type."},
		"frontmatter": map[string]any{"type": "object", "description": "A page's own fields, when it has a schema."}})
	list := c.Param("path") == ""
	if !list {
		if p, err := a.PageByPath(c.R.Context(), c.Param("path"), true); err == nil {
			if fs := ParseFields(p.Schema); len(fs) > 0 {
				item["properties"].(map[string]any)["frontmatter"] = JSONSchema(fs)
			}
		}
	}
	return a.optionsAnswer(c, "pages", list, item)
}

func (a *App) v1EntriesOptions(c *Ctx) error {
	if err := c.Need("entries:read"); err != nil {
		return err
	}
	col, err := a.v1ServedCollection(c)
	if err != nil {
		return err
	}
	item := recordSchema(map[string]any{"collection": map[string]any{"const": col.Slug}, "frontmatter": JSONSchema(col.Fields()),
		"body_markdown": map[string]any{"type": "string"}, "blocks": map[string]any{"type": "array"}})
	return a.optionsAnswer(c, "collections/"+col.Slug+"/entries", c.Param("entry") == "", item)
}

func (a *App) v1GlobalOptions(c *Ctx) error {
	if err := c.Need("globals:read"); err != nil {
		return err
	}
	g, err := a.GlobalBySlug(c.R.Context(), c.Param("slug"))
	if err != nil {
		return err
	}
	return a.optionsAnswer(c, "globals/"+g.Slug, false, map[string]any{"type": "object", "properties": map[string]any{
		"id": map[string]any{"type": "integer"}, "slug": map[string]any{"const": g.Slug}, "name": map[string]any{"type": "string"},
		"data": JSONSchema(g.Fields()), "updated_at": map[string]any{"type": "string", "format": "date-time"}}})
}

func seoSchema() map[string]any {
	return JSONSchema(ParseFields([]any{
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
}
