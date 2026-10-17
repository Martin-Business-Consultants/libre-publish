package cms

import (
	"context"
	"database/sql"
	"encoding/json"
	"regexp"
	"strings"
)

// ---- collections ---------------------------------------------------------

type Collection struct {
	ID                     int64
	Slug, Name, Icon       string
	APIEnabled             bool
	EnableBlocks           bool
	Schema, BuildConfig    JSON
	CategoriesCollectionID NullInt
	TagsCollectionID       NullInt
	CreatedAt, UpdatedAt   Time
}

var collectionSlugFormat = regexp.MustCompile(`^[a-z0-9][a-z0-9_\-]*$`)

const collectionCols = `id, slug, name, COALESCE(icon, ''), api_enabled, enable_blocks, schema, build_config, categories_collection_id, tags_collection_id, created_at, updated_at`

func (a *App) Collections(ctx context.Context, where string, args ...any) ([]*Collection, error) {
	if where == "" {
		where = "1=1"
	}
	rows, err := a.Store.DB.QueryContext(ctx, "SELECT "+collectionCols+" FROM collections WHERE "+where, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []*Collection{}
	for rows.Next() {
		c := &Collection{}
		if err := rows.Scan(&c.ID, &c.Slug, &c.Name, &c.Icon, &c.APIEnabled, &c.EnableBlocks, &c.Schema, &c.BuildConfig,
			&c.CategoriesCollectionID, &c.TagsCollectionID, &c.CreatedAt, &c.UpdatedAt); err != nil {
			return nil, err
		}
		c.Schema = c.Schema.Or(`{"fields":[]}`)
		c.BuildConfig = c.BuildConfig.Or("{}")
		out = append(out, c)
	}
	return out, rows.Err()
}

func (a *App) CollectionBySlug(ctx context.Context, slug string) (*Collection, error) {
	list, err := a.Collections(ctx, "slug = ?", slug)
	if err != nil {
		return nil, err
	}
	if len(list) == 0 {
		return nil, errNotFound("Couldn't find collection " + slug + ".")
	}
	return list[0], nil
}

func (c *Collection) Fields() []Field { return ParseFields(c.Schema) }

func (c *Collection) FieldsJSON() any {
	m := c.Schema.Map()
	if f, ok := m["fields"]; ok && f != nil {
		return f
	}
	return []any{}
}

func (a *App) CollectionJSON(ctx context.Context, c *Collection) Obj {
	var count int
	a.Store.DB.QueryRowContext(ctx, `SELECT count(*) FROM collection_entries WHERE collection_id = ? AND deleted_at IS NULL`, c.ID).Scan(&count)
	return O("id", c.ID, "slug", c.Slug, "name", c.Name, "enable_blocks", c.EnableBlocks, "schema", c.Schema, "build_config", c.BuildConfig,
		"categories_collection_id", c.CategoriesCollectionID, "tags_collection_id", c.TagsCollectionID, "created_at", c.CreatedAt,
		"updated_at", c.UpdatedAt, "api_enabled", c.APIEnabled, "frontmatter_json_schema", JSONSchema(c.Fields()), "entry_count", count)
}

// SaveCollection creates or updates one from {slug, name, enable_blocks,
// api_enabled, schema, build_config, categories_collection_id,
// tags_collection_id}.
func (a *App) SaveCollection(ctx context.Context, actor *Actor, c *Collection, p map[string]any) error {
	creating := c.ID == 0
	if creating {
		c.Schema, c.BuildConfig = JSON(`{"fields":[]}`), JSON("{}")
	}
	if has(p, "slug") {
		c.Slug = strings.TrimSpace(str(p["slug"]))
	}
	if has(p, "name") {
		c.Name = strings.TrimSpace(str(p["name"]))
	}
	if has(p, "icon") {
		c.Icon = str(p["icon"])
	}
	if has(p, "enable_blocks") {
		c.EnableBlocks = boolOf(p["enable_blocks"])
	}
	if has(p, "api_enabled") {
		c.APIEnabled = boolOf(p["api_enabled"])
	}
	if has(p, "build_config") {
		c.BuildConfig = mustJSON(p["build_config"]).Or("{}")
	}
	for _, k := range []string{"categories_collection_id", "tags_collection_id"} {
		if has(p, k) {
			var n NullInt
			if id, ok := intOf(p[k]); ok {
				n = IntOf(id)
			}
			if k == "categories_collection_id" {
				c.CategoriesCollectionID = n
			} else {
				c.TagsCollectionID = n
			}
		}
	}
	inv := Invalid{}
	if has(p, "schema") {
		c.Schema = normalizeSchema(p["schema"])
		ValidateDefinitions(c.Schema.Map()["fields"], false, inv, "schema.fields")
	}
	if c.Slug == "" || !collectionSlugFormat.MatchString(c.Slug) {
		inv.Add("slug", "is invalid: lowercase letters, numbers, - and _")
	}
	if c.Name == "" {
		inv.Add("name", "can't be blank")
	}
	var clash int
	a.Store.DB.QueryRowContext(ctx, `SELECT count(*) FROM collections WHERE slug = ? AND id != ?`, c.Slug, c.ID).Scan(&clash)
	if clash > 0 {
		inv.Add("slug", "has already been taken")
	}
	if err := inv.Err(); err != nil {
		return err
	}
	now := Now()
	if creating {
		res, err := a.Store.DB.ExecContext(ctx, `INSERT INTO collections (slug, name, icon, api_enabled, enable_blocks, schema, build_config, categories_collection_id, tags_collection_id, created_at, updated_at)
			VALUES (?,?,?,?,?,?,?,?,?,?,?)`, c.Slug, c.Name, c.Icon, c.APIEnabled, c.EnableBlocks, string(c.Schema), string(c.BuildConfig),
			c.CategoriesCollectionID.DB(), c.TagsCollectionID.DB(), now.DB(), now.DB())
		if err != nil {
			return err
		}
		c.ID, _ = res.LastInsertId()
		c.CreatedAt = now
	} else {
		if _, err := a.Store.DB.ExecContext(ctx, `UPDATE collections SET slug=?, name=?, icon=?, api_enabled=?, enable_blocks=?, schema=?, build_config=?,
			categories_collection_id=?, tags_collection_id=?, updated_at=? WHERE id=?`, c.Slug, c.Name, c.Icon, c.APIEnabled, c.EnableBlocks,
			string(c.Schema), string(c.BuildConfig), c.CategoriesCollectionID.DB(), c.TagsCollectionID.DB(), now.DB(), c.ID); err != nil {
			return err
		}
	}
	c.UpdatedAt = now
	a.audit(ctx, actor, map[bool]string{true: "collection.created", false: "collection.updated"}[creating], "Collection", c.ID, c.Name, nil)
	a.Deploys.Changed("collection:" + c.Slug)
	return nil
}

// normalizeSchema accepts [fields] or {"fields": [fields]} and stores the
// latter.
func normalizeSchema(v any) JSON {
	switch x := v.(type) {
	case []any:
		return mustJSON(map[string]any{"fields": x})
	case map[string]any:
		if x["fields"] == nil {
			x["fields"] = []any{}
		}
		return mustJSON(x)
	}
	return JSON(`{"fields":[]}`)
}

func (a *App) DeleteCollection(ctx context.Context, actor *Actor, c *Collection) error {
	var live int
	a.Store.DB.QueryRowContext(ctx, `SELECT count(*) FROM collection_entries WHERE collection_id = ?`, c.ID).Scan(&live)
	if live > 0 {
		return errConflict("It still has entries (trashed ones count): delete or purge those first.")
	}
	if _, err := a.Store.DB.ExecContext(ctx, `DELETE FROM collections WHERE id = ?`, c.ID); err != nil {
		return err
	}
	a.audit(ctx, actor, "collection.deleted", "Collection", c.ID, c.Name, nil)
	return nil
}

// ---- globals -------------------------------------------------------------

type Global struct {
	ID                              int64
	Slug, Name, Description, Icon   string
	Data, Schema                    JSON
	Version, LockVersion            int
	DeletedAt, CreatedAt, UpdatedAt Time
}

const globalCols = `id, slug, name, COALESCE(description, ''), COALESCE(icon, ''), data, schema, version, lock_version, deleted_at, created_at, updated_at`

func (a *App) Globals(ctx context.Context, where string, args ...any) ([]*Global, error) {
	if where == "" {
		where = "1=1"
	}
	if !strings.Contains(where, "deleted_at") {
		where = scoped("deleted_at IS NULL", where)
	}
	rows, err := a.Store.DB.QueryContext(ctx, "SELECT "+globalCols+" FROM globals WHERE "+where, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []*Global{}
	for rows.Next() {
		g := &Global{}
		if err := rows.Scan(&g.ID, &g.Slug, &g.Name, &g.Description, &g.Icon, &g.Data, &g.Schema, &g.Version, &g.LockVersion, &g.DeletedAt, &g.CreatedAt, &g.UpdatedAt); err != nil {
			return nil, err
		}
		g.Data = g.Data.Or("{}")
		g.Schema = g.Schema.Or(`{"fields":[]}`)
		out = append(out, g)
	}
	return out, rows.Err()
}

func (a *App) GlobalBySlug(ctx context.Context, slug string) (*Global, error) {
	list, err := a.Globals(ctx, "slug = ?", slug)
	if err != nil {
		return nil, err
	}
	if len(list) == 0 {
		return nil, errNotFound("Couldn't find global " + slug + ".")
	}
	return list[0], nil
}

func (a *App) globalByID(ctx context.Context, id int64) (*Global, error) {
	list, err := a.Globals(ctx, "id = ?", id)
	if err != nil {
		return nil, err
	}
	if len(list) == 0 {
		return nil, ErrNotFound
	}
	return list[0], nil
}

func (g *Global) Fields() []Field { return ParseFields(g.Schema) }

func (g *Global) FieldsJSON() any {
	if f := g.Schema.Map()["fields"]; f != nil {
		return f
	}
	return []any{}
}

func (a *App) GlobalJSON(g *Global) Obj {
	return O("id", g.ID, "slug", g.Slug, "name", g.Name, "description", g.Description, "icon", g.Icon, "version", g.Version,
		"data", Redact(g.Data.Map()), "created_at", g.CreatedAt, "updated_at", g.UpdatedAt, "fields", g.FieldsJSON(),
		"json_schema", JSONSchema(g.Fields()))
}

var globalKeys = []string{"slug", "name", "description", "icon", "version", "data", "schema"}

// SaveGlobal creates or updates a global. Globals have no draft state, so
// changing one that exists needs globals:publish; without it the write is
// held as a revision.
func (a *App) SaveGlobal(ctx context.Context, actor *Actor, g *Global, p map[string]any) (*WriteResult, error) {
	creating := g.ID == 0
	if !creating && !actor.Can("globals:publish") {
		rev, ignored, err := a.fileRevision(ctx, actor, "Global", g.ID, g.Name, p, []string{"name", "description", "icon", "data"})
		if err != nil {
			return nil, err
		}
		return &WriteResult{Held: rev, Ignored: ignored}, nil
	}
	if (g.Slug == "scripts" || str(p["slug"]) == "scripts") && !actor.Can("globals:scripts") {
		return nil, errForbidden("globals:scripts")
	}
	if creating {
		g.Data, g.Schema, g.Version = JSON("{}"), JSON(`{"fields":[]}`), 1
	}
	prior := *g
	if has(p, "slug") {
		g.Slug = strings.TrimSpace(str(p["slug"]))
	}
	if has(p, "name") {
		g.Name = strings.TrimSpace(str(p["name"]))
	}
	if has(p, "description") {
		g.Description = str(p["description"])
	}
	if has(p, "icon") {
		g.Icon = str(p["icon"])
	}
	if v, ok := intOf(p["version"]); ok {
		g.Version = int(v)
	}
	inv := Invalid{}
	if has(p, "schema") {
		g.Schema = normalizeSchema(p["schema"])
		ValidateDefinitions(g.Schema.Map()["fields"], true, inv, "schema.fields")
	}
	if has(p, "data") {
		data, ok := p["data"].(map[string]any)
		if !ok {
			inv.Add("data", "must be an object")
		} else {
			// A masked secret written back means "keep what's there".
			old := prior.Data.Map()
			for k, v := range data {
				if s, ok := v.(string); ok && strings.HasPrefix(s, "***") && secretKey(k) {
					data[k] = old[k]
				}
			}
			g.Data = mustJSON(data)
		}
	}
	if g.Slug == "" || !collectionSlugFormat.MatchString(g.Slug) {
		inv.Add("slug", "is invalid: lowercase letters, numbers, - and _")
	}
	if g.Name == "" {
		inv.Add("name", "can't be blank")
	}
	var clash int
	a.Store.DB.QueryRowContext(ctx, `SELECT count(*) FROM globals WHERE slug = ? AND id != ? AND deleted_at IS NULL`, g.Slug, g.ID).Scan(&clash)
	if clash > 0 {
		inv.Add("slug", "has already been taken")
	}
	ValidateData(g.Fields(), g.Data.Map(), a.blockTypeResolver(ctx), inv, "data")
	if err := inv.Err(); err != nil {
		return nil, err
	}
	if !creating {
		if lv, ok := intOf(p["lock_version"]); ok && int(lv) != prior.LockVersion {
			return nil, errConflict("Someone else saved this since you read it. Read it again and redo the change.")
		}
		if jsonEqual(prior.Data, g.Data) && jsonEqual(prior.Schema, g.Schema) && prior.Name == g.Name && prior.Slug == g.Slug &&
			prior.Description == g.Description && prior.Icon == g.Icon && prior.Version == g.Version {
			return &WriteResult{Unchanged: true}, nil
		}
	}
	now := Now()
	var refs []Ref
	FieldRefs(g.Fields(), g.Data.Map(), a.blockTypeResolver(ctx), &refs)
	err := a.Store.Tx(ctx, func(tx *sql.Tx) error {
		if creating {
			res, err := tx.ExecContext(ctx, `INSERT INTO globals (slug, name, description, icon, data, schema, version, created_at, updated_at) VALUES (?,?,?,?,?,?,?,?,?)`,
				g.Slug, g.Name, g.Description, g.Icon, string(g.Data), string(g.Schema), g.Version, now.DB(), now.DB())
			if err != nil {
				return err
			}
			g.ID, _ = res.LastInsertId()
			g.CreatedAt = now
		} else {
			g.LockVersion++
			if _, err := tx.ExecContext(ctx, `UPDATE globals SET slug=?, name=?, description=?, icon=?, data=?, schema=?, version=?, lock_version=?, updated_at=? WHERE id=?`,
				g.Slug, g.Name, g.Description, g.Icon, string(g.Data), string(g.Schema), g.Version, g.LockVersion, now.DB(), g.ID); err != nil {
				return err
			}
		}
		var author any
		if actor.UserID != 0 {
			author = actor.UserID
		}
		if _, err := tx.ExecContext(ctx, `INSERT INTO global_versions (global_id, author_id, data, name, created_at) VALUES (?,?,?,?,?)`, g.ID, author, string(g.Data), g.Name, now.DB()); err != nil {
			return err
		}
		return replaceReferences(ctx, tx, "Global", g.ID, appendRefs(nil, refs, -1))
	})
	if err != nil {
		return nil, err
	}
	g.UpdatedAt = now
	a.audit(ctx, actor, map[bool]string{true: "global.created", false: "global.updated"}[creating], "Global", g.ID, g.Name, nil)
	payload := O("id", g.ID, "slug", g.Slug, "name", g.Name, "updated_at", g.UpdatedAt.ISO())
	a.Hooks.Deliver("global.updated", payload)
	a.Deploys.Changed("global:" + g.Slug)
	a.Plugins.Emit("global.updated", payload)
	return &WriteResult{Created: creating}, nil
}

// ---- block types ---------------------------------------------------------

type BlockType struct {
	ID                                       int64
	Slug, Label, Description, Category, Icon string
	Fields, Defaults                         JSON
	BuiltIn, Deprecated                      bool
	Version                                  int
	CreatedAt, UpdatedAt                     Time
}

const blockTypeCols = `id, slug, label, COALESCE(description, ''), COALESCE(category, ''), COALESCE(icon, ''), fields, defaults, built_in, deprecated, version, created_at, updated_at`

func (a *App) BlockTypesList(ctx context.Context, where string, args ...any) ([]*BlockType, error) {
	if where == "" {
		where = "1=1"
	}
	rows, err := a.Store.DB.QueryContext(ctx, "SELECT "+blockTypeCols+" FROM block_types WHERE "+where, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []*BlockType{}
	for rows.Next() {
		b := &BlockType{}
		if err := rows.Scan(&b.ID, &b.Slug, &b.Label, &b.Description, &b.Category, &b.Icon, &b.Fields, &b.Defaults, &b.BuiltIn, &b.Deprecated, &b.Version, &b.CreatedAt, &b.UpdatedAt); err != nil {
			return nil, err
		}
		b.Fields = b.Fields.Or("[]")
		b.Defaults = b.Defaults.Or("{}")
		out = append(out, b)
	}
	return out, rows.Err()
}

func (b *BlockType) JSON() Obj {
	return O("id", b.ID, "slug", b.Slug, "label", b.Label, "description", b.Description, "category", b.Category, "icon", b.Icon,
		"version", b.Version, "built_in", b.BuiltIn, "deprecated", b.Deprecated, "fields", b.Fields, "defaults", b.Defaults,
		"created_at", b.CreatedAt, "updated_at", b.UpdatedAt, "json_schema", b.Schema())
}

func (b *BlockType) Schema() map[string]any {
	s := JSONSchema(ParseFields(b.Fields))
	s["title"] = b.Label
	return s
}

func (a *App) SaveBlockType(ctx context.Context, actor *Actor, b *BlockType, p map[string]any) error {
	creating := b.ID == 0
	if creating {
		b.Fields, b.Defaults, b.Version = JSON("[]"), JSON("{}"), 1
	}
	for k, dst := range map[string]*string{"slug": &b.Slug, "label": &b.Label, "description": &b.Description, "category": &b.Category, "icon": &b.Icon} {
		if has(p, k) {
			*dst = strings.TrimSpace(str(p[k]))
		}
	}
	if has(p, "deprecated") {
		b.Deprecated = boolOf(p["deprecated"])
	}
	if v, ok := intOf(p["version"]); ok {
		b.Version = int(v)
	}
	inv := Invalid{}
	if has(p, "fields") {
		ValidateDefinitions(p["fields"], true, inv, "fields")
		b.Fields = mustJSON(p["fields"]).Or("[]")
	}
	if has(p, "defaults") {
		if _, ok := p["defaults"].(map[string]any); !ok {
			inv.Add("defaults", "must be an object")
		} else {
			b.Defaults = mustJSON(p["defaults"])
		}
	}
	if !blockSlugFormat.MatchString(b.Slug) {
		inv.Add("slug", "is invalid: a lowercase letter, then a-z, 0-9 and _")
	}
	if b.Label == "" {
		inv.Add("label", "can't be blank")
	}
	var clash int
	a.Store.DB.QueryRowContext(ctx, `SELECT count(*) FROM block_types WHERE slug = ? AND id != ?`, b.Slug, b.ID).Scan(&clash)
	if clash > 0 {
		inv.Add("slug", "has already been taken")
	}
	if err := inv.Err(); err != nil {
		return err
	}
	now := Now()
	if creating {
		res, err := a.Store.DB.ExecContext(ctx, `INSERT INTO block_types (slug, label, description, category, icon, fields, defaults, built_in, deprecated, version, created_at, updated_at)
			VALUES (?,?,?,?,?,?,?,?,?,?,?,?)`, b.Slug, b.Label, b.Description, b.Category, b.Icon, string(b.Fields), string(b.Defaults), b.BuiltIn, b.Deprecated, b.Version, now.DB(), now.DB())
		if err != nil {
			return err
		}
		b.ID, _ = res.LastInsertId()
		b.CreatedAt = now
	} else if _, err := a.Store.DB.ExecContext(ctx, `UPDATE block_types SET slug=?, label=?, description=?, category=?, icon=?, fields=?, defaults=?, deprecated=?, version=?, updated_at=? WHERE id=?`,
		b.Slug, b.Label, b.Description, b.Category, b.Icon, string(b.Fields), string(b.Defaults), b.Deprecated, b.Version, now.DB(), b.ID); err != nil {
		return err
	}
	b.UpdatedAt = now
	a.audit(ctx, actor, map[bool]string{true: "block_type.created", false: "block_type.updated"}[creating], "BlockType", b.ID, b.Label, nil)
	return nil
}

// ---- settings ------------------------------------------------------------

// Setting reads one settings key's data ({} when it isn't set).
func (a *App) Setting(ctx context.Context, key string) map[string]any {
	var data JSON
	err := a.Store.DB.QueryRowContext(ctx, `SELECT data FROM settings WHERE key = ?`, key).Scan(&data)
	if err != nil {
		return map[string]any{}
	}
	return data.Map()
}

func (a *App) general() map[string]any { return a.Setting(context.Background(), "general") }

func (a *App) defaultLocale() string {
	if l := str(a.general()["default_locale"]); l != "" {
		return l
	}
	return "en"
}

// PutSetting merges data into a key (null removes a key), keeping what a
// masked secret written back would otherwise overwrite.
func (a *App) PutSetting(ctx context.Context, actor *Actor, key string, data map[string]any, replace bool) (map[string]any, error) {
	old := a.Setting(ctx, key)
	merged := map[string]any{}
	if !replace {
		for k, v := range old {
			merged[k] = v
		}
	}
	keepMasked(merged, old, data)
	now := Now().DB()
	_, err := a.Store.DB.ExecContext(ctx, `INSERT INTO settings (key, data, created_at, updated_at) VALUES (?,?,?,?)
		ON CONFLICT(key) DO UPDATE SET data = excluded.data, updated_at = excluded.updated_at`, key, string(mustJSON(merged)), now, now)
	if err != nil {
		return nil, err
	}
	a.audit(ctx, actor, "setting.updated", "Setting", 0, key, map[string]any{"keys": keysOf(data)})
	if key == "general" {
		a.Deploys.Changed("site")
	}
	return merged, nil
}

func keepMasked(into, old, data map[string]any) {
	for k, v := range data {
		switch x := v.(type) {
		case nil:
			delete(into, k)
		case string:
			if strings.HasPrefix(x, "***") && secretKey(k) {
				if ov, ok := old[k]; ok {
					into[k] = ov
				}
				continue
			}
			into[k] = x
		case map[string]any:
			sub, _ := old[k].(map[string]any)
			if sub == nil {
				sub = map[string]any{}
			}
			next := map[string]any{}
			for sk, sv := range sub {
				next[sk] = sv
			}
			keepMasked(next, sub, x)
			into[k] = next
		default:
			into[k] = v
		}
	}
}

func keysOf(m map[string]any) []string {
	out := make([]string, 0, len(m))
	for k := range m {
		out = append(out, k)
	}
	return out
}

var secretPattern = regexp.MustCompile(`(?i)(token|secret|password|api_key|apikey|private_key|access_key|credential)`)

func secretKey(k string) bool { return secretPattern.MatchString(k) }

// Redact masks secret-looking values: "***" and the last four characters.
func Redact(v any) any {
	switch x := v.(type) {
	case map[string]any:
		out := map[string]any{}
		for k, val := range x {
			if s, ok := val.(string); ok && secretKey(k) && s != "" {
				tail := s
				if len(s) > 4 {
					tail = s[len(s)-4:]
				}
				out[k] = "***" + tail
			} else {
				out[k] = Redact(val)
			}
		}
		return out
	case []any:
		out := make([]any, len(x))
		for i, val := range x {
			out[i] = Redact(val)
		}
		return out
	}
	return v
}

// ---- audit log -----------------------------------------------------------

func (a *App) audit(ctx context.Context, actor *Actor, action, targetType string, targetID int64, targetLabel string, meta map[string]any) {
	if meta == nil {
		meta = map[string]any{}
	}
	var actorID, actorType any
	label := "system"
	if actor != nil {
		actorID, actorType, label = actor.ID(), actor.Type(), actor.Label()
	}
	var tid any
	if targetID != 0 {
		tid = targetID
	}
	_, err := a.Store.DB.ExecContext(context.WithoutCancel(ctx), `INSERT INTO audit_logs (action, actor_id, actor_type, actor_label, target_id, target_type, target_label, metadata, created_at)
		VALUES (?,?,?,?,?,?,?,?,?)`, action, actorID, actorType, label, tid, targetType, targetLabel, string(mustJSON(meta)), Now().DB())
	if err != nil {
		a.Logger.Warn("audit", "err", err)
	}
}

// ---- seeding -------------------------------------------------------------

// seed makes what an empty install needs: the built-in roles, and the
// general settings saying the site is served over the API.
func (a *App) seed() error {
	ctx := context.Background()
	// Roles only on an empty install: a Rails database brings its own.
	var roles int
	a.Store.DB.QueryRowContext(ctx, `SELECT count(*) FROM roles`).Scan(&roles)
	for _, r := range defaultRoles {
		if roles > 0 {
			break
		}
		perms, _ := json.Marshal(r.Caps)
		if _, err := a.Store.DB.ExecContext(ctx, `INSERT INTO roles (name, description, permissions, system, created_at, updated_at) VALUES (?,?,?,?,?,?)`,
			r.Name, r.Description, string(perms), r.System, Now().DB(), Now().DB()); err != nil {
			return err
		}
	}
	var n int
	a.Store.DB.QueryRowContext(ctx, `SELECT count(*) FROM settings WHERE key = 'general'`).Scan(&n)
	if n == 0 {
		_, err := a.Store.DB.ExecContext(ctx, `INSERT INTO settings (key, data, created_at, updated_at) VALUES ('general', ?, ?, ?)`,
			`{"title":"My site","default_locale":"en","serving":"api_only"}`, Now().DB(), Now().DB())
		return err
	}
	return nil
}
