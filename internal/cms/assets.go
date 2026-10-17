package cms

import (
	"bytes"
	"context"
	"crypto/md5"
	"database/sql"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"image"
	"image/gif"
	"image/jpeg"
	"image/png"
	"io"
	"mime"
	"net/http"
	"net/url"
	"os"
	"path"
	"path/filepath"
	"strconv"
	"strings"
	"sync"

	"golang.org/x/image/draw"
	_ "golang.org/x/image/webp"
)

// Media files keep Active Storage's disk layout (storage/ab/cd/abcd…), so a
// Rails install's storage/ directory is served as it is.

var DeliveryWidths = []int{640, 1280, 1920}

const maxUpload = 100 << 20

type Asset struct {
	ID                       int64
	Name, Alt, Caption, Desc string
	Folder                   string
	FocalX, FocalY           float64
	DeletedAt, CreatedAt     Time
	UpdatedAt                Time
	BlobKey, Filename, Type  string
	ByteSize                 int64
	Width, Height            *int
}

const assetCols = `a.id, COALESCE(a.name, ''), COALESCE(a.alt, ''), COALESCE(a.caption, ''), COALESCE(a.description, ''), a.folder, a.focal_x, a.focal_y,
	a.deleted_at, a.created_at, a.updated_at, COALESCE(b.key, ''), COALESCE(b.filename, ''), COALESCE(b.content_type, ''), COALESCE(b.byte_size, 0), COALESCE(b.metadata, '')`

const assetFrom = ` FROM assets a
	LEFT JOIN active_storage_attachments att ON att.record_type = 'Asset' AND att.record_id = a.id AND att.name = 'file'
	LEFT JOIN active_storage_blobs b ON b.id = att.blob_id `

func (a *App) Assets(ctx context.Context, where string, args ...any) ([]*Asset, error) {
	if where == "" {
		where = "1=1"
	}
	if !strings.Contains(where, "deleted_at") {
		where = scoped("a.deleted_at IS NULL", where)
	}
	rows, err := a.Store.DB.QueryContext(ctx, "SELECT "+assetCols+assetFrom+"WHERE "+where, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []*Asset{}
	for rows.Next() {
		as := &Asset{}
		var meta string
		if err := rows.Scan(&as.ID, &as.Name, &as.Alt, &as.Caption, &as.Desc, &as.Folder, &as.FocalX, &as.FocalY, &as.DeletedAt, &as.CreatedAt, &as.UpdatedAt,
			&as.BlobKey, &as.Filename, &as.Type, &as.ByteSize, &meta); err != nil {
			return nil, err
		}
		var m map[string]any
		if json.Unmarshal([]byte(meta), &m) == nil {
			if w, ok := intOf(m["width"]); ok {
				wi := int(w)
				as.Width = &wi
			}
			if h, ok := intOf(m["height"]); ok {
				hi := int(h)
				as.Height = &hi
			}
		}
		out = append(out, as)
	}
	return out, rows.Err()
}

func (a *App) AssetByID(ctx context.Context, id int64, withTrashed bool) (*Asset, error) {
	where := "a.id = ?"
	if withTrashed {
		where += " AND (a.deleted_at IS NULL OR a.deleted_at IS NOT NULL)"
	}
	list, err := a.Assets(ctx, where, id)
	if err != nil {
		return nil, err
	}
	if len(list) == 0 {
		return nil, errNotFound("Couldn't find asset " + strconv.FormatInt(id, 10) + ".")
	}
	return list[0], nil
}

func (as *Asset) Image() bool { return strings.HasPrefix(as.Type, "image/") }

// variantable: images this core can resize (not SVG, not animated GIF
// guesses — GIFs resize to their first frame).
func (as *Asset) variantable() bool {
	switch as.Type {
	case "image/jpeg", "image/png", "image/gif", "image/webp":
		return true
	}
	return false
}

func (a *App) fileURL(as *Asset, variant string) string {
	if as.BlobKey == "" {
		return ""
	}
	p := "/files/" + as.BlobKey
	if variant != "" {
		p += "/" + variant
	}
	return a.BaseURL + p + "/" + urlPathEscape(as.Filename)
}

func urlPathEscape(s string) string { return url.PathEscape(s) }

// Delivery is an asset as a site renders it: absolute URLs on the CMS's own
// host, its size, and width-limited renditions.
func (a *App) Delivery(as *Asset) Obj {
	url := a.fileURL(as, "")
	o := O("id", as.ID, "url", url, "original", url, "filename", as.Filename, "content_type", as.Type, "byte_size", as.ByteSize,
		"width", as.Width, "height", as.Height, "alt", as.Alt, "folder", as.Folder)
	if as.Image() {
		variants := map[string]string{}
		srcset := []Obj{}
		thumb := url
		if as.variantable() {
			for _, w := range DeliveryWidths {
				variants["w"+strconv.Itoa(w)] = a.fileURL(as, "w"+strconv.Itoa(w))
				srcset = append(srcset, O("width", w, "descriptor", strconv.Itoa(w)+"w", "url", a.fileURL(as, "w"+strconv.Itoa(w))))
			}
			thumb = a.fileURL(as, "w256")
		}
		o = append(o, kv{"variants", variants}, kv{"thumb_url", thumb}, kv{"srcset", srcset}, kv{"focal_x", as.FocalX}, kv{"focal_y", as.FocalY})
	}
	return o
}

func (a *App) AssetJSON(ctx context.Context, as *Asset) Obj {
	var uses int
	a.Store.DB.QueryRowContext(ctx, `SELECT count(DISTINCT owner_type || ':' || owner_id) FROM content_references WHERE ref_type = 'asset' AND ref_id = ?`, strconv.FormatInt(as.ID, 10)).Scan(&uses)
	return append(a.Delivery(as), kv{"name", as.Name}, kv{"caption", as.Caption}, kv{"description", as.Desc}, kv{"created_at", as.CreatedAt.ISO()}, kv{"usage_count", uses})
}

// resolveAssets is {id: delivery} for the ids that exist.
func (a *App) resolveAssets(ctx context.Context, ids []int64) map[string]Obj {
	out := map[string]Obj{}
	if len(ids) == 0 {
		return out
	}
	args := make([]any, len(ids))
	for i, id := range ids {
		args[i] = id
	}
	list, err := a.Assets(ctx, "a.id IN ("+placeholders(len(ids))+")", args...)
	if err != nil {
		return out
	}
	for _, as := range list {
		out[strconv.FormatInt(as.ID, 10)] = a.Delivery(as)
	}
	return out
}

func (a *App) blobPath(key string) string {
	if len(key) < 4 {
		return filepath.Join(a.DataDir, "storage", key)
	}
	return filepath.Join(a.DataDir, "storage", key[0:2], key[2:4], key)
}

// CreateAsset stores an upload and makes its asset.
func (a *App) CreateAsset(ctx context.Context, actor *Actor, filename, contentType string, r io.Reader, fields map[string]string) (*Asset, error) {
	data, err := io.ReadAll(io.LimitReader(r, maxUpload+1))
	if err != nil {
		return nil, err
	}
	if len(data) > maxUpload {
		return nil, &Error{Status: 422, Code: "invalid", Message: "Validation failed", Errors: Invalid{"file": {"is larger than 100 MB"}}}
	}
	if len(data) == 0 {
		return nil, &Error{Status: 422, Code: "invalid", Message: "Validation failed", Errors: Invalid{"file": {"is empty"}}}
	}
	filename = path.Base(strings.ReplaceAll(filename, "\\", "/"))
	if contentType == "" || contentType == "application/octet-stream" {
		if t := mime.TypeByExtension(strings.ToLower(filepath.Ext(filename))); t != "" {
			contentType = strings.Split(t, ";")[0]
		} else {
			contentType = http.DetectContentType(data)
		}
	}
	if contentType == "text/html" || strings.HasSuffix(strings.ToLower(filename), ".html") {
		return nil, &Error{Status: 422, Code: "invalid", Message: "Validation failed", Errors: Invalid{"file": {"HTML files can't be uploaded"}}}
	}
	meta := map[string]any{"identified": true, "analyzed": true}
	if cfg, _, err := image.DecodeConfig(bytes.NewReader(data)); err == nil {
		meta["width"], meta["height"] = cfg.Width, cfg.Height
	}
	key := strings.ToLower(strings.TrimRight(base32Key(), "="))
	sum := md5.Sum(data)
	p := a.blobPath(key)
	if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
		return nil, err
	}
	if err := os.WriteFile(p, data, 0o644); err != nil {
		return nil, err
	}
	folder := normalizeFolder(fields["folder"])
	now := Now().DB()
	var id int64
	err = a.Store.Tx(ctx, func(tx *sql.Tx) error {
		res, err := tx.ExecContext(ctx, `INSERT INTO active_storage_blobs (key, filename, content_type, metadata, service_name, byte_size, checksum, created_at) VALUES (?,?,?,?,?,?,?,?)`,
			key, filename, contentType, string(mustJSON(meta)), "local", len(data), base64.StdEncoding.EncodeToString(sum[:]), now)
		if err != nil {
			return err
		}
		blobID, _ := res.LastInsertId()
		name := fields["name"]
		if name == "" {
			name = strings.TrimSuffix(filename, filepath.Ext(filename))
		}
		res, err = tx.ExecContext(ctx, `INSERT INTO assets (name, alt, caption, description, folder, created_at, updated_at) VALUES (?,?,?,?,?,?,?)`,
			name, fields["alt"], fields["caption"], fields["description"], folder, now, now)
		if err != nil {
			return err
		}
		id, _ = res.LastInsertId()
		_, err = tx.ExecContext(ctx, `INSERT INTO active_storage_attachments (name, record_type, record_id, blob_id, created_at) VALUES ('file', 'Asset', ?, ?, ?)`, id, blobID, now)
		return err
	})
	if err != nil {
		os.Remove(p)
		return nil, err
	}
	as, err := a.AssetByID(ctx, id, false)
	if err == nil {
		a.audit(ctx, actor, "asset.created", "Asset", id, filename, nil)
	}
	return as, err
}

func base32Key() string {
	const alphabet = "abcdefghijklmnopqrstuvwxyz0123456789"
	b := randomBytes(28)
	out := make([]byte, 28)
	for i, c := range b {
		out[i] = alphabet[int(c)%len(alphabet)]
	}
	return string(out)
}

func normalizeFolder(f string) string {
	f = "/" + strings.Trim(strings.TrimSpace(f), "/")
	return path.Clean(f)
}

func (a *App) UpdateAsset(ctx context.Context, actor *Actor, as *Asset, p map[string]any) error {
	for k, dst := range map[string]*string{"name": &as.Name, "alt": &as.Alt, "caption": &as.Caption, "description": &as.Desc} {
		if has(p, k) {
			*dst = str(p[k])
		}
	}
	if has(p, "folder") {
		as.Folder = normalizeFolder(str(p["folder"]))
	}
	for k, dst := range map[string]*float64{"focal_x": &as.FocalX, "focal_y": &as.FocalY} {
		if v, ok := p[k].(float64); ok {
			if v < 0 || v > 1 {
				return &Error{Status: 422, Code: "invalid", Message: "Validation failed", Errors: Invalid{k: {"must be between 0 and 1"}}}
			}
			*dst = v
		}
	}
	_, err := a.Store.DB.ExecContext(ctx, `UPDATE assets SET name=?, alt=?, caption=?, description=?, folder=?, focal_x=?, focal_y=?, updated_at=? WHERE id=?`,
		as.Name, as.Alt, as.Caption, as.Desc, as.Folder, as.FocalX, as.FocalY, Now().DB(), as.ID)
	if err == nil {
		a.audit(ctx, actor, "asset.updated", "Asset", as.ID, as.Filename, nil)
	}
	return err
}

func (a *App) PurgeAsset(ctx context.Context, actor *Actor, as *Asset) error {
	err := a.Store.Tx(ctx, func(tx *sql.Tx) error {
		var blobID int64
		tx.QueryRowContext(ctx, `SELECT blob_id FROM active_storage_attachments WHERE record_type = 'Asset' AND record_id = ?`, as.ID).Scan(&blobID)
		for _, s := range []string{
			`DELETE FROM active_storage_attachments WHERE record_type = 'Asset' AND record_id = ?`,
			`DELETE FROM assets WHERE id = ?`,
		} {
			if _, err := tx.ExecContext(ctx, s, as.ID); err != nil {
				return err
			}
		}
		_, err := tx.ExecContext(ctx, `DELETE FROM active_storage_blobs WHERE id = ?`, blobID)
		return err
	})
	if err != nil {
		return err
	}
	if as.BlobKey != "" {
		os.Remove(a.blobPath(as.BlobKey))
		matches, _ := filepath.Glob(filepath.Join(a.DataDir, "variants", as.BlobKey+"-*"))
		for _, m := range matches {
			os.Remove(m)
		}
	}
	a.audit(ctx, actor, "asset.purged", "Asset", as.ID, as.Filename, nil)
	return nil
}

// ---- serving -------------------------------------------------------------

var variantLocks sync.Map

// serveFile answers /files/<key>/<filename> and /files/<key>/w640/<filename>.
// Keys are unguessable; a file is public once uploaded, as Active Storage's
// were.
func (a *App) serveFile(w http.ResponseWriter, r *http.Request) {
	parts := strings.Split(strings.TrimPrefix(r.URL.Path, "/files/"), "/")
	if len(parts) < 2 {
		http.NotFound(w, r)
		return
	}
	key := parts[0]
	variant := ""
	if len(parts) >= 3 {
		variant = parts[1]
	}
	var as Asset
	err := a.Store.DB.QueryRowContext(r.Context(), `SELECT key, filename, COALESCE(content_type, '') FROM active_storage_blobs WHERE key = ?`, key).Scan(&as.BlobKey, &as.Filename, &as.Type)
	if err != nil {
		http.NotFound(w, r)
		return
	}
	file := a.blobPath(key)
	if variant != "" && as.variantable() {
		width, err := strconv.Atoi(strings.TrimPrefix(variant, "w"))
		if err != nil || !strings.HasPrefix(variant, "w") || (width != 256 && !containsInt(DeliveryWidths, width)) {
			http.NotFound(w, r)
			return
		}
		file, err = a.variant(as, width)
		if err != nil {
			a.Logger.Warn("variant", "key", key, "err", err)
			file = a.blobPath(key)
		}
	}
	f, err := os.Open(file)
	if err != nil {
		http.NotFound(w, r)
		return
	}
	defer f.Close()
	st, _ := f.Stat()
	ct := as.Type
	if strings.HasSuffix(file, ".jpg") {
		ct = "image/jpeg"
	} else if strings.HasSuffix(file, ".png") {
		ct = "image/png"
	}
	h := w.Header()
	h.Set("Content-Type", ct)
	h.Set("Cache-Control", "public, max-age=31536000, immutable")
	h.Set("Content-Security-Policy", "default-src 'none'; style-src 'unsafe-inline'; sandbox")
	if !strings.HasPrefix(ct, "image/") && !strings.HasPrefix(ct, "video/") && !strings.HasPrefix(ct, "audio/") && ct != "application/pdf" {
		h.Set("Content-Disposition", fmt.Sprintf("attachment; filename=%q", as.Filename))
	}
	http.ServeContent(w, r, "", st.ModTime(), f)
}

func containsInt(l []int, v int) bool {
	for _, x := range l {
		if x == v {
			return true
		}
	}
	return false
}

// variant makes (once) and returns the path of a width-limited copy.
func (a *App) variant(as Asset, width int) (string, error) {
	ext := ".jpg"
	if as.Type == "image/png" || as.Type == "image/gif" {
		ext = ".png"
	}
	out := filepath.Join(a.DataDir, "variants", fmt.Sprintf("%s-w%d%s", as.BlobKey, width, ext))
	if _, err := os.Stat(out); err == nil {
		return out, nil
	}
	lock, _ := variantLocks.LoadOrStore(out, &sync.Mutex{})
	lock.(*sync.Mutex).Lock()
	defer lock.(*sync.Mutex).Unlock()
	if _, err := os.Stat(out); err == nil {
		return out, nil
	}
	src, err := os.Open(a.blobPath(as.BlobKey))
	if err != nil {
		return "", err
	}
	defer src.Close()
	img, _, err := image.Decode(src)
	if err != nil {
		return "", err
	}
	b := img.Bounds()
	if b.Dx() <= width {
		return a.blobPath(as.BlobKey), nil
	}
	height := b.Dy() * width / b.Dx()
	dst := image.NewRGBA(image.Rect(0, 0, width, height))
	draw.CatmullRom.Scale(dst, dst.Bounds(), img, b, draw.Over, nil)
	if err := os.MkdirAll(filepath.Dir(out), 0o755); err != nil {
		return "", err
	}
	tmp := out + ".tmp"
	f, err := os.Create(tmp)
	if err != nil {
		return "", err
	}
	if ext == ".png" {
		err = png.Encode(f, dst)
	} else {
		err = jpeg.Encode(f, dst, &jpeg.Options{Quality: 82})
	}
	f.Close()
	if err != nil {
		os.Remove(tmp)
		return "", err
	}
	return out, os.Rename(tmp, out)
}

var _ = gif.Decode // registers GIF decoding
