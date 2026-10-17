package cms

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"regexp"
	"slices"
	"strconv"
	"strings"
)

// Content is a page or a collection entry: the two share status, schedule,
// blocks, frontmatter, SEO, taxonomy and translations, and differ in where
// they live (a page in the tree, an entry in a collection).
type Content struct {
	Kind string // "page" or "entry"

	ID     int64
	Slug   string
	Title  string
	Status string
	Locale string

	// Pages
	Path     string
	ParentID NullInt
	Depth    int
	Schema   JSON

	// Entries
	CollectionID   int64
	CollectionSlug string
	BodyMarkdown   string

	Blocks             JSON
	Frontmatter        JSON
	Seo                JSON
	CategoryEntryID    NullInt
	TranslationGroupID NullInt
	LockVersion        int

	PublishAt, PublishedAt, UnpublishAt, DeletedAt, CreatedAt, UpdatedAt Time

	tagIDs []int64 // set by a write that names tag_ids
}

var Statuses = []string{"draft", "published", "archived"}

var contentSlugFormat = regexp.MustCompile(`^[a-z0-9][a-z0-9\-]*$`)

func (c *Content) table() string {
	if c.Kind == "page" {
		return "pages"
	}
	return "collection_entries"
}

// TaggableType is the Rails class name, as taggings and references store it.
func (c *Content) TaggableType() string {
	if c.Kind == "page" {
		return "Page"
	}
	return "CollectionEntry"
}

// Prefix is the capability resource: pages:… or entries:….
func (c *Content) Prefix() string {
	if c.Kind == "page" {
		return "pages"
	}
	return "entries"
}

func (c *Content) Live() bool { return c.Status == "published" && !c.DeletedAt.Valid }

func (c *Content) Label() string {
	if c.Kind == "page" {
		return c.Title + " (/" + c.Path + ")"
	}
	return c.Title + " (" + c.CollectionSlug + "/" + c.Slug + ")"
}

// Address is how the CLI names it: a page's path, an entry's collection/slug.
func (c *Content) Address() string {
	if c.Kind == "page" {
		return c.Path
	}
	return c.CollectionSlug + "/" + c.Slug
}

const pageCols = `id, slug, path, parent_id, depth, title, status, locale, blocks, frontmatter, seo, schema,
	category_entry_id, translation_group_id, lock_version, publish_at, published_at, unpublish_at, deleted_at, created_at, updated_at`

const entryCols = `e.id, e.slug, e.title, e.status, e.locale, e.blocks, e.frontmatter, e.seo, e.body_markdown, e.collection_id, c.slug,
	e.category_entry_id, e.translation_group_id, e.lock_version, e.publish_at, e.published_at, e.unpublish_at, e.deleted_at, e.created_at, e.updated_at`

func scanPage(rows interface{ Scan(...any) error }) (*Content, error) {
	p := &Content{Kind: "page"}
	err := rows.Scan(&p.ID, &p.Slug, &p.Path, &p.ParentID, &p.Depth, &p.Title, &p.Status, &p.Locale, &p.Blocks, &p.Frontmatter, &p.Seo, &p.Schema,
		&p.CategoryEntryID, &p.TranslationGroupID, &p.LockVersion, &p.PublishAt, &p.PublishedAt, &p.UnpublishAt, &p.DeletedAt, &p.CreatedAt, &p.UpdatedAt)
	p.normalize()
	return p, err
}

func scanEntry(rows interface{ Scan(...any) error }) (*Content, error) {
	e := &Content{Kind: "entry"}
	err := rows.Scan(&e.ID, &e.Slug, &e.Title, &e.Status, &e.Locale, &e.Blocks, &e.Frontmatter, &e.Seo, &e.BodyMarkdown, &e.CollectionID, &e.CollectionSlug,
		&e.CategoryEntryID, &e.TranslationGroupID, &e.LockVersion, &e.PublishAt, &e.PublishedAt, &e.UnpublishAt, &e.DeletedAt, &e.CreatedAt, &e.UpdatedAt)
	e.normalize()
	return e, err
}

func (c *Content) normalize() {
	c.Blocks = c.Blocks.Or("[]")
	c.Frontmatter = c.Frontmatter.Or("{}")
	c.Seo = c.Seo.Or("{}")
	c.Schema = c.Schema.Or(`{"fields":[]}`)
}

// Pages reads pages matching a WHERE clause (trashed ones excluded unless
// the clause says otherwise).
func (a *App) Pages(ctx context.Context, where string, args ...any) ([]*Content, error) {
	if where == "" {
		where = "1=1"
	}
	if !strings.Contains(where, "deleted_at") {
		where = scoped("deleted_at IS NULL", where)
	}
	rows, err := a.Store.DB.QueryContext(ctx, "SELECT "+pageCols+" FROM pages WHERE "+where, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []*Content{}
	for rows.Next() {
		p, err := scanPage(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, p)
	}
	return out, rows.Err()
}

func (a *App) Entries(ctx context.Context, where string, args ...any) ([]*Content, error) {
	if where == "" {
		where = "1=1"
	}
	if !strings.Contains(where, "deleted_at") {
		where = scoped("e.deleted_at IS NULL", where)
	}
	rows, err := a.Store.DB.QueryContext(ctx, "SELECT "+entryCols+" FROM collection_entries e JOIN collections c ON c.id = e.collection_id WHERE "+where, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []*Content{}
	for rows.Next() {
		e, err := scanEntry(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, e)
	}
	return out, rows.Err()
}

// scoped puts cond in front of a WHERE clause that may end in ORDER BY or
// LIMIT.
func scoped(cond, where string) string {
	cut := len(where)
	for _, kw := range []string{" ORDER BY ", " LIMIT "} {
		if i := strings.Index(where, kw); i >= 0 && i < cut {
			cut = i
		}
	}
	return cond + " AND (" + where[:cut] + ")" + where[cut:]
}

func one(list []*Content, err error) (*Content, error) {
	if err != nil {
		return nil, err
	}
	if len(list) == 0 {
		return nil, ErrNotFound
	}
	return list[0], nil
}

func (a *App) PageByPath(ctx context.Context, path string, liveOnly bool) (*Content, error) {
	where := "path = ?"
	if liveOnly {
		where += " AND status = 'published'"
	}
	p, err := one(a.Pages(ctx, where+" ORDER BY id LIMIT 1", strings.Trim(path, "/")))
	if errors.Is(err, ErrNotFound) {
		return nil, errNotFound("Couldn't find page " + path + ".")
	}
	return p, err
}

func (a *App) EntryBySlug(ctx context.Context, collectionID int64, slug string, liveOnly bool) (*Content, error) {
	where := "e.collection_id = ? AND e.slug = ?"
	if liveOnly {
		where += " AND e.status = 'published'"
	}
	e, err := one(a.Entries(ctx, where+" ORDER BY e.id LIMIT 1", collectionID, slug))
	if errors.Is(err, ErrNotFound) {
		return nil, errNotFound("Couldn't find entry " + slug + ".")
	}
	return e, err
}

func (a *App) contentByID(ctx context.Context, kind string, id int64, withTrashed bool) (*Content, error) {
	trash := ""
	if withTrashed {
		trash = " AND (deleted_at IS NULL OR deleted_at IS NOT NULL)"
	}
	if kind == "page" {
		return one(a.Pages(ctx, "id = ?"+trash, id))
	}
	if withTrashed {
		trash = " AND (e.deleted_at IS NULL OR e.deleted_at IS NOT NULL)"
	}
	return one(a.Entries(ctx, "e.id = ?"+trash, id))
}

// ---- taxonomy & translations ---------------------------------------------

func (a *App) taxonomy(ctx context.Context, c *Content) (category any, tags []Obj, err error) {
	tags = []Obj{}
	if c.CategoryEntryID.Valid {
		var id int64
		var slug, title string
		err := a.Store.DB.QueryRowContext(ctx, `SELECT id, slug, title FROM collection_entries WHERE id = ? AND deleted_at IS NULL`, c.CategoryEntryID.Int64).Scan(&id, &slug, &title)
		if err == nil {
			category = O("id", id, "slug", slug, "title", title)
		} else if !errors.Is(err, sql.ErrNoRows) {
			return nil, nil, err
		}
	}
	rows, err := a.Store.DB.QueryContext(ctx, `SELECT e.id, e.slug, e.title FROM taggings t JOIN collection_entries e ON e.id = t.tag_entry_id
		WHERE t.taggable_type = ? AND t.taggable_id = ? AND e.deleted_at IS NULL ORDER BY t.position, t.id`, c.TaggableType(), c.ID)
	if err != nil {
		return nil, nil, err
	}
	defer rows.Close()
	for rows.Next() {
		var id int64
		var slug, title string
		if err := rows.Scan(&id, &slug, &title); err != nil {
			return nil, nil, err
		}
		tags = append(tags, O("id", id, "slug", slug, "title", title))
	}
	return category, tags, rows.Err()
}

// translations are the record's other languages that are live.
func (a *App) translations(ctx context.Context, c *Content) ([]Obj, error) {
	out := []Obj{}
	if !c.TranslationGroupID.Valid {
		return out, nil
	}
	var siblings []*Content
	var err error
	if c.Kind == "page" {
		siblings, err = a.Pages(ctx, "translation_group_id = ? AND id != ? AND status = 'published'", c.TranslationGroupID.Int64, c.ID)
	} else {
		siblings, err = a.Entries(ctx, "e.translation_group_id = ? AND e.id != ? AND e.status = 'published'", c.TranslationGroupID.Int64, c.ID)
	}
	if err != nil {
		return nil, err
	}
	for _, s := range siblings {
		out = append(out, O("locale", s.Locale, "path", a.PublicPath(s)))
	}
	return out, nil
}

// ---- addresses -----------------------------------------------------------

// PublicPath is where the record lives on the site: an SEO canonical when it
// has one, else its path under its locale's prefix ("home" is "/").
func (a *App) PublicPath(c *Content) string {
	seo := c.Seo.Map()
	if canon := strings.TrimSpace(str(seo["canonical_url"])); canon != "" {
		return canon
	}
	if canon := strings.TrimSpace(str(seo["canonical"])); canon != "" {
		return canon
	}
	path := "/" + c.Path
	if c.Kind == "entry" {
		path = "/" + c.CollectionSlug + "/" + c.Slug
	}
	if path == "/home" {
		path = "/"
	}
	def := a.defaultLocale()
	if c.Locale == "" || c.Locale == def {
		return path
	}
	prefix := "/" + c.Locale
	if path == prefix || strings.HasPrefix(path, prefix+"/") {
		return path
	}
	if path == "/" {
		return prefix
	}
	return prefix + path
}

func (a *App) PublicURL(c *Content) string {
	path := a.PublicPath(c)
	if strings.HasPrefix(path, "http://") || strings.HasPrefix(path, "https://") {
		return path
	}
	base := strings.TrimRight(strings.TrimSpace(str(a.general()["site_base_url"])), "/")
	if base == "" {
		return path
	}
	return base + path
}

// ---- answers -------------------------------------------------------------

// PageJSON is a whole page as /api has always answered it.
func (a *App) PageJSON(ctx context.Context, p *Content, blocks any) (Obj, error) {
	cat, tags, err := a.taxonomy(ctx, p)
	if err != nil {
		return nil, err
	}
	if blocks == nil {
		blocks = p.Blocks
	}
	return O("id", p.ID, "slug", p.Slug, "path", p.Path, "parent_id", p.ParentID, "depth", p.Depth, "title", p.Title,
		"status", p.Status, "locale", p.Locale, "blocks", blocks, "frontmatter", p.Frontmatter, "seo", p.Seo,
		"published_at", p.PublishedAt, "created_at", p.CreatedAt, "updated_at", p.UpdatedAt, "category", cat, "tags", tags), nil
}

func (a *App) PageSummaryJSON(ctx context.Context, p *Content) (Obj, error) {
	cat, tags, err := a.taxonomy(ctx, p)
	if err != nil {
		return nil, err
	}
	return O("id", p.ID, "slug", p.Slug, "path", p.Path, "parent_id", p.ParentID, "depth", p.Depth, "title", p.Title,
		"status", p.Status, "locale", p.Locale, "published_at", p.PublishedAt, "created_at", p.CreatedAt, "updated_at", p.UpdatedAt,
		"category", cat, "tags", tags), nil
}

func (a *App) EntryJSON(ctx context.Context, e *Content) (Obj, error) {
	cat, tags, err := a.taxonomy(ctx, e)
	if err != nil {
		return nil, err
	}
	return O("id", e.ID, "slug", e.Slug, "title", e.Title, "status", e.Status, "locale", e.Locale, "frontmatter", e.Frontmatter,
		"seo", e.Seo, "body_markdown", e.BodyMarkdown, "blocks", e.Blocks, "published_at", e.PublishedAt, "created_at", e.CreatedAt,
		"updated_at", e.UpdatedAt, "collection_slug", e.CollectionSlug, "category", cat, "tags", tags), nil
}

func (a *App) EntrySummaryJSON(ctx context.Context, e *Content) (Obj, error) {
	cat, tags, err := a.taxonomy(ctx, e)
	if err != nil {
		return nil, err
	}
	return O("id", e.ID, "slug", e.Slug, "title", e.Title, "status", e.Status, "locale", e.Locale, "published_at", e.PublishedAt,
		"created_at", e.CreatedAt, "updated_at", e.UpdatedAt, "category", cat, "tags", tags), nil
}

// ---- writing -------------------------------------------------------------

// contentKeys is what a write may set, as the Rails core permitted.
var pageKeys = []string{"slug", "title", "status", "locale", "published_at", "publish_at", "unpublish_at", "category_entry_id", "parent_id", "tag_ids", "blocks", "frontmatter", "seo", "translation_of"}
var entryKeys = []string{"slug", "title", "status", "locale", "body_markdown", "published_at", "publish_at", "unpublish_at", "category_entry_id", "tag_ids", "blocks", "frontmatter", "seo", "translation_of"}

func (c *Content) permitted() []string {
	if c.Kind == "page" {
		return pageKeys
	}
	return entryKeys
}

// assign applies the permitted keys of params to c.
func (c *Content) assign(params map[string]any) error {
	for _, key := range c.permitted() {
		v, ok := params[key]
		if !ok {
			continue
		}
		switch key {
		case "slug":
			c.Slug = strings.TrimSpace(str(v))
		case "title":
			c.Title = strings.TrimSpace(str(v))
		case "status":
			c.Status = str(v)
		case "locale":
			c.Locale = str(v)
		case "body_markdown":
			c.BodyMarkdown = str(v)
		case "published_at", "publish_at", "unpublish_at":
			var t Time
			if s := str(v); s != "" {
				if err := t.parse(s); err != nil {
					return &Error{Status: 422, Code: "invalid", Message: "Validation failed", Errors: Invalid{key: {"isn't a date and time"}}}
				}
			}
			switch key {
			case "published_at":
				c.PublishedAt = t
			case "publish_at":
				c.PublishAt = t
			default:
				c.UnpublishAt = t
			}
		case "category_entry_id", "parent_id":
			var n NullInt
			if id, ok := intOf(v); ok {
				n = IntOf(id)
			}
			if key == "parent_id" {
				c.ParentID = n
			} else {
				c.CategoryEntryID = n
			}
		case "tag_ids":
			c.tagIDs = []int64{}
			for _, t := range asList(v) {
				if id, ok := intOf(t); ok {
					c.tagIDs = append(c.tagIDs, id)
				}
			}
		case "blocks":
			if v == nil {
				v = []any{}
			}
			c.Blocks = mustJSON(normalizeBlocks(v))
		case "frontmatter", "seo":
			if v == nil {
				v = map[string]any{}
			}
			if key == "frontmatter" {
				c.Frontmatter = mustJSON(v)
			} else {
				c.Seo = mustJSON(v)
			}
		}
	}
	return nil
}

// normalizeBlocks gives each block an id, as the editor does, and keeps
// only a block's own keys.
func normalizeBlocks(v any) any {
	list, ok := v.([]any)
	if !ok {
		return v
	}
	out := make([]any, 0, len(list))
	for _, item := range list {
		b, ok := item.(map[string]any)
		if !ok {
			out = append(out, item)
			continue
		}
		block := map[string]any{"id": b["id"], "type": b["type"], "data": b["data"]}
		if str(b["id"]) == "" {
			block["id"] = randomToken(8)
		}
		if b["version"] != nil {
			block["version"] = b["version"]
		}
		if block["data"] == nil {
			block["data"] = map[string]any{}
		}
		out = append(out, block)
	}
	return out
}

func (a *App) blockTypeResolver(ctx context.Context) BlockTypes {
	cache := map[string][]Field{}
	rows, err := a.Store.DB.QueryContext(ctx, `SELECT slug, fields FROM block_types`)
	if err == nil {
		defer rows.Close()
		for rows.Next() {
			var slug string
			var fields JSON
			if rows.Scan(&slug, &fields) == nil {
				cache[slug] = ParseFields(fields)
			}
		}
	}
	return func(slug string) ([]Field, bool) {
		f, ok := cache[slug]
		return f, ok
	}
}

// contentFields is what a record's frontmatter is written against: its
// page's own schema, or its collection's.
func (a *App) contentFields(ctx context.Context, c *Content) []Field {
	if c.Kind == "page" {
		return ParseFields(c.Schema)
	}
	var schema JSON
	a.Store.DB.QueryRowContext(ctx, `SELECT schema FROM collections WHERE id = ?`, c.CollectionID).Scan(&schema)
	return ParseFields(schema)
}

func (a *App) validateContent(ctx context.Context, c *Content) error {
	inv := Invalid{}
	if c.Slug == "" {
		inv.Add("slug", "can't be blank")
	} else if !contentSlugFormat.MatchString(c.Slug) {
		inv.Add("slug", "is invalid: lowercase letters, numbers and hyphens, starting with a letter or number")
	}
	if c.Title == "" {
		inv.Add("title", "can't be blank")
	}
	if !slices.Contains(Statuses, c.Status) {
		inv.Add("status", "is not included in the list")
	}
	if c.Locale == "" {
		inv.Add("locale", "can't be blank")
	}
	if c.PublishAt.Valid && c.UnpublishAt.Valid && !c.UnpublishAt.After(c.PublishAt.Time) {
		inv.Add("unpublish_at", "must be after publish_at")
	}
	types := a.blockTypeResolver(ctx)
	var blocks []any
	if err := json.Unmarshal(c.Blocks, &blocks); err != nil {
		inv.Add("blocks", "must be a list of blocks")
	} else {
		ValidateBlocks(blocks, nil, types, inv, "blocks")
	}
	var fm map[string]any
	if err := json.Unmarshal(c.Frontmatter, &fm); err != nil {
		inv.Add("frontmatter", "must be an object")
	} else {
		ValidateData(a.contentFields(ctx, c), fm, types, inv, "frontmatter")
	}
	if !json.Valid(c.Seo) || !strings.HasPrefix(strings.TrimSpace(string(c.Seo)), "{") {
		inv.Add("seo", "must be an object")
	}

	db := a.Store.DB
	var clash int64
	if c.Kind == "page" {
		if c.ParentID.Valid {
			if c.ParentID.Int64 == c.ID {
				inv.Add("parent_id", "can't be the page itself")
			} else if c.ID != 0 {
				// Walk up from the new parent: meeting this page is a cycle.
				node := c.ParentID.Int64
				for i := 0; i < 64 && node != 0; i++ {
					if node == c.ID {
						inv.Add("parent_id", "can't be one of the page's own descendants")
						break
					}
					var parent NullInt
					if db.QueryRowContext(ctx, `SELECT parent_id FROM pages WHERE id = ?`, node).Scan(&parent) != nil {
						break
					}
					node = parent.Int64
				}
			}
			var exists int
			db.QueryRowContext(ctx, `SELECT count(*) FROM pages WHERE id = ? AND deleted_at IS NULL`, c.ParentID.Int64).Scan(&exists)
			if exists == 0 {
				inv.Add("parent_id", "isn't a page")
			}
		}
		err := db.QueryRowContext(ctx, `SELECT id FROM pages WHERE slug = ? AND parent_id IS ? AND id != ? AND deleted_at IS NULL LIMIT 1`, c.Slug, c.ParentID.DB(), c.ID).Scan(&clash)
		if err == nil {
			inv.Add("slug", "has already been taken")
		}
	} else {
		err := db.QueryRowContext(ctx, `SELECT id FROM collection_entries WHERE collection_id = ? AND slug = ? AND locale = ? AND id != ? AND deleted_at IS NULL LIMIT 1`, c.CollectionID, c.Slug, c.Locale, c.ID).Scan(&clash)
		if err == nil {
			inv.Add("slug", "has already been taken")
		}
	}
	if c.CategoryEntryID.Valid {
		if !a.inPool(ctx, c, "categories_collection_id", []int64{c.CategoryEntryID.Int64}) {
			inv.Add("category_entry_id", "isn't one of the categories")
		}
	}
	if c.tagIDs != nil && len(c.tagIDs) > 0 && !a.inPool(ctx, c, "tags_collection_id", c.tagIDs) {
		inv.Add("tag_ids", "aren't all tags")
	}
	return inv.Err()
}

// inPool: the ids are entries of the record's taxonomy pool (an entry's
// collection's categories or tags collection; for pages, any entries).
func (a *App) inPool(ctx context.Context, c *Content, poolColumn string, ids []int64) bool {
	args := []any{}
	for _, id := range ids {
		args = append(args, id)
	}
	query := `SELECT count(*) FROM collection_entries WHERE deleted_at IS NULL AND id IN (` + placeholders(len(ids)) + `)`
	if c.Kind == "entry" {
		var pool NullInt
		a.Store.DB.QueryRowContext(ctx, `SELECT `+poolColumn+` FROM collections WHERE id = ?`, c.CollectionID).Scan(&pool)
		if !pool.Valid {
			return false
		}
		query += ` AND collection_id = ?`
		args = append(args, pool.Int64)
	}
	var n int
	a.Store.DB.QueryRowContext(ctx, query, args...).Scan(&n)
	return n == len(ids)
}

// WriteResult is what a write did: saved (with the record), or held for a
// person (a revision).
type WriteResult struct {
	Record    *Content
	Held      *Revision
	Ignored   []string
	Unchanged bool
	Created   bool
}

// SaveContent creates or updates a page or entry from a write's params, as
// the actor. It enforces the publish gate: a write to something live, or one
// that publishes or schedules, needs <prefix>:publish. Without it a write to
// a live record is held as a revision for review, and one that would
// publish a draft is refused.
func (a *App) SaveContent(ctx context.Context, actor *Actor, rec *Content, params map[string]any) (*WriteResult, error) {
	creating := rec.ID == 0
	prior := *rec
	if creating {
		rec.Status = "draft"
		rec.Locale = a.defaultLocale()
		rec.normalize()
	}
	if err := rec.assign(params); err != nil {
		return nil, err
	}
	if rec.Kind == "page" {
		if err := a.computePath(ctx, rec); err != nil {
			return nil, err
		}
	}
	if err := a.validateContent(ctx, rec); err != nil {
		return nil, err
	}

	publishing := (rec.Status == "published" && prior.Status != "published") ||
		(rec.PublishAt.Valid && (!prior.PublishAt.Valid || !rec.PublishAt.Equal(prior.PublishAt.Time)))
	wasLive := !creating && prior.Status == "published"
	if (wasLive || publishing) && !actor.Can(rec.Prefix()+":publish") {
		if !wasLive {
			return nil, errForbidden(rec.Prefix() + ":publish")
		}
		return a.holdWrite(ctx, actor, &prior, params)
	}

	if !creating {
		if lv, ok := intOf(params["lock_version"]); ok && int(lv) != prior.LockVersion {
			return nil, &Error{Status: 409, Code: "conflict", Message: fmt.Sprintf("Someone else saved this since you read it (lock_version %d, now %d). Read it again and redo the change.", lv, prior.LockVersion)}
		}
		if contentEqual(&prior, rec) && rec.tagIDs == nil {
			return &WriteResult{Record: rec, Unchanged: true}, nil
		}
	}
	now := Now()
	if rec.Status == "published" && !rec.PublishedAt.Valid {
		rec.PublishedAt = now
	}
	if rec.Status == "published" && prior.Status != "published" {
		rec.PublishAt = Time{}
	}
	if tr, ok := intOf(params["translation_of"]); ok && creating {
		if err := a.joinTranslation(ctx, rec, tr); err != nil {
			return nil, err
		}
	}

	err := a.Store.Tx(ctx, func(tx *sql.Tx) error {
		if creating {
			rec.CreatedAt, rec.UpdatedAt = now, now
			var res sql.Result
			var err error
			if rec.Kind == "page" {
				res, err = tx.ExecContext(ctx, `INSERT INTO pages (slug, path, parent_id, depth, title, status, locale, blocks, frontmatter, seo, schema,
					category_entry_id, translation_group_id, publish_at, published_at, unpublish_at, created_at, updated_at)
					VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`,
					rec.Slug, rec.Path, rec.ParentID.DB(), rec.Depth, rec.Title, rec.Status, rec.Locale, string(rec.Blocks), string(rec.Frontmatter),
					string(rec.Seo), string(rec.Schema), rec.CategoryEntryID.DB(), rec.TranslationGroupID.DB(), rec.PublishAt.DB(), rec.PublishedAt.DB(),
					rec.UnpublishAt.DB(), now.DB(), now.DB())
			} else {
				res, err = tx.ExecContext(ctx, `INSERT INTO collection_entries (collection_id, slug, title, status, locale, body_markdown, blocks, frontmatter, seo,
					category_entry_id, translation_group_id, publish_at, published_at, unpublish_at, created_at, updated_at)
					VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`,
					rec.CollectionID, rec.Slug, rec.Title, rec.Status, rec.Locale, rec.BodyMarkdown, string(rec.Blocks), string(rec.Frontmatter),
					string(rec.Seo), rec.CategoryEntryID.DB(), rec.TranslationGroupID.DB(), rec.PublishAt.DB(), rec.PublishedAt.DB(),
					rec.UnpublishAt.DB(), now.DB(), now.DB())
			}
			if err != nil {
				return err
			}
			rec.ID, _ = res.LastInsertId()
		} else {
			rec.UpdatedAt = now
			rec.LockVersion = prior.LockVersion + 1
			var err error
			if rec.Kind == "page" {
				_, err = tx.ExecContext(ctx, `UPDATE pages SET slug=?, path=?, parent_id=?, depth=?, title=?, status=?, locale=?, blocks=?, frontmatter=?, seo=?,
					category_entry_id=?, translation_group_id=?, publish_at=?, published_at=?, unpublish_at=?, lock_version=?, updated_at=? WHERE id=?`,
					rec.Slug, rec.Path, rec.ParentID.DB(), rec.Depth, rec.Title, rec.Status, rec.Locale, string(rec.Blocks), string(rec.Frontmatter),
					string(rec.Seo), rec.CategoryEntryID.DB(), rec.TranslationGroupID.DB(), rec.PublishAt.DB(), rec.PublishedAt.DB(), rec.UnpublishAt.DB(),
					rec.LockVersion, now.DB(), rec.ID)
				if err == nil && rec.Path != prior.Path {
					err = resyncDescendants(ctx, tx, rec)
				}
			} else {
				_, err = tx.ExecContext(ctx, `UPDATE collection_entries SET slug=?, title=?, status=?, locale=?, body_markdown=?, blocks=?, frontmatter=?, seo=?,
					category_entry_id=?, translation_group_id=?, publish_at=?, published_at=?, unpublish_at=?, lock_version=?, updated_at=? WHERE id=?`,
					rec.Slug, rec.Title, rec.Status, rec.Locale, rec.BodyMarkdown, string(rec.Blocks), string(rec.Frontmatter), string(rec.Seo),
					rec.CategoryEntryID.DB(), rec.TranslationGroupID.DB(), rec.PublishAt.DB(), rec.PublishedAt.DB(), rec.UnpublishAt.DB(),
					rec.LockVersion, now.DB(), rec.ID)
			}
			if err != nil {
				return err
			}
		}
		if rec.tagIDs != nil {
			if err := writeTaggings(ctx, tx, rec); err != nil {
				return err
			}
		}
		if creating || string(prior.Blocks) != string(rec.Blocks) || string(prior.Frontmatter) != string(rec.Frontmatter) || prior.BodyMarkdown != rec.BodyMarkdown {
			if err := writeVersion(ctx, tx, rec, actor); err != nil {
				return err
			}
		}
		return a.writeReferences(ctx, tx, rec)
	})
	if err != nil {
		return nil, err
	}

	a.announce(ctx, actor, rec, &prior, creating)
	return &WriteResult{Record: rec, Created: creating}, nil
}

func contentEqual(a, b *Content) bool {
	return a.Slug == b.Slug && a.Title == b.Title && a.Status == b.Status && a.Locale == b.Locale && a.Path == b.Path &&
		a.ParentID == b.ParentID && a.BodyMarkdown == b.BodyMarkdown && jsonEqual(a.Blocks, b.Blocks) &&
		jsonEqual(a.Frontmatter, b.Frontmatter) && jsonEqual(a.Seo, b.Seo) && a.CategoryEntryID == b.CategoryEntryID &&
		a.PublishAt == b.PublishAt && a.PublishedAt == b.PublishedAt && a.UnpublishAt == b.UnpublishAt
}

func jsonEqual(x, y JSON) bool {
	var a, b any
	json.Unmarshal(x, &a)
	json.Unmarshal(y, &b)
	ja, _ := json.Marshal(a)
	jb, _ := json.Marshal(b)
	return string(ja) == string(jb)
}

func (a *App) computePath(ctx context.Context, p *Content) error {
	if p.Slug == "" {
		return nil
	}
	p.Path, p.Depth = p.Slug, 0
	if p.ParentID.Valid {
		var parentPath string
		var depth int
		err := a.Store.DB.QueryRowContext(ctx, `SELECT path, depth FROM pages WHERE id = ?`, p.ParentID.Int64).Scan(&parentPath, &depth)
		if err == nil {
			p.Path, p.Depth = parentPath+"/"+p.Slug, depth+1
		}
	}
	return nil
}

// resyncDescendants rewrites the paths under a page that moved or was
// renamed.
func resyncDescendants(ctx context.Context, tx *sql.Tx, p *Content) error {
	type node struct {
		id    int64
		path  string
		depth int
	}
	queue := []node{{p.ID, p.Path, p.Depth}}
	for visited := 0; len(queue) > 0 && visited < 10000; visited++ {
		n := queue[0]
		queue = queue[1:]
		rows, err := tx.QueryContext(ctx, `SELECT id, slug FROM pages WHERE parent_id = ?`, n.id)
		if err != nil {
			return err
		}
		var children []node
		for rows.Next() {
			var id int64
			var slug string
			rows.Scan(&id, &slug)
			children = append(children, node{id, n.path + "/" + slug, n.depth + 1})
		}
		rows.Close()
		for _, ch := range children {
			if _, err := tx.ExecContext(ctx, `UPDATE pages SET path = ?, depth = ?, updated_at = ? WHERE id = ?`, ch.path, ch.depth, Now().DB(), ch.id); err != nil {
				return err
			}
			queue = append(queue, ch)
		}
	}
	return nil
}

func writeTaggings(ctx context.Context, tx *sql.Tx, c *Content) error {
	if _, err := tx.ExecContext(ctx, `DELETE FROM taggings WHERE taggable_type = ? AND taggable_id = ?`, c.TaggableType(), c.ID); err != nil {
		return err
	}
	now := Now().DB()
	for i, id := range c.tagIDs {
		if _, err := tx.ExecContext(ctx, `INSERT INTO taggings (tag_entry_id, taggable_id, taggable_type, position, created_at, updated_at) VALUES (?,?,?,?,?,?)`,
			id, c.ID, c.TaggableType(), i, now, now); err != nil {
			return err
		}
	}
	return nil
}

func writeVersion(ctx context.Context, tx *sql.Tx, c *Content, actor *Actor) error {
	var author any
	if actor != nil && actor.UserID != 0 {
		author = actor.UserID
	}
	var err error
	if c.Kind == "page" {
		_, err = tx.ExecContext(ctx, `INSERT INTO page_versions (page_id, author_id, blocks, created_at) VALUES (?,?,?,?)`, c.ID, author, string(c.Blocks), Now().DB())
	} else {
		_, err = tx.ExecContext(ctx, `INSERT INTO collection_entry_versions (collection_entry_id, author_id, blocks, body_markdown, frontmatter, created_at) VALUES (?,?,?,?,?,?)`,
			c.ID, author, string(c.Blocks), c.BodyMarkdown, string(c.Frontmatter), Now().DB())
	}
	return err
}

// joinTranslation puts a new record in the translation group of the record
// it translates (making the group if that one had none).
func (a *App) joinTranslation(ctx context.Context, rec *Content, ofID int64) error {
	of, err := a.contentByID(ctx, rec.Kind, ofID, false)
	if err != nil {
		return &Error{Status: 422, Code: "invalid", Message: "Validation failed", Errors: Invalid{"translation_of": {"isn't a " + rec.Kind}}}
	}
	if of.Locale == rec.Locale {
		return &Error{Status: 422, Code: "invalid", Message: "Validation failed", Errors: Invalid{"locale": {"must differ from the record it translates"}}}
	}
	if !of.TranslationGroupID.Valid {
		res, err := a.Store.DB.ExecContext(ctx, `INSERT INTO translation_groups (kind, created_at, updated_at) VALUES (?,?,?)`, of.TaggableType(), Now().DB(), Now().DB())
		if err != nil {
			return err
		}
		id, _ := res.LastInsertId()
		of.TranslationGroupID = IntOf(id)
		if _, err := a.Store.DB.ExecContext(ctx, `UPDATE `+of.table()+` SET translation_group_id = ? WHERE id = ?`, id, of.ID); err != nil {
			return err
		}
	}
	rec.TranslationGroupID = of.TranslationGroupID
	return nil
}

// ---- trash ---------------------------------------------------------------

// TrashContent moves a record to the trash; a page takes its children.
func (a *App) TrashContent(ctx context.Context, actor *Actor, c *Content) error {
	now := Now()
	var trashed []*Content
	err := a.Store.Tx(ctx, func(tx *sql.Tx) error {
		ids := []int64{c.ID}
		if c.Kind == "page" {
			for i := 0; i < len(ids) && i < 10000; i++ {
				rows, err := tx.QueryContext(ctx, `SELECT id FROM pages WHERE parent_id = ? AND deleted_at IS NULL`, ids[i])
				if err != nil {
					return err
				}
				for rows.Next() {
					var id int64
					rows.Scan(&id)
					ids = append(ids, id)
				}
				rows.Close()
			}
		}
		for _, id := range ids {
			if _, err := tx.ExecContext(ctx, `UPDATE `+c.table()+` SET deleted_at = ?, updated_at = ? WHERE id = ?`, now.DB(), now.DB(), id); err != nil {
				return err
			}
		}
		return nil
	})
	if err != nil {
		return err
	}
	trashed = append(trashed, c)
	for _, t := range trashed {
		a.audit(ctx, actor, t.Kind+".trashed", t.TaggableType(), t.ID, t.Label(), nil)
		if t.Live() {
			a.contentEvent(ctx, t, "deleted")
		}
	}
	return nil
}

func (a *App) PurgeContent(ctx context.Context, actor *Actor, c *Content) error {
	err := a.Store.Tx(ctx, func(tx *sql.Tx) error {
		stmts := []string{
			`DELETE FROM taggings WHERE taggable_type = ? AND taggable_id = ?`,
			`DELETE FROM content_references WHERE owner_type = ? AND owner_id = ?`,
		}
		for _, s := range stmts {
			if _, err := tx.ExecContext(ctx, s, c.TaggableType(), c.ID); err != nil {
				return err
			}
		}
		if c.Kind == "page" {
			if _, err := tx.ExecContext(ctx, `UPDATE pages SET parent_id = NULL WHERE parent_id = ?`, c.ID); err != nil {
				return err
			}
			if _, err := tx.ExecContext(ctx, `DELETE FROM page_versions WHERE page_id = ?`, c.ID); err != nil {
				return err
			}
		} else {
			if _, err := tx.ExecContext(ctx, `DELETE FROM collection_entry_versions WHERE collection_entry_id = ?`, c.ID); err != nil {
				return err
			}
		}
		_, err := tx.ExecContext(ctx, `DELETE FROM `+c.table()+` WHERE id = ?`, c.ID)
		return err
	})
	if err == nil {
		a.audit(ctx, actor, c.Kind+".purged", c.TaggableType(), c.ID, c.Label(), nil)
		if c.Live() {
			a.contentEvent(ctx, c, "deleted")
		}
	}
	return err
}

func (a *App) RestoreContent(ctx context.Context, actor *Actor, c *Content) error {
	if c.Kind == "page" && c.ParentID.Valid {
		var parentGone int
		a.Store.DB.QueryRowContext(ctx, `SELECT count(*) FROM pages WHERE id = ? AND deleted_at IS NOT NULL`, c.ParentID.Int64).Scan(&parentGone)
		if parentGone > 0 {
			return errConflict("Its parent page is in the trash: restore that first.")
		}
	}
	var clash int
	if c.Kind == "page" {
		a.Store.DB.QueryRowContext(ctx, `SELECT count(*) FROM pages WHERE path = ? AND deleted_at IS NULL AND id != ?`, c.Path, c.ID).Scan(&clash)
	} else {
		a.Store.DB.QueryRowContext(ctx, `SELECT count(*) FROM collection_entries WHERE collection_id = ? AND slug = ? AND locale = ? AND deleted_at IS NULL AND id != ?`, c.CollectionID, c.Slug, c.Locale, c.ID).Scan(&clash)
	}
	if clash > 0 {
		return errConflict("Something else has its address now (" + c.Address() + ").")
	}
	// A page comes back with the children that went with it.
	deletedAt := c.DeletedAt
	err := a.Store.Tx(ctx, func(tx *sql.Tx) error {
		if _, err := tx.ExecContext(ctx, `UPDATE `+c.table()+` SET deleted_at = NULL, updated_at = ? WHERE id = ?`, Now().DB(), c.ID); err != nil {
			return err
		}
		if c.Kind == "page" && deletedAt.Valid {
			_, err := tx.ExecContext(ctx, `UPDATE pages SET deleted_at = NULL WHERE deleted_at = ? AND path LIKE ?`, deletedAt.DB(), c.Path+"/%")
			return err
		}
		return nil
	})
	if err == nil {
		c.DeletedAt = Time{}
		a.audit(ctx, actor, c.Kind+".restored", c.TaggableType(), c.ID, c.Label(), nil)
		if c.Live() {
			a.contentEvent(ctx, c, "published")
		}
	}
	return err
}

// ---- events --------------------------------------------------------------

// announce tells everyone who listens what a save did: the audit log,
// webhooks, the deploy, plugins.
func (a *App) announce(ctx context.Context, actor *Actor, rec, prior *Content, created bool) {
	var action, event string
	switch {
	case created:
		action = "created"
		if rec.Status == "published" {
			event = "published"
		}
	case rec.Status == "published" && prior.Status != "published":
		action, event = "published", "published"
	case rec.Status != "published" && prior.Status == "published":
		action, event = "unpublished", "unpublished"
	default:
		action = "updated"
		if rec.Status == "published" {
			event = "updated"
		}
	}
	a.audit(ctx, actor, rec.Kind+"."+action, rec.TaggableType(), rec.ID, rec.Label(), map[string]any{"path": rec.Address(), "status": rec.Status})
	if event != "" {
		a.contentEvent(ctx, rec, event)
	}
}

// contentEvent is a change the public site sees: webhooks get it, the site
// is rebuilt, plugins hear of it.
func (a *App) contentEvent(ctx context.Context, c *Content, what string) {
	name := c.Kind + "." + what
	payload := a.WebhookPayload(c)
	a.Hooks.Deliver(name, payload)
	a.Deploys.Changed(c.cacheTags()...)
	a.Plugins.Emit(name, payload)
}

func (c *Content) cacheTags() []string {
	if c.Kind == "page" {
		return []string{"page:" + c.Path, "pages", "sitemap"}
	}
	return []string{"entry:" + c.CollectionSlug + "/" + c.Slug, "collection:" + c.CollectionSlug, "sitemap"}
}

// WebhookPayload is a record's data in a content webhook, the keys
// contracts/webhook_contract.json holds the CMS to.
func (a *App) WebhookPayload(c *Content) Obj {
	if c.Kind == "page" {
		return O("id", c.ID, "slug", c.Slug, "path", c.Path, "url", a.PublicURL(c), "title", c.Title, "status", c.Status,
			"locale", c.Locale, "published_at", c.PublishedAt.ISO(), "updated_at", c.UpdatedAt.ISO())
	}
	return O("id", c.ID, "slug", c.Slug, "collection_slug", c.CollectionSlug, "url", a.PublicURL(c), "title", c.Title,
		"status", c.Status, "locale", c.Locale, "published_at", c.PublishedAt.ISO(), "updated_at", c.UpdatedAt.ISO())
}

// ---- references ----------------------------------------------------------

// writeReferences records what a record points at, for `cms refs` and the
// unused-media list, in the Rails core's content_references rows: a block's
// references at its index, the frontmatter's and SEO's at -1.
func (a *App) writeReferences(ctx context.Context, tx *sql.Tx, c *Content) error {
	types := a.blockTypeResolver(ctx)
	var rows []refRow
	for i, b := range c.Blocks.List() {
		var refs []Ref
		BlockRefs(b, types, &refs)
		rows = appendRefs(rows, refs, i)
	}
	var refs []Ref
	FieldRefs(a.contentFields(ctx, c), c.Frontmatter.Map(), types, &refs)
	if img, ok := c.Seo.Map()["og_image_id"].(string); ok && img != "" {
		refs = append(refs, Ref{"asset", "asset", img})
	}
	rows = appendRefs(rows, refs, -1)
	return replaceReferences(ctx, tx, c.TaggableType(), c.ID, rows)
}

type refRow struct {
	Ref
	Position int
}

func appendRefs(rows []refRow, refs []Ref, position int) []refRow {
	for _, r := range refs {
		rows = append(rows, refRow{r, position})
	}
	return rows
}

func replaceReferences(ctx context.Context, tx *sql.Tx, ownerType string, ownerID int64, rows []refRow) error {
	if _, err := tx.ExecContext(ctx, `DELETE FROM content_references WHERE owner_type = ? AND owner_id = ?`, ownerType, ownerID); err != nil {
		return err
	}
	for _, r := range rows {
		if _, err := tx.ExecContext(ctx, `INSERT INTO content_references (owner_type, owner_id, ref_type, ref_id, kind, position, created_at) VALUES (?,?,?,?,?,?,?)`,
			ownerType, ownerID, r.RefType, r.RefID, r.Kind, r.Position, Now().DB()); err != nil {
			return err
		}
	}
	return nil
}

// assetIDs is every asset the records point at.
func (a *App) assetIDs(ctx context.Context, ownerType string, ids []int64) []int64 {
	if len(ids) == 0 {
		return nil
	}
	args := []any{ownerType}
	for _, id := range ids {
		args = append(args, id)
	}
	rows, err := a.Store.DB.QueryContext(ctx, `SELECT DISTINCT ref_id FROM content_references WHERE ref_type = 'asset' AND owner_type = ? AND owner_id IN (`+placeholders(len(ids))+`)`, args...)
	if err != nil {
		return nil
	}
	defer rows.Close()
	var out []int64
	for rows.Next() {
		var s string
		rows.Scan(&s)
		if n, err := strconv.ParseInt(s, 10, 64); err == nil {
			out = append(out, n)
		}
	}
	return out
}
