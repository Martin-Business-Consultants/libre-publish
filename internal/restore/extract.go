package restore

import (
	"archive/tar"
	"bufio"
	"bytes"
	"compress/gzip"
	"context"
	"crypto/md5" //nolint:gosec // Active Storage's checksum, which blobs are checked against
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path"
	"path/filepath"
	"regexp"
	"strings"
)

// Limits bound what an archive may unpack to, so a hostile or broken one
// (a gzip bomb, a million tiny entries) fails rather than filling the disk.
type Limits struct {
	// MaxTotal is the most the archive may decompress to, every entry
	// counted, whether it's kept or not.
	MaxTotal int64
	// MaxFile is the most one file may be.
	MaxFile int64
	// MaxEntries is the most entries the archive may hold.
	MaxEntries int
}

// DefaultLimits are generous: a site's database and media, not a disk's.
var DefaultLimits = Limits{MaxTotal: 64 << 30, MaxFile: 32 << 30, MaxEntries: 2_000_000}

func (l Limits) or() Limits {
	if l.MaxTotal <= 0 {
		l.MaxTotal = DefaultLimits.MaxTotal
	}
	if l.MaxFile <= 0 {
		l.MaxFile = DefaultLimits.MaxFile
	}
	if l.MaxEntries <= 0 {
		l.MaxEntries = DefaultLimits.MaxEntries
	}
	return l
}

// What an entry of a backup is. Only these are written, each to a path
// built here rather than taken from the archive, so nothing in it lands
// anywhere else.
type entryKind int

const (
	kindIgnored  entryKind = iota
	kindDB                 // the database
	kindWAL                // its write-ahead log (a copied directory's)
	kindBlob               // an uploaded file
	kindManifest           // manifest.json
	kindKey                // secret.key (a Go backup that was asked to include it)
)

// The databases, by the name each format gives it.
var databases = map[string]string{
	"cms.sqlite3":        FormatGo,
	"db/main.sqlite3":    FormatRailsSite,
	"production.sqlite3": FormatRailsData,
}

// blobKey is an Active Storage key as both cores make them: lowercase
// base36 (Rails) or base32 (Go).
var blobKey = regexp.MustCompile(`^[a-z0-9]{4,128}$`)

// classify says what name (cleaned) is, and for a blob its key.
func classify(name string) (entryKind, string) {
	if _, ok := databases[name]; ok {
		return kindDB, name
	}
	if db, ok := strings.CutSuffix(name, "-wal"); ok {
		if _, ok := databases[db]; ok {
			return kindWAL, db
		}
	}
	switch name {
	case "manifest.json":
		return kindManifest, ""
	case "secret.key":
		return kindKey, ""
	}
	parts := strings.Split(name, "/")
	// blobs/<key> or blobs/<tenant>/<key>: a Rails site backup.
	if parts[0] == "blobs" && (len(parts) == 2 || len(parts) == 3) {
		if key := parts[len(parts)-1]; blobKey.MatchString(key) {
			return kindBlob, key
		}
		return kindIgnored, ""
	}
	// storage/<k0k1>/<k2k3>/<key> (Go, or a Rails data directory under
	// storage/) or <k0k1>/<k2k3>/<key> (a Rails data directory's root).
	if parts[0] == "storage" {
		parts = parts[1:]
	}
	if len(parts) == 3 {
		key := parts[2]
		if blobKey.MatchString(key) && parts[0] == key[0:2] && parts[1] == key[2:4] {
			return kindBlob, key
		}
	}
	return kindIgnored, ""
}

// cleanName is an entry's name as a relative slash path, or an error for
// one that reaches outside the archive (absolute, .., a drive letter).
func cleanName(name string) (string, error) {
	if strings.ContainsAny(name, "\\\x00") {
		return "", fmt.Errorf("%w: the entry %q has a backslash or NUL in its name", ErrInvalid, name)
	}
	if strings.HasPrefix(name, "/") {
		return "", fmt.Errorf("%w: the entry %q is an absolute path", ErrInvalid, name)
	}
	for el := range strings.SplitSeq(name, "/") {
		if el == ".." {
			return "", fmt.Errorf("%w: the entry %q climbs out of the archive", ErrInvalid, name)
		}
	}
	clean := path.Clean(name)
	if clean == "." {
		return "", nil
	}
	if !filepath.IsLocal(filepath.FromSlash(clean)) {
		return "", fmt.Errorf("%w: the entry %q isn't a local path", ErrInvalid, name)
	}
	return clean, nil
}

// unpacked is what an archive or directory held, written into staging.
type unpacked struct {
	db       string // which of databases it had, by name
	wal      bool
	manifest *Manifest
	key      string // secret.key's contents
	blobs    map[string]blobFile
	ignored  []string
}

type blobFile struct {
	size int64
	md5  []byte
}

// writer writes the entries a backup may hold into staging, within the
// limits.
type writer struct {
	root    *os.Root // staging
	limits  Limits
	total   int64
	entries int
	out     unpacked
}

func newWriter(staging string, limits Limits) (*writer, error) {
	root, err := os.OpenRoot(staging)
	if err != nil {
		return nil, err
	}
	return &writer{root: root, limits: limits.or(), out: unpacked{blobs: map[string]blobFile{}}}, nil
}

func (w *writer) close() error { return w.root.Close() }

// entry writes one regular file named name (cleaned), size bytes from r.
func (w *writer) entry(ctx context.Context, name string, size int64, r io.Reader) error {
	if err := ctx.Err(); err != nil {
		return err
	}
	w.entries++
	if w.entries > w.limits.MaxEntries {
		return fmt.Errorf("%w: more than %d entries", ErrTooLarge, w.limits.MaxEntries)
	}
	kind, ref := classify(name)
	if kind == kindIgnored {
		if len(w.out.ignored) < 1000 {
			w.out.ignored = append(w.out.ignored, name)
		}
		return nil
	}
	if size > w.limits.MaxFile {
		return fmt.Errorf("%w: %s is %d bytes, over the limit of %d", ErrTooLarge, name, size, w.limits.MaxFile)
	}
	w.total += size
	if w.total > w.limits.MaxTotal {
		return fmt.Errorf("%w: the files come to over %d bytes", ErrTooLarge, w.limits.MaxTotal)
	}
	switch kind {
	case kindManifest, kindKey:
		if size > 1<<20 {
			return fmt.Errorf("%w: %s is too large to be one", ErrInvalid, name)
		}
		raw, err := io.ReadAll(io.LimitReader(r, size))
		if err != nil {
			return err
		}
		if kind == kindKey {
			w.out.key = strings.TrimSpace(string(raw))
			return nil
		}
		var m Manifest
		if err := json.Unmarshal(raw, &m); err != nil {
			return fmt.Errorf("%w: manifest.json isn't JSON: %w", ErrInvalid, err)
		}
		w.out.manifest = &m
		return nil
	case kindDB, kindWAL:
		if w.out.db != "" && w.out.db != ref {
			return fmt.Errorf("%w: it holds two databases (%s and %s); import one at a time", ErrInvalid, w.out.db, ref)
		}
		w.out.db = ref
		dest := stagedDB
		if kind == kindWAL {
			dest, w.out.wal = stagedDB+"-wal", true
		}
		_, err := w.write(dest, size, r, false)
		return err
	default: // kindBlob
		sum, err := w.write(path.Join("storage", ref[0:2], ref[2:4], ref), size, r, true)
		if err != nil {
			return err
		}
		w.out.blobs[ref] = blobFile{size: size, md5: sum}
		return nil
	}
}

// write copies exactly size bytes of r to name under staging, and their
// MD5 when asked.
func (w *writer) write(name string, size int64, r io.Reader, hash bool) ([]byte, error) {
	if err := w.root.MkdirAll(path.Dir(name), 0o750); err != nil {
		return nil, err
	}
	f, err := w.root.OpenFile(name, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, 0o640)
	if err != nil {
		return nil, err
	}
	var dst io.Writer = f
	h := md5.New() //nolint:gosec // Active Storage's checksum
	if hash {
		dst = io.MultiWriter(f, h)
	}
	n, err := io.Copy(dst, io.LimitReader(r, size))
	if cerr := f.Close(); err == nil {
		err = cerr
	}
	if err != nil {
		return nil, err
	}
	if n != size {
		return nil, fmt.Errorf("%w: %s is cut short (%d of %d bytes)", ErrInvalid, name, n, size)
	}
	if !hash {
		return nil, nil
	}
	return h.Sum(nil), nil
}

// fromArchive unpacks a .tar.gz (or a plain .tar) from r.
func (w *writer) fromArchive(ctx context.Context, r io.Reader) error {
	br := bufio.NewReaderSize(r, 64<<10)
	head, err := br.Peek(2)
	if err != nil {
		return fmt.Errorf("%w: it's empty or unreadable", ErrInvalid)
	}
	var src io.Reader = br
	if bytes.Equal(head, []byte{0x1f, 0x8b}) {
		gz, err := gzip.NewReader(br)
		if err != nil {
			return fmt.Errorf("%w: %w", ErrInvalid, err)
		}
		defer gz.Close()
		src = gz
	}
	// Everything decompressed counts, kept or skipped: a bomb is caught
	// however it's packed.
	capped := &capReader{r: src, left: w.limits.MaxTotal + 1<<20}
	tr := tar.NewReader(capped)
	for {
		hdr, err := tr.Next()
		if errors.Is(err, io.EOF) {
			return nil
		}
		if err != nil {
			if capped.left <= 0 {
				return fmt.Errorf("%w: it decompresses to over %d bytes", ErrTooLarge, w.limits.MaxTotal)
			}
			return fmt.Errorf("%w: it isn't a backup archive (%w)", ErrInvalid, err)
		}
		name, err := cleanName(hdr.Name)
		if err != nil {
			return err
		}
		switch hdr.Typeflag {
		case tar.TypeReg, tar.TypeRegA: //nolint:staticcheck // TypeRegA is what old tars write for a file
		case tar.TypeDir, tar.TypeXGlobalHeader:
			continue
		default:
			return fmt.Errorf("%w: the entry %q is a link or a device, which a backup never holds", ErrInvalid, hdr.Name)
		}
		if name == "" {
			continue
		}
		if err := w.entry(ctx, name, hdr.Size, tr); err != nil {
			if capped.left <= 0 {
				return fmt.Errorf("%w: it decompresses to over %d bytes", ErrTooLarge, w.limits.MaxTotal)
			}
			return err
		}
	}
}

// fromDir copies what a directory holds (an unpacked backup, or a data
// directory), refusing links rather than following them.
func (w *writer) fromDir(ctx context.Context, dir string) error {
	root, err := os.OpenRoot(dir)
	if err != nil {
		return err
	}
	defer root.Close()
	return fs.WalkDir(root.FS(), ".", func(p string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if p == "." {
			return nil
		}
		name, err := cleanName(p)
		if err != nil {
			return err
		}
		if d.IsDir() {
			// Not worth descending: what an install keeps beside its data.
			switch name {
			case "imports", "backups", "variants", "releases", "site_imports":
				return fs.SkipDir
			}
			if strings.HasPrefix(name, "replaced-") {
				return fs.SkipDir
			}
			return nil
		}
		if !d.Type().IsRegular() {
			return fmt.Errorf("%w: %s is a link or a device; copy the files themselves", ErrInvalid, name)
		}
		if kind, _ := classify(name); kind == kindIgnored {
			return w.entry(ctx, name, 0, nil)
		}
		info, err := d.Info()
		if err != nil {
			return err
		}
		f, err := root.Open(p)
		if err != nil {
			return err
		}
		defer f.Close()
		return w.entry(ctx, name, info.Size(), f)
	})
}

// capReader reads at most left bytes, then fails.
type capReader struct {
	r    io.Reader
	left int64
}

func (c *capReader) Read(p []byte) (int, error) {
	if c.left <= 0 {
		return 0, errors.New("over the size limit")
	}
	if int64(len(p)) > c.left {
		p = p[:c.left]
	}
	n, err := c.r.Read(p)
	c.left -= int64(n)
	return n, err
}
