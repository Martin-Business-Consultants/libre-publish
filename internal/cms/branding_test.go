package cms

import (
	"bytes"
	"image"
	"image/png"
	"mime/multipart"
	"testing"
)

// upload adds a file to the media library and gives its id.
func (s *site) upload(name string, content []byte) any {
	s.t.Helper()
	var body bytes.Buffer
	mw := multipart.NewWriter(&body)
	fw, _ := mw.CreateFormFile("file", name)
	fw.Write(content)
	mw.Close()
	return dig(s.must(201, s.do(s.admin, "POST", "/api/assets", body.Bytes(), "Content-Type", mw.FormDataContentType())).Body, "asset", "id")
}

func pngOf(t *testing.T, w, h int) []byte {
	t.Helper()
	var b bytes.Buffer
	if err := png.Encode(&b, image.NewRGBA(image.Rect(0, 0, w, h))); err != nil {
		t.Fatal(err)
	}
	return b.Bytes()
}

func TestBranding(t *testing.T) {
	t.Parallel()
	s := newSite(t)
	logo, icon := s.upload("logo.png", pngOf(t, 300, 100)), s.upload("icon.png", pngOf(t, 64, 64))
	doc := s.upload("notes.txt", []byte("not an image"))

	// Everything checked, and named when wrong.
	r := s.must(422, s.do(s.admin, "PATCH", "/api/settings/branding", map[string]any{"setting": map[string]any{"data": map[string]any{
		"logo_id": doc, "favicon_id": 999999, "primary_color": "red; } body { display:none", "secondary_color": "#12345",
		"font": "Comic Sans", "border_radius": "huge", "box_shadow": "giant", "top_bar": "light", "css": "x",
	}}}))
	for _, k := range []string{"logo_id", "favicon_id", "primary_color", "secondary_color", "font", "border_radius", "box_shadow", "top_bar", "css"} {
		if dig(r.Body, "errors", k, 0) == nil {
			t.Errorf("%s not refused: %s", k, r.Raw)
		}
	}

	s.must(200, s.do(s.admin, "PATCH", "/api/settings/branding", map[string]any{"setting": map[string]any{"data": map[string]any{
		"logo_id": logo, "favicon_id": jsonID(icon), "primary_color": "#B45309", "secondary_color": "#1c1917",
		"font": "Lora", "border_radius": "large", "box_shadow": "none", "top_bar": "dark",
	}}}))
	// The site gets the identity (not the admin's top bar)...
	r = s.must(200, s.do(s.prod, "GET", "/api/v1/site", nil))
	b := dig(r.Body, "data", "branding")
	if dig(b, "logo", "id") != logo || dig(b, "logo", "width") != float64(300) || dig(b, "logo", "srcset") == nil || dig(b, "favicon", "id") != icon ||
		dig(b, "primary_color") != "#b45309" || dig(b, "font") != "Lora" || dig(b, "border_radius") != "large" || dig(b, "box_shadow") != "none" || dig(b, "top_bar") != nil {
		t.Fatalf("site branding: %s", r.Raw)
	}
	// ...and the admin all of it, signed in or not (the sign-in page wears it).
	r = s.must(200, s.do("", "GET", "/api/session", nil))
	if dig(r.Body, "branding", "top_bar") != "dark" || dig(r.Body, "branding", "logo", "url") == nil {
		t.Fatalf("session branding: %s", r.Raw)
	}

	// The logo and favicon are in use.
	r = s.must(200, s.do(s.admin, "GET", "/api/assets/"+jsonID(logo), nil))
	if dig(r.Body, "asset", "used_by", 0, "type") != "Setting" || dig(r.Body, "asset", "used_by", 0, "label") != "Logo" {
		t.Fatalf("logo used by: %s", r.Raw)
	}
	r = s.must(200, s.do(s.admin, "GET", "/api/assets?unused=1", nil))
	if dig(r.Body, "pagination", "total") != float64(1) {
		t.Fatalf("only the text file is unused: %s", r.Raw)
	}

	// A save is the whole branding: what's left out or blank is cleared.
	s.must(200, s.do(s.admin, "PATCH", "/api/settings/branding", map[string]any{"setting": map[string]any{"data": map[string]any{
		"primary_color": "#0af", "logo_id": "", "font": nil,
	}}}))
	r = s.must(200, s.do(s.admin, "GET", "/api/settings/branding", nil))
	if d, _ := dig(r.Body, "setting", "data").(map[string]any); len(d) != 1 || d["primary_color"] != "#0af" {
		t.Fatalf("overwritten: %s", r.Raw)
	}

	// Imported data isn't trusted either: what fails the checks isn't delivered.
	if _, err := s.app.store.ExecContext(t.Context(), `UPDATE settings SET data = '{"primary_color":"#fff;}","font":"Inter","border_radius":"x","logo_id":"`+jsonID(doc)+`"}' WHERE key = 'branding'`); err != nil {
		t.Fatal(err)
	}
	r = s.must(200, s.do(s.prod, "GET", "/api/v1/site", nil))
	if b, _ := dig(r.Body, "data", "branding").(map[string]any); len(b) != 1 || b["font"] != "Inter" {
		t.Fatalf("imported branding, checked: %s", r.Raw)
	}
}
