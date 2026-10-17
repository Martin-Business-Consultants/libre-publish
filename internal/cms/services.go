package cms

import (
	"bytes"
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"slices"
	"sort"
	"strings"
	"sync"
	"time"
)

// ---- webhooks ------------------------------------------------------------

// Webhooks posts events to the URLs people registered, signed the way the
// webhook contract says (X-CMS-Signature: sha256=<HMAC of the body>).
type Webhooks struct {
	app *App
	wg  sync.WaitGroup
}

type Webhook struct {
	ID                   int64
	Name, URL, Secret    string
	Events, Headers      JSON
	EventFilters         JSON
	Active               bool
	FailureCount         int
	LastDeliveryAt       Time
	LastStatus           string
	CreatedAt, UpdatedAt Time
}

const webhookCols = `id, name, url, secret, events, headers, event_filters, active, failure_count, last_delivery_at, COALESCE(last_status, ''), created_at, updated_at`

func (w *Webhooks) list(ctx context.Context, where string, args ...any) ([]*Webhook, error) {
	if where == "" {
		where = "1=1"
	}
	rows, err := w.app.Store.DB.QueryContext(ctx, "SELECT "+webhookCols+" FROM webhooks WHERE "+where+" ORDER BY id", args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []*Webhook{}
	for rows.Next() {
		h := &Webhook{}
		if err := rows.Scan(&h.ID, &h.Name, &h.URL, &h.Secret, &h.Events, &h.Headers, &h.EventFilters, &h.Active, &h.FailureCount, &h.LastDeliveryAt, &h.LastStatus, &h.CreatedAt, &h.UpdatedAt); err != nil {
			return nil, err
		}
		h.Events, h.Headers, h.EventFilters = h.Events.Or("[]"), h.Headers.Or("{}"), h.EventFilters.Or("{}")
		out = append(out, h)
	}
	return out, rows.Err()
}

func (h *Webhook) JSON() Obj {
	return O("id", h.ID, "name", h.Name, "url", h.URL, "events", h.Events, "event_filters", h.EventFilters, "headers", Redact(h.Headers.Map()),
		"active", h.Active, "failure_count", h.FailureCount, "last_delivery_at", h.LastDeliveryAt, "last_status", h.LastStatus,
		"created_at", h.CreatedAt, "updated_at", h.UpdatedAt)
}

// secret reads the signing key; a Rails-encrypted one can't be read here
// and has to be rotated.
func (h *Webhook) secret(s *Secrets) (string, bool) {
	if plain, ok := s.Open(h.Secret); ok {
		return plain, true
	}
	if strings.HasPrefix(h.Secret, "{") {
		return "", false
	}
	return h.Secret, true
}

// Deliver sends event to every active webhook listening for it, in the
// background.
func (w *Webhooks) Deliver(event string, data any) {
	hooks, err := w.list(context.Background(), "active = 1")
	if err != nil {
		w.app.Logger.Warn("webhooks", "err", err)
		return
	}
	for _, h := range hooks {
		events := []string{}
		for _, e := range h.Events.List() {
			events = append(events, str(e))
		}
		if len(events) > 0 && !slices.Contains(events, event) && !slices.Contains(events, "*") {
			continue
		}
		w.wg.Add(1)
		go func(h *Webhook) {
			defer w.wg.Done()
			w.send(context.Background(), h, event, data)
		}(h)
	}
}

// Wait is for tests: every delivery started has finished.
func (w *Webhooks) Wait() { w.wg.Wait() }

func (w *Webhooks) tenant() string {
	if w.app.SiteKey != "" {
		return w.app.SiteKey
	}
	host := strings.TrimPrefix(strings.TrimPrefix(w.app.BaseURL, "https://"), "http://")
	return strings.Split(host, ".")[0]
}

// send makes one delivery and records it.
func (w *Webhooks) send(ctx context.Context, h *Webhook, event string, data any) (status int, err error) {
	body, _ := json.Marshal(O("event", event, "tenant", w.tenant(), "delivered_at", time.Now().UTC().Format(time.RFC3339), "data", data))
	start := time.Now()
	defer func() {
		ms := time.Since(start).Milliseconds()
		success := err == nil && status >= 200 && status < 300
		var errText any
		if err != nil {
			errText = err.Error()
		} else if !success {
			errText = fmt.Sprintf("HTTP %d", status)
		}
		db := w.app.Store.DB
		db.ExecContext(ctx, `INSERT INTO webhook_deliveries (webhook_id, event, payload, response_status, success, duration_ms, error, created_at) VALUES (?,?,?,?,?,?,?,?)`,
			h.ID, event, string(body), status, success, ms, errText, Now().DB())
		if success {
			db.ExecContext(ctx, `UPDATE webhooks SET last_delivery_at = ?, last_status = ?, failure_count = 0 WHERE id = ?`, Now().DB(), fmt.Sprint(status), h.ID)
		} else {
			db.ExecContext(ctx, `UPDATE webhooks SET last_delivery_at = ?, last_status = ?, failure_count = failure_count + 1 WHERE id = ?`, Now().DB(), fmt.Sprint(errText), h.ID)
		}
	}()
	secret, ok := h.secret(w.app.Secrets)
	if !ok {
		return 0, fmt.Errorf("the signing secret was written by the Rails core and can't be read here: rotate it")
	}
	if err := checkOutboundURL(h.URL); err != nil {
		return 0, err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, h.URL, bytes.NewReader(body))
	if err != nil {
		return 0, err
	}
	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write(body)
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("User-Agent", "librepublish-webhooks/1")
	req.Header.Set("X-CMS-Event", event)
	req.Header.Set("X-CMS-Signature", "sha256="+hex.EncodeToString(mac.Sum(nil)))
	for k, v := range h.Headers.Map() {
		req.Header.Set(k, str(v))
	}
	resp, err := outboundClient.Do(req)
	if err != nil {
		return 0, err
	}
	io.Copy(io.Discard, io.LimitReader(resp.Body, 1<<16))
	resp.Body.Close()
	return resp.StatusCode, nil
}

var outboundClient = &http.Client{Timeout: 15 * time.Second}

// checkOutboundURL refuses what isn't http(s). (Private addresses are
// allowed: a site on the same box is a normal setup for a one-file CMS.)
func checkOutboundURL(u string) error {
	if !strings.HasPrefix(u, "https://") && !strings.HasPrefix(u, "http://") {
		return fmt.Errorf("only http(s) URLs: %q", u)
	}
	return nil
}

// ---- deploys -------------------------------------------------------------

// Deploys rebuilds the site after content changes: a build hook for a
// static site, a signed purge for one rendered on demand. Changes inside the
// debounce window go out as one.
type Deploys struct {
	app   *App
	mu    sync.Mutex
	tags  map[string]bool
	timer *time.Timer
}

func (d *Deploys) config() map[string]any { return d.app.Setting(context.Background(), "deploy") }

// Changed notes what a publish touched (cache tags) and schedules the
// rebuild or purge.
func (d *Deploys) Changed(tags ...string) {
	cfg := d.config()
	if str(cfg["hook_url"]) == "" && str(d.app.Setting(context.Background(), "frontend")["webhook_url"]) == "" {
		return
	}
	if v, ok := cfg["enabled"]; ok && !boolOf(v) {
		return
	}
	delay := 30 * time.Second
	if s, ok := intOf(cfg["debounce_seconds"]); ok && s >= 0 {
		delay = time.Duration(s) * time.Second
	}
	d.mu.Lock()
	defer d.mu.Unlock()
	if d.tags == nil {
		d.tags = map[string]bool{}
	}
	for _, t := range tags {
		d.tags[t] = true
	}
	if d.timer != nil {
		d.timer.Stop()
	}
	d.timer = time.AfterFunc(delay, func() { d.Trigger(context.Background(), "publish") })
}

// Trigger runs the deploy now and records how it went.
func (d *Deploys) Trigger(ctx context.Context, reason string) (map[string]any, error) {
	d.mu.Lock()
	tags := make([]string, 0, len(d.tags))
	for t := range d.tags {
		tags = append(tags, t)
	}
	d.tags = map[string]bool{}
	d.mu.Unlock()
	sort.Strings(tags)

	cfg := d.config()
	front := d.app.Setting(ctx, "frontend")
	status := map[string]any{"at": time.Now().UTC().Format(time.RFC3339), "reason": reason, "tags": tags}

	var err error
	switch {
	case str(front["render"]) == "server" && str(front["webhook_url"]) != "":
		// On demand: purge what changed, signed with the frontend's secret.
		status["kind"] = "purge"
		err = d.post(ctx, str(front["webhook_url"]), str(front["secret"]), map[string]any{"tags": tags, "reason": reason})
	case str(cfg["hook_url"]) != "":
		status["kind"] = "build"
		err = d.post(ctx, str(cfg["hook_url"]), "", map[string]any{"tags": tags, "reason": reason, "source": "librepublish"})
	default:
		status["status"] = "disabled"
		d.app.PutSetting(ctx, nil, "deploy_status", status, true)
		return status, nil
	}
	if err != nil {
		status["status"], status["error"] = "failure", err.Error()
	} else {
		status["status"] = "success"
	}
	d.app.PutSetting(ctx, nil, "deploy_status", status, true)
	return status, err
}

func (d *Deploys) post(ctx context.Context, url, secret string, payload any) error {
	if err := checkOutboundURL(url); err != nil {
		return err
	}
	body, _ := json.Marshal(payload)
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(body))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	if secret != "" {
		mac := hmac.New(sha256.New, []byte(secret))
		mac.Write(body)
		req.Header.Set("X-CMS-Signature", "sha256="+hex.EncodeToString(mac.Sum(nil)))
	}
	resp, err := outboundClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 300 {
		return fmt.Errorf("the hook answered HTTP %d", resp.StatusCode)
	}
	return nil
}

// ---- the scheduler -------------------------------------------------------

// scheduler publishes and unpublishes what's due, and empties old trash.
func (a *App) scheduler() {
	tick := time.NewTicker(30 * time.Second)
	defer tick.Stop()
	for {
		a.RunSchedule(context.Background())
		select {
		case <-a.stop:
			return
		case <-tick.C:
		}
	}
}

var systemActor = &Actor{Name: "Scheduler", Role: &Role{System: true}}

func (a *App) RunSchedule(ctx context.Context) {
	now := Now().DB()
	for _, kind := range []string{"page", "entry"} {
		var due, gone []*Content
		var err error
		if kind == "page" {
			due, err = a.Pages(ctx, "publish_at IS NOT NULL AND publish_at <= ? AND status != 'published'", now)
			if err == nil {
				gone, err = a.Pages(ctx, "unpublish_at IS NOT NULL AND unpublish_at <= ? AND status = 'published'", now)
			}
		} else {
			due, err = a.Entries(ctx, "e.publish_at IS NOT NULL AND e.publish_at <= ? AND e.status != 'published'", now)
			if err == nil {
				gone, err = a.Entries(ctx, "e.unpublish_at IS NOT NULL AND e.unpublish_at <= ? AND e.status = 'published'", now)
			}
		}
		if err != nil {
			a.Logger.Warn("scheduler", "err", err)
			continue
		}
		for _, c := range due {
			if _, err := a.SaveContent(ctx, systemActor, c, map[string]any{"status": "published"}); err != nil {
				a.Logger.Warn("scheduled publish", "record", c.Label(), "err", err)
			}
		}
		for _, c := range gone {
			if _, err := a.SaveContent(ctx, systemActor, c, map[string]any{"status": "draft", "unpublish_at": nil}); err != nil {
				a.Logger.Warn("scheduled unpublish", "record", c.Label(), "err", err)
			}
		}
	}
	a.Store.DB.ExecContext(ctx, `DELETE FROM device_authorizations WHERE expires_at < ?`, Now().DB())
	a.Store.DB.ExecContext(ctx, `DELETE FROM webhook_deliveries WHERE created_at < ?`, TimeOf(time.Now().Add(-30*24*time.Hour)).DB())
}
