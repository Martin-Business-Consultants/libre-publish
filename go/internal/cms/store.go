package cms

import (
	"context"
	"database/sql"
	_ "embed"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"

	_ "modernc.org/sqlite"
)

// The schema keeps the Rails app's table and column names, so a database the
// Rails core wrote opens here as it is (docs: go/README.md, "Moving over").
// Every statement is CREATE … IF NOT EXISTS: on a Rails database the tables
// are already there and only the Go core's own (revisions, plugins, …) are
// added.
//
//go:embed schema.sql
var schemaSQL string

// Store is the one database: content, users, settings, everything.
type Store struct {
	DB *sql.DB
}

func OpenStore(path string) (*Store, error) {
	dsn := fmt.Sprintf("file:%s?_pragma=journal_mode(WAL)&_pragma=foreign_keys(1)&_pragma=busy_timeout(10000)&_pragma=synchronous(NORMAL)&_txlock=immediate", path)
	db, err := sql.Open("sqlite", dsn)
	if err != nil {
		return nil, err
	}
	db.SetMaxOpenConns(8)
	if _, err := db.Exec(schemaSQL); err != nil {
		return nil, fmt.Errorf("schema: %w", err)
	}
	return &Store{DB: db}, nil
}

func (s *Store) Close() error { return s.DB.Close() }

// Tx runs fn in one write transaction.
func (s *Store) Tx(ctx context.Context, fn func(*sql.Tx) error) error {
	tx, err := s.DB.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	if err := fn(tx); err != nil {
		tx.Rollback()
		return err
	}
	return tx.Commit()
}

// q is what both *sql.DB and *sql.Tx answer to.
type q interface {
	ExecContext(ctx context.Context, query string, args ...any) (sql.Result, error)
	QueryContext(ctx context.Context, query string, args ...any) (*sql.Rows, error)
	QueryRowContext(ctx context.Context, query string, args ...any) *sql.Row
}

var ErrNotFound = errors.New("not found")

func notFound(err error) error {
	if errors.Is(err, sql.ErrNoRows) {
		return ErrNotFound
	}
	return err
}

// ---- time ----------------------------------------------------------------

// Rails writes SQLite datetimes as UTC text with microseconds; so does this.
const dbTimeFormat = "2006-01-02 15:04:05.999999"

// Time is a nullable timestamp that reads Rails' text format and writes JSON
// the way Rails does (ISO 8601, milliseconds, Z).
type Time struct {
	time.Time
	Valid bool
}

func Now() Time { return Time{Time: time.Now().UTC(), Valid: true} }

func TimeOf(t time.Time) Time { return Time{Time: t.UTC(), Valid: !t.IsZero()} }

func (t *Time) Scan(v any) error {
	switch x := v.(type) {
	case nil:
		*t = Time{}
	case time.Time:
		*t = TimeOf(x)
	case string:
		return t.parse(x)
	case []byte:
		return t.parse(string(x))
	default:
		return fmt.Errorf("time: can't scan %T", v)
	}
	return nil
}

func (t *Time) parse(s string) error {
	s = strings.TrimSpace(s)
	if s == "" {
		*t = Time{}
		return nil
	}
	for _, layout := range []string{dbTimeFormat, time.RFC3339Nano, "2006-01-02T15:04:05.999999", "2006-01-02"} {
		if p, err := time.Parse(layout, s); err == nil {
			*t = TimeOf(p)
			return nil
		}
	}
	return fmt.Errorf("time: can't parse %q", s)
}

func (t Time) DB() any {
	if !t.Valid {
		return nil
	}
	return t.Time.UTC().Format(dbTimeFormat)
}

func (t Time) MarshalJSON() ([]byte, error) {
	if !t.Valid {
		return []byte("null"), nil
	}
	return json.Marshal(t.Time.UTC().Format("2006-01-02T15:04:05.000Z"))
}

func (t *Time) UnmarshalJSON(b []byte) error {
	var s *string
	if err := json.Unmarshal(b, &s); err != nil {
		return err
	}
	if s == nil {
		*t = Time{}
		return nil
	}
	return t.parse(*s)
}

// ISO is the seconds-precision form some answers have always used.
func (t Time) ISO() any {
	if !t.Valid {
		return nil
	}
	return t.Time.UTC().Format(time.RFC3339)
}

// ---- JSON columns --------------------------------------------------------

// JSON is a json column: raw, scanned from text, never nil once read.
type JSON json.RawMessage

func (j *JSON) Scan(v any) error {
	switch x := v.(type) {
	case nil:
		*j = nil
	case string:
		*j = JSON(x)
	case []byte:
		*j = append(JSON(nil), x...)
	default:
		return fmt.Errorf("json: can't scan %T", v)
	}
	return nil
}

func (j JSON) MarshalJSON() ([]byte, error) {
	if len(j) == 0 {
		return []byte("null"), nil
	}
	return j, nil
}

func (j *JSON) UnmarshalJSON(b []byte) error {
	*j = append(JSON(nil), b...)
	return nil
}

func (j JSON) Or(def string) JSON {
	if len(j) == 0 || string(j) == "null" {
		return JSON(def)
	}
	return j
}

func (j JSON) Map() map[string]any {
	m := map[string]any{}
	_ = json.Unmarshal(j, &m)
	if m == nil {
		m = map[string]any{}
	}
	return m
}

func (j JSON) List() []any {
	var l []any
	_ = json.Unmarshal(j, &l)
	if l == nil {
		l = []any{}
	}
	return l
}

func mustJSON(v any) JSON {
	b, err := json.Marshal(v)
	if err != nil {
		panic(err)
	}
	return JSON(b)
}

// NullInt is a nullable integer id, null in JSON when absent.
type NullInt struct {
	sql.NullInt64
}

func (n NullInt) MarshalJSON() ([]byte, error) {
	if !n.Valid {
		return []byte("null"), nil
	}
	return json.Marshal(n.Int64)
}

func (n NullInt) DB() any {
	if !n.Valid {
		return nil
	}
	return n.Int64
}

func IntOf(v int64) NullInt { return NullInt{sql.NullInt64{Int64: v, Valid: true}} }

func placeholders(n int) string {
	return strings.TrimSuffix(strings.Repeat("?,", n), ",")
}
