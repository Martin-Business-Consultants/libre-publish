package main

import "github.com/extism/go-pdk"

const version = "1.0.0"

// The field types the builder offers. "input" is how the admin previews
// one; "props" are what its inspector edits.
var palette = []map[string]any{
	{"type": "text", "label": "Text", "icon": "text", "input": "text", "props": []string{"placeholder", "default", "max_length"}},
	{"type": "email", "label": "Email", "icon": "email", "input": "email", "props": []string{"placeholder"}},
	{"type": "tel", "label": "Phone", "icon": "phone", "input": "tel", "props": []string{"placeholder"}},
	{"type": "textarea", "label": "Paragraph", "icon": "paragraph", "input": "textarea", "props": []string{"placeholder", "rows", "max_length"}},
	{"type": "number", "label": "Number", "icon": "hash", "input": "number", "props": []string{"placeholder", "min", "max"}},
	{"type": "select", "label": "Dropdown", "icon": "dropdown", "input": "select", "props": []string{"options", "placeholder", "default"}},
	{"type": "radio", "label": "Choice", "icon": "radio", "input": "radio", "props": []string{"options", "default"}},
	{"type": "checkboxes", "label": "Checkboxes", "icon": "checkboxes", "input": "checkboxes", "props": []string{"options"}},
	{"type": "checkbox", "label": "Consent", "icon": "check-square", "input": "checkbox", "props": []string{"text"}},
	{"type": "date", "label": "Date", "icon": "calendar", "input": "date", "props": []string{}},
	{"type": "url", "label": "Website", "icon": "link", "input": "url", "props": []string{"placeholder"}},
	{"type": "file", "label": "File upload", "icon": "upload", "input": "file", "props": []string{"accept", "max_mb"}},
	{"type": "hidden", "label": "Hidden", "icon": "eye-off", "input": "hidden", "props": []string{"default"}},
	{"type": "heading", "label": "Heading", "icon": "heading", "input": "heading", "props": []string{"text"}, "layout": true},
}

var mergeHelp = "Merge tags: {{ name of a field }}, {{ all_fields }}, {{ form_name }}, {{ site_name }}, {{ submission_id }}, {{ date }}."

// The tags every message can use, after the form's own fields.
var tagCatalog = map[string]any{"builder": "fields", "extra": []map[string]string{
	{"name": "all_fields", "label": "All answers", "hint": "Every answer, as a table"},
	{"name": "form_name", "label": "Form name"},
	{"name": "site_name", "label": "Site name"},
	{"name": "date", "label": "Date received"},
	{"name": "submission_id", "label": "Submission id"},
}}

func screens() []map[string]any {
	statusOptions := []map[string]string{{"value": "active", "label": "Accepting submissions"}, {"value": "closed", "label": "Closed"}}
	emailFields := map[string]any{"builder": "fields", "types": []string{"email"}}
	return []map[string]any{
		{
			"id": "forms", "title": "Forms", "menu": "All forms", "source": "/forms",
			"actions": []map[string]any{{"label": "New form", "screen": "form", "primary": true, "icon": "add"}},
			"table": map[string]any{
				"rows": "forms", "key": "slug",
				"columns": []map[string]any{
					{"key": "name", "label": "Name", "link": map[string]any{"screen": "form", "params": map[string]string{"id": "slug"}}, "sub": "slug"},
					{"key": "field_count", "label": "Fields", "num": true},
					{"key": "submissions", "label": "Submissions", "num": true, "link": map[string]any{"screen": "submissions", "params": map[string]string{"form": "slug"}}},
					{"key": "status", "label": "Status", "badge": true},
					{"key": "updated_at", "label": "Updated", "time": true},
				},
				"row_actions": []map[string]any{
					{"label": "Edit", "screen": "form", "params": map[string]string{"id": "slug"}},
					{"label": "Submissions", "screen": "submissions", "params": map[string]string{"form": "slug"}},
					{"label": "Duplicate", "post": "/form/duplicate", "params": map[string]string{"id": "slug"}},
					{"label": "Delete", "post": "/form/delete", "params": map[string]string{"id": "slug"}, "danger": true,
						"confirm": "Delete this form and all of its submissions? This can't be undone."},
				},
				"empty": map[string]string{"title": "No forms yet", "text": "Build a contact form, a quote request or a sign-up: drag fields in, choose who's emailed, and the site posts to it."},
			},
		},
		{
			"id": "form", "title": "Form", "title_key": "name", "new_title": "New form", "parent": "forms", "source": "/form",
			"form": map[string]any{
				"record": "form", "save": "/form", "key": "slug",
				"tabs": []map[string]any{
					{"id": "general", "title": "General", "sections": []map[string]any{
						{"title": "Form", "fields": []map[string]any{
							{"name": "name", "label": "Name", "type": "string", "required": true},
							{"name": "slug", "label": "Slug", "type": "string", "help": "How the site names it: /api/x/forms/submit?form=<slug>. Blank: made from the name."},
							{"name": "status", "label": "Status", "type": "select", "options": statusOptions},
							{"name": "store_submissions", "label": "Keep submissions here", "type": "boolean", "help": "Off: only emailed."},
						}},
						{"title": "On the site", "readonly": "embed"},
					}},
					{"id": "editor", "title": "Editor", "sections": []map[string]any{
						{"fields": []map[string]any{{"name": "fields", "type": "form_builder", "palette": palette}}},
					}},
					{"id": "admin", "title": "Admin Confirmation", "sections": []map[string]any{
						{"title": "Email each submission to you", "fields": []map[string]any{
							{"name": "admin_enabled", "label": "Email each submission", "type": "boolean"},
							{"name": "admin_to", "label": "Send to", "type": "string_list", "help": "Addresses that get each submission. Blank: the site's contact email (Settings › General), else the reply-to or from address in Settings › Email."},
							{"name": "admin_cc", "label": "Cc", "type": "string_list"},
							{"name": "admin_bcc", "label": "Bcc", "type": "string_list"},
							{"name": "admin_subject", "label": "Subject", "type": "string", "help": mergeHelp},
							{"name": "admin_message", "label": "Message", "type": "rich_text", "merge_tags": tagCatalog},
							{"name": "admin_reply_to_field", "label": "Reply to", "type": "select", "options_from": emailFields, "help": "Replying goes to the address the visitor typed in this field."},
						}},
						{"title": "Sent from", "fields": []map[string]any{
							{"name": "admin_from_name", "label": "From name", "type": "string", "help": "Blank: the default in Settings › Email."},
							{"name": "admin_from_email", "label": "From address", "type": "string", "help": "Blank: the default in Settings › Email. Use an address your mail server may send as."},
						}},
					}},
					{"id": "client", "title": "User Confirmation", "sections": []map[string]any{
						{"title": "Email the visitor a confirmation", "fields": []map[string]any{
							{"name": "client_enabled", "label": "Send a confirmation", "type": "boolean"},
							{"name": "client_to_field", "label": "Send to the address in", "type": "select", "options_from": emailFields},
							{"name": "client_subject", "label": "Subject", "type": "string", "help": mergeHelp},
							{"name": "client_message", "label": "Message", "type": "rich_text", "merge_tags": tagCatalog},
						}},
						{"title": "Sent from", "fields": []map[string]any{
							{"name": "client_from_name", "label": "From name", "type": "string", "help": "Blank: the default in Settings › Email."},
							{"name": "client_from_email", "label": "From address", "type": "string", "help": "Blank: the default in Settings › Email."},
							{"name": "client_reply_to", "label": "Reply-to address", "type": "string", "help": "Where the visitor's reply goes. Blank: the from address."},
						}},
					}},
					{"id": "spam", "title": "Spam", "sections": []map[string]any{
						{"title": "Spam protection", "fields": []map[string]any{
							{"name": "honeypot", "label": "Honeypot field", "type": "boolean", "help": "A hidden _hp field bots fill in and people don't."},
							{"name": "min_seconds", "label": "Slower than (seconds)", "type": "integer", "help": "Submissions sent sooner after the page set _ts are spam. 0: off."},
						}},
						{"title": "Captcha", "fields": []map[string]any{
							{"name": "captcha", "label": "Provider", "type": "select", "options": []map[string]string{
								{"value": "none", "label": "None"}, {"value": "turnstile", "label": "Cloudflare Turnstile"}, {"value": "recaptcha", "label": "Google reCAPTCHA"}},
								"help": "The site shows the provider's widget and every submission must pass it."},
							{"name": "turnstile_site_key", "label": "Site key", "type": "string", "show_if": map[string]string{"captcha": "turnstile"}, "help": "From the Cloudflare dashboard › Turnstile."},
							{"name": "turnstile_secret", "label": "Secret key", "type": "password", "show_if": map[string]string{"captcha": "turnstile"}},
							{"name": "recaptcha_site_key", "label": "Site key", "type": "string", "show_if": map[string]string{"captcha": "recaptcha"}, "help": "From the reCAPTCHA admin console (v2 or v3)."},
							{"name": "recaptcha_secret", "label": "Secret key", "type": "password", "show_if": map[string]string{"captcha": "recaptcha"}},
							{"name": "recaptcha_min_score", "label": "Lowest score (v3)", "type": "number", "show_if": map[string]string{"captcha": "recaptcha"}, "help": "0 to 1; submissions scoring lower are refused. Blank: any that pass (v2)."},
						}},
					}},
					{"id": "after", "title": "After Submission", "sections": []map[string]any{
						{"title": "After submitting", "fields": []map[string]any{
							{"name": "submit_label", "label": "Button label", "type": "string"},
							{"name": "success_message", "label": "Thank-you message", "type": "text"},
							{"name": "redirect_url", "label": "Or send them to", "type": "string", "help": "A page on the site (/thanks) or an address. Blank: show the message."},
						}},
					}},
				},
			},
		},
		{
			"id": "submissions", "title": "Submissions", "menu": "Submissions", "source": "/submissions",
			"actions": []map[string]any{{"label": "Export CSV", "download": "/submissions.csv", "keep": []string{"form", "status"}, "icon": "download"}},
			"table": map[string]any{
				"rows": "submissions", "key": "id",
				"status_links": map[string]any{"param": "status", "options": "statuses"},
				"filters":      []map[string]any{{"param": "form", "label": "Form", "options": "forms"}},
				"cursor":       map[string]any{"param": "after", "next": "next"},
				"columns": []map[string]any{
					{"key": "summary", "label": "Submission", "link": map[string]any{"screen": "submission", "params": map[string]string{"id": "id"}}, "sub": "excerpt"},
					{"key": "form_name", "label": "Form"},
					{"key": "status", "label": "Status", "badge": true},
					{"key": "submitted_at", "label": "Received", "time": true},
				},
				"row_actions": []map[string]any{
					{"label": "View", "screen": "submission", "params": map[string]string{"id": "id"}},
					{"label": "Spam", "post": "/submission/status", "params": map[string]string{"id": "id"}, "body": map[string]string{"status": "spam"}},
					{"label": "Delete", "post": "/submission/delete", "params": map[string]string{"id": "id"}, "danger": true, "confirm": "Delete this submission?"},
				},
				"empty": map[string]string{"title": "No submissions", "text": "When someone sends one of your forms, it shows here."},
			},
		},
		{
			"id": "submission", "title": "Submission", "title_key": "summary", "parent": "submissions", "source": "/submission",
			"detail": map[string]any{
				"record": "submission",
				"main":   []map[string]any{{"title": "Answers", "items": "answers"}},
				"side":   []map[string]any{{"title": "Details", "items": "details"}, {"title": "Email", "items": "mail"}},
				"actions": []map[string]any{
					{"label": "Mark as read", "post": "/submission/status", "params": map[string]string{"id": "id"}, "body": map[string]string{"status": "read"}, "hide_if": map[string]string{"status": "read"}},
					{"label": "Mark as spam", "post": "/submission/status", "params": map[string]string{"id": "id"}, "body": map[string]string{"status": "spam"}, "hide_if": map[string]string{"status": "spam"}},
					{"label": "Not spam", "post": "/submission/status", "params": map[string]string{"id": "id"}, "body": map[string]string{"status": "read"}, "show_if": map[string]string{"status": "spam"}},
					{"label": "Delete", "post": "/submission/delete", "params": map[string]string{"id": "id"}, "danger": true, "confirm": "Delete this submission?", "then": "submissions"},
				},
			},
		},
	}
}

//go:wasmexport manifest
func manifest() int32 {
	read, write := "forms:read", "forms:write"
	pdk.OutputJSON(map[string]any{
		"key":         "forms",
		"name":        "Forms",
		"version":     version,
		"description": "Build forms visually, keep their submissions, and email them to you and a confirmation to the visitor.",
		"permissions": map[string]any{"storage": true, "mail": true, "media:write": true, "http": []string{"challenges.cloudflare.com", "www.google.com"}},
		"capabilities": []map[string]string{
			{"key": read, "label": "See forms and their submissions"},
			{"key": write, "label": "Build forms and manage submissions"},
		},
		"routes": []map[string]any{
			{"method": "GET", "path": "/definition", "export": "definition", "public": true},
			{"method": "POST", "path": "/submit", "export": "submit", "public": true, "max_body": 10 << 20},
			{"method": "GET", "path": "/forms", "export": "list_forms", "capability": read},
			{"method": "GET", "path": "/form", "export": "show_form", "capability": read},
			{"method": "POST", "path": "/form", "export": "save_form", "capability": write},
			{"method": "POST", "path": "/form/duplicate", "export": "duplicate_form", "capability": write},
			{"method": "POST", "path": "/form/delete", "export": "delete_form", "capability": write},
			{"method": "GET", "path": "/submissions", "export": "list_submissions", "capability": read},
			{"method": "GET", "path": "/submissions.csv", "export": "export_submissions", "capability": read},
			{"method": "GET", "path": "/submission", "export": "show_submission", "capability": read},
			{"method": "POST", "path": "/submission/status", "export": "set_submission_status", "capability": write},
			{"method": "POST", "path": "/submission/delete", "export": "delete_submission", "capability": write},
		},
		"admin": map[string]any{
			"menu":    map[string]any{"label": "Forms", "icon": "form", "group": "Content", "badge": "/submissions?count=new"},
			"screens": screens(),
		},
		"site_config": map[string]any{"definition": "/api/x/forms/definition?form=<slug>", "submit": "/api/x/forms/submit?form=<slug>"},
	})
	return 0
}

func main() {}
