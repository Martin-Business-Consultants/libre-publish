package cms

import (
	"context"
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"database/sql"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"net/http"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"sync"
	"time"

	"golang.org/x/crypto/bcrypt"
)

// ---- capabilities --------------------------------------------------------

const Wildcard = "manage:all"

// Catalog is the capability catalog, grouped as the role editor shows it.
// The same strings the Rails core stores on roles.permissions.
var Catalog = []struct {
	Group string
	Caps  []string
}{
	{"Pages", []string{"pages:read", "pages:write", "pages:delete", "pages:publish"}},
	{"Collections", []string{"collections:read", "collections:write", "collections:delete"}},
	{"Entries", []string{"entries:read", "entries:write", "entries:delete", "entries:publish"}},
	{"Block types", []string{"block_types:read", "block_types:write", "block_types:delete"}},
	{"Globals", []string{"globals:read", "globals:write", "globals:publish", "globals:delete", "globals:scripts"}},
	{"Assets", []string{"assets:read", "assets:write", "assets:delete"}},
	{"Webhooks", []string{"webhooks:read", "webhooks:write", "webhooks:delete"}},
	{"Redirects", []string{"redirects:read", "redirects:write", "redirects:delete"}},
	{"Users", []string{"users:read", "users:write", "users:delete"}},
	{"Roles", []string{"roles:read", "roles:write", "roles:delete"}},
	{"Settings", []string{"settings:read", "settings:write"}},
	{"Audit log", []string{"audit_log:read"}},
	{"Trash", []string{"trash:read", "trash:write"}},
	{"Tools", []string{"tools:use"}},
	{"Plugins", []string{"plugins:read", "plugins:write"}},
}

func AllCapabilities() []string {
	var all []string
	for _, g := range Catalog {
		all = append(all, g.Caps...)
	}
	for _, g := range PluginCaps() {
		all = append(all, g.Caps...)
	}
	return all
}

// capGroup is a plugin's capabilities, as its manifest declares them; the
// enabled plugins' join the catalog.
type capGroup struct {
	Group  string
	Caps   []string
	Labels []string
}

var pluginCaps struct {
	sync.RWMutex
	groups []capGroup
}

func setPluginCaps(g []capGroup) {
	pluginCaps.Lock()
	defer pluginCaps.Unlock()
	pluginCaps.groups = g
}

func PluginCaps() []capGroup {
	pluginCaps.RLock()
	defer pluginCaps.RUnlock()
	return pluginCaps.groups
}

var defaultRoles = []struct {
	Name, Description string
	System            bool
	Caps              []string
}{
	{"Administrator", "Everything, including users, roles and settings.", true, []string{Wildcard}},
	{"Editor", "Writes and publishes content.", false, []string{
		"pages:read", "pages:write", "pages:publish", "collections:read", "entries:read", "entries:write", "entries:publish",
		"block_types:read", "globals:read", "globals:write", "globals:publish", "assets:read", "assets:write",
		"webhooks:read", "redirects:read", "settings:read", "audit_log:read", "trash:read", "trash:write"}},
	{"Author", "Writes drafts.", false, []string{
		"pages:read", "pages:write", "collections:read", "entries:read", "entries:write", "block_types:read",
		"globals:read", "assets:read", "assets:write", "settings:read"}},
	{"Production site", "What a published site reads: live content, nothing else.", false, []string{
		"pages:read", "collections:read", "entries:read", "block_types:read", "globals:read", "assets:read", "redirects:read"}},
	{"Agent", "An agent or script: writes drafts, never publishes them.", false, []string{
		"pages:read", "pages:write", "collections:read", "entries:read", "entries:write", "block_types:read",
		"globals:read", "globals:write", "assets:read", "assets:write", "redirects:read", "settings:read"}},
}

type Role struct {
	ID          int64    `json:"id"`
	Name        string   `json:"name"`
	Description string   `json:"description"`
	Permissions []string `json:"permissions"`
	System      bool     `json:"system"`
	CreatedAt   Time     `json:"created_at"`
	UpdatedAt   Time     `json:"updated_at"`
}

func (r *Role) Can(capability string) bool {
	if r == nil {
		return false
	}
	return r.System || slices.Contains(r.Permissions, Wildcard) || slices.Contains(r.Permissions, capability)
}

func (r *Role) Capabilities() []string {
	if r == nil {
		return []string{}
	}
	if r.System || slices.Contains(r.Permissions, Wildcard) {
		return AllCapabilities()
	}
	out := []string{}
	for _, c := range AllCapabilities() {
		if slices.Contains(r.Permissions, c) {
			out = append(out, c)
		}
	}
	return out
}

// Actor is whoever a request acts as: a person (by session or personal
// token) or a service token, with its role.
type Actor struct {
	UserID    int64
	Name      string
	Email     string
	Role      *Role
	ServiceID int64 // a service token, with no person behind it
	TokenID   int64 // the personal token, when that's how it came
	Session   *adminSession
}

func (a *Actor) Can(capability string) bool { return a.Role.Can(capability) }

func (a *Actor) Label() string {
	if a == nil {
		return "system"
	}
	if a.ServiceID != 0 {
		return a.Name + " (service token)"
	}
	return a.Name
}

func (a *Actor) Type() string {
	if a.ServiceID != 0 {
		return "ServiceToken"
	}
	return "User"
}

func (a *Actor) ID() int64 {
	if a.ServiceID != 0 {
		return a.ServiceID
	}
	return a.UserID
}

// ---- secrets -------------------------------------------------------------

// Secrets keeps the install's key (DATA_DIR/secret.key, made on first run)
// and encrypts what has to be shown again: token plaintexts, settings'
// secrets. A Rails database's encrypted values can't be read without Rails'
// key; they still authenticate (by digest) and show as unreadable.
type Secrets struct {
	key []byte
}

func LoadSecrets(dir string) (*Secrets, error) {
	path := filepath.Join(dir, "secret.key")
	if env := os.Getenv("SECRET_KEY"); env != "" {
		sum := sha256.Sum256([]byte(env))
		return &Secrets{key: sum[:]}, nil
	}
	raw, err := os.ReadFile(path)
	if errors.Is(err, os.ErrNotExist) {
		raw = []byte(hex.EncodeToString(randomBytes(32)))
		if err := os.WriteFile(path, raw, 0o600); err != nil {
			return nil, err
		}
	} else if err != nil {
		return nil, err
	}
	key, err := hex.DecodeString(strings.TrimSpace(string(raw)))
	if err != nil || len(key) != 32 {
		return nil, errors.New("secret.key: expected 64 hex characters")
	}
	return &Secrets{key: key}, nil
}

const sealedPrefix = "go1:"

func (s *Secrets) Seal(plain string) string {
	block, _ := aes.NewCipher(s.key)
	gcm, _ := cipher.NewGCM(block)
	nonce := randomBytes(gcm.NonceSize())
	return sealedPrefix + base64.RawStdEncoding.EncodeToString(gcm.Seal(nonce, nonce, []byte(plain), nil))
}

// Open returns the plaintext, ok false for a value this key didn't seal.
func (s *Secrets) Open(sealed string) (string, bool) {
	if !strings.HasPrefix(sealed, sealedPrefix) {
		return "", false
	}
	raw, err := base64.RawStdEncoding.DecodeString(strings.TrimPrefix(sealed, sealedPrefix))
	if err != nil {
		return "", false
	}
	block, _ := aes.NewCipher(s.key)
	gcm, _ := cipher.NewGCM(block)
	if len(raw) < gcm.NonceSize() {
		return "", false
	}
	plain, err := gcm.Open(nil, raw[:gcm.NonceSize()], raw[gcm.NonceSize():], nil)
	if err != nil {
		return "", false
	}
	return string(plain), true
}

func randomBytes(n int) []byte {
	b := make([]byte, n)
	if _, err := rand.Read(b); err != nil {
		panic(err)
	}
	return b
}

func randomToken(n int) string { return base64.RawURLEncoding.EncodeToString(randomBytes(n)) }

func digest(s string) string {
	sum := sha256.Sum256([]byte(s))
	return hex.EncodeToString(sum[:])
}

// ---- authentication ------------------------------------------------------

const sessionCookie = "lp_session"

func (a *App) authenticate(c *Ctx) (*Actor, error) {
	if h := c.R.Header.Get("Authorization"); strings.HasPrefix(h, "Bearer ") {
		plain := strings.TrimSpace(strings.TrimPrefix(h, "Bearer "))
		actor, err := a.actorForToken(c.R.Context(), plain, c.ip())
		if err != nil {
			return nil, err
		}
		if actor == nil {
			return nil, &Error{Status: 401, Code: "unauthorized", Message: "That token isn't valid: it was rotated, revoked, or never existed."}
		}
		return actor, nil
	}
	cookie, err := c.R.Cookie(sessionCookie)
	if err != nil || cookie.Value == "" {
		return nil, nil
	}
	actor, err := a.actorForSession(c.R.Context(), cookie.Value)
	if err != nil || actor == nil {
		return nil, err
	}
	// A write signed in by the browser's cookie must carry the session's
	// CSRF token, or a sibling site's page could act as whoever is signed in.
	if c.R.Method != http.MethodGet && c.R.Method != http.MethodHead {
		if subtle.ConstantTimeCompare([]byte(c.R.Header.Get("X-CSRF-Token")), []byte(actor.Session.CSRF)) != 1 {
			return nil, &Error{Status: 422, Code: "invalid_authenticity_token", Message: "A write signed in by the browser's session needs the page's CSRF token (X-CSRF-Token), or use a Bearer token."}
		}
	}
	return actor, nil
}

func (a *App) actorForToken(ctx context.Context, plain, ip string) (*Actor, error) {
	if plain == "" {
		return nil, nil
	}
	d := digest(plain)
	db := a.Store.DB
	var tokenID, userID int64
	var lastUsed Time
	err := db.QueryRowContext(ctx, `SELECT id, user_id, last_used_at FROM api_tokens WHERE token_digest = ?`, d).Scan(&tokenID, &userID, &lastUsed)
	if err == nil {
		actor, err := a.actorForUser(ctx, userID)
		if err != nil || actor == nil {
			return actor, err
		}
		actor.TokenID = tokenID
		if !lastUsed.Valid || time.Since(lastUsed.Time) > time.Minute {
			db.ExecContext(ctx, `UPDATE api_tokens SET last_used_at = ?, last_used_ip = ? WHERE id = ?`, Now().DB(), ip, tokenID)
		}
		return actor, nil
	}
	if !errors.Is(err, sql.ErrNoRows) {
		return nil, err
	}
	var st struct {
		id, roleID int64
		name       string
	}
	err = db.QueryRowContext(ctx, `SELECT id, role_id, name, last_used_at FROM service_tokens WHERE token_digest = ? AND revoked_at IS NULL`, d).Scan(&st.id, &st.roleID, &st.name, &lastUsed)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil
	} else if err != nil {
		return nil, err
	}
	role, err := a.role(ctx, st.roleID)
	if err != nil && !errors.Is(err, ErrNotFound) {
		return nil, err
	}
	if !lastUsed.Valid || time.Since(lastUsed.Time) > time.Minute {
		db.ExecContext(ctx, `UPDATE service_tokens SET last_used_at = ?, last_used_ip = ? WHERE id = ?`, Now().DB(), ip, st.id)
	}
	return &Actor{ServiceID: st.id, Name: st.name, Role: role}, nil
}

func (a *App) actorForUser(ctx context.Context, userID int64) (*Actor, error) {
	var actor Actor
	var roleID NullInt
	err := a.Store.DB.QueryRowContext(ctx, `SELECT id, name, email, role_id FROM users WHERE id = ?`, userID).Scan(&actor.UserID, &actor.Name, &actor.Email, &roleID)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil
	} else if err != nil {
		return nil, err
	}
	if roleID.Valid {
		role, err := a.role(ctx, roleID.Int64)
		if err != nil && !errors.Is(err, ErrNotFound) {
			return nil, err
		}
		actor.Role = role
	}
	return &actor, nil
}

func (a *App) role(ctx context.Context, id int64) (*Role, error) {
	var r Role
	var perms JSON
	err := a.Store.DB.QueryRowContext(ctx, `SELECT id, name, COALESCE(description, ''), permissions, system, created_at, updated_at FROM roles WHERE id = ?`, id).
		Scan(&r.ID, &r.Name, &r.Description, &perms, &r.System, &r.CreatedAt, &r.UpdatedAt)
	if err != nil {
		return nil, notFound(err)
	}
	r.Permissions = []string{}
	for _, p := range perms.List() {
		r.Permissions = append(r.Permissions, str(p))
	}
	return &r, nil
}

// roleByName finds a role; "Administrator" (or "Admin") is the system role
// whatever it's called, as a Rails install names it "Admin".
func (a *App) roleByName(ctx context.Context, name string) (*Role, error) {
	var id int64
	err := a.Store.DB.QueryRowContext(ctx, `SELECT id FROM roles WHERE lower(name) = lower(?)`, name).Scan(&id)
	if errors.Is(err, sql.ErrNoRows) && (strings.EqualFold(name, "Administrator") || strings.EqualFold(name, "Admin")) {
		err = a.Store.DB.QueryRowContext(ctx, `SELECT id FROM roles WHERE system = 1 ORDER BY id LIMIT 1`).Scan(&id)
	}
	if err != nil {
		return nil, notFound(err)
	}
	return a.role(ctx, id)
}

// ---- admin sessions ------------------------------------------------------

type adminSession struct {
	ID   int64
	CSRF string
}

func (a *App) actorForSession(ctx context.Context, cookie string) (*Actor, error) {
	var s adminSession
	var userID int64
	var seen Time
	err := a.Store.DB.QueryRowContext(ctx, `SELECT id, csrf, user_id, last_seen_at FROM admin_sessions WHERE token_digest = ?`, digest(cookie)).Scan(&s.ID, &s.CSRF, &userID, &seen)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil
	} else if err != nil {
		return nil, err
	}
	// Two weeks idle signs a session out.
	if seen.Valid && time.Since(seen.Time) > 14*24*time.Hour {
		a.Store.DB.ExecContext(ctx, `DELETE FROM admin_sessions WHERE id = ?`, s.ID)
		return nil, nil
	}
	if !seen.Valid || time.Since(seen.Time) > time.Minute {
		a.Store.DB.ExecContext(ctx, `UPDATE admin_sessions SET last_seen_at = ? WHERE id = ?`, Now().DB(), s.ID)
	}
	actor, err := a.actorForUser(ctx, userID)
	if actor != nil {
		actor.Session = &s
	}
	return actor, err
}

func hashPassword(pw string) (string, error) {
	b, err := bcrypt.GenerateFromPassword([]byte(pw), 12)
	return string(b), err
}

// checkPassword reads Rails' has_secure_password digests as they are: both
// are bcrypt.
func checkPassword(digest, pw string) bool {
	return bcrypt.CompareHashAndPassword([]byte(digest), []byte(pw)) == nil
}

// signIn opens a session for the user and sets its cookie.
func (a *App) signIn(c *Ctx, userID int64) (string, error) {
	cookie := randomToken(32)
	csrf := randomToken(24)
	_, err := a.Store.DB.ExecContext(c.R.Context(), `INSERT INTO admin_sessions (token_digest, csrf, user_id, ip, user_agent, last_seen_at, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)`,
		digest(cookie), csrf, userID, c.ip(), c.R.UserAgent(), Now().DB(), Now().DB())
	if err != nil {
		return "", err
	}
	http.SetCookie(c.W, &http.Cookie{
		Name: sessionCookie, Value: cookie, Path: "/", HttpOnly: true,
		Secure: c.R.TLS != nil || (a.TrustProxy && c.R.Header.Get("X-Forwarded-Proto") == "https") || strings.HasPrefix(a.BaseURL, "https://"), SameSite: http.SameSiteLaxMode,
		MaxAge: 14 * 24 * 3600,
	})
	return csrf, nil
}
