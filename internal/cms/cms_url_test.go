package cms

import (
	"strings"
	"testing"
)

// The CMS's own address: APP_URL, else Settings › General's CMS address,
// else localhost (which Site health calls out).
func TestCMSAddress(t *testing.T) {
	t.Parallel()
	s := newSiteWith(t, Config{})
	app := s.server.App()
	app.cfg.BaseURL, app.cfg.Addr = "", ":80" // no APP_URL

	if got := app.BaseURL(); got != "http://localhost:80" {
		t.Fatalf("unset: %q", got)
	}
	if app.addressKnown() || !strings.Contains(string(s.must(200, s.do(s.admin, "GET", "/api/v1/site_health", nil)).Raw), `"cms_url"`) {
		t.Fatal("an unknown address isn't called out")
	}

	for _, bad := range []string{"javascript:alert(1)", "cms.example.com", "https://cms.example.com/?a=1", "ftp://cms.example.com"} {
		s.must(422, s.do(s.admin, "PATCH", "/api/settings/general", map[string]any{"setting": map[string]any{"data": map[string]any{"cms_url": bad}}}))
	}
	s.must(200, s.do(s.admin, "PATCH", "/api/settings/general", map[string]any{"setting": map[string]any{"data": map[string]any{"cms_url": " https://cms.oldmill.example/ "}}}))
	if got := app.BaseURL(); got != "https://cms.oldmill.example" || !app.addressKnown() {
		t.Fatalf("set: %q", got)
	}
	if got := s.must(200, s.do(s.admin, "GET", "/api/settings/general", nil)).Body; dig(got, "setting", "data", "cms_url") != "https://cms.oldmill.example" {
		t.Fatalf("stored: %v", got)
	}

	// Kept across a restart, as the next App reads it.
	again, err := NewApp(app.cfg)
	if err == nil {
		defer again.Close()
	}
	if err != nil || again.BaseURL() != "https://cms.oldmill.example" {
		t.Fatalf("reopened: %v %q", err, again.BaseURL())
	}

	// APP_URL wins over the setting; clearing the setting goes back to localhost.
	app.cfg.BaseURL = "https://from-env.example"
	if got := app.BaseURL(); got != "https://from-env.example" {
		t.Fatalf("APP_URL: %q", got)
	}
	app.cfg.BaseURL = ""
	s.must(200, s.do(s.admin, "PATCH", "/api/settings/general", map[string]any{"setting": map[string]any{"data": map[string]any{"cms_url": ""}}}))
	if got := app.BaseURL(); got != "http://localhost:80" {
		t.Fatalf("cleared: %q", got)
	}
}
