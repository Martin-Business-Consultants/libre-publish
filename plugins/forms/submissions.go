package main

import (
	"bytes"
	"encoding/csv"
	"encoding/json"
	"slices"
	"strings"
)

func loadSubmission(id string) (Submission, bool) {
	slug, ok := kvGet("all:" + id)
	if !ok {
		return Submission{}, false
	}
	var s Submission
	return s, kvGetJSON("sub:"+slug+":"+id, &s)
}

// summary is how a submission is named in lists: its first name- or
// email-like answer, else its first answer.
func summary(f Form, s Submission) (string, string) {
	var first, best, excerpt string
	for _, fl := range f.Fields {
		v := display(s.Values[fl.Name])
		if v == "" || fl.layout() || fl.Type == "hidden" || fl.Type == "file" {
			continue
		}
		if first == "" {
			first = v
		}
		if best == "" && (fl.Type == "email" || strings.Contains(fl.Name, "name")) {
			best = v
		}
		if excerpt == "" && fl.Type == "textarea" {
			excerpt = v
		}
	}
	if best == "" {
		best = first
	}
	if best == "" {
		best = "Submission " + s.ID
	}
	if r := []rune(excerpt); len(r) > 90 {
		excerpt = string(r[:90]) + "…"
	}
	return best, excerpt
}

//go:wasmexport list_submissions
func listSubmissions() int32 {
	req := input()
	slug, status := req.q("form"), req.q("status")
	forms := allForms()
	byslug := map[string]Form{}
	options := []map[string]string{{"value": "", "label": "Every form"}}
	total := stats{}
	for _, f := range forms {
		byslug[f.Slug] = f
		options = append(options, map[string]string{"value": f.Slug, "label": f.Name})
		if slug == "" || slug == f.Slug {
			st := formStats(f.Slug)
			total.New, total.Read, total.Spam, total.Total = total.New+st.New, total.Read+st.Read, total.Spam+st.Spam, total.Total+st.Total
		}
	}
	if req.q("count") == "new" {
		return reply(200, map[string]any{"count": total.New})
	}
	statuses := []map[string]any{
		{"value": "", "label": "All", "count": total.Total - total.Spam},
		{"value": "new", "label": "Unread", "count": total.New},
		{"value": "read", "label": "Read", "count": total.Read},
		{"value": "spam", "label": "Spam", "count": total.Spam},
	}
	prefix := "all:"
	if slug != "" {
		prefix = "sub:" + slug + ":"
	}
	const per = 25
	rows := []map[string]any{}
	after, next := req.q("after"), ""
	for len(rows) < per {
		keys, more := kvKeys(prefix, after, 100)
		for i, k := range keys {
			id := k[strings.LastIndex(k, ":")+1:]
			s, ok := loadSubmission(id)
			if !ok || (status == "" && s.Status == "spam") || (status != "" && s.Status != status) {
				continue
			}
			name, excerpt := summary(byslug[s.Form], s)
			rows = append(rows, map[string]any{"id": s.ID, "summary": name, "excerpt": excerpt, "form": s.Form,
				"form_name": strOr(byslug[s.Form].Name, s.Form), "status": s.Status, "submitted_at": s.SubmittedAt})
			if len(rows) == per {
				if i < len(keys)-1 || more != "" {
					next = k
				}
				break
			}
		}
		if more == "" || len(rows) == per {
			break
		}
		after = more
	}
	return reply(200, map[string]any{"submissions": rows, "next": next, "forms": options, "statuses": statuses})
}

//go:wasmexport show_submission
func showSubmission() int32 {
	req := input()
	s, ok := loadSubmission(req.q("id"))
	if !ok {
		return notFound("No submission " + req.q("id") + ".")
	}
	f, _ := loadForm(s.Form)
	// Opening an unread one reads it.
	if s.Status == "new" {
		setStatus(&s, "read")
	}
	answers := []map[string]any{}
	seen := map[string]bool{}
	for _, fl := range f.Fields {
		if fl.layout() {
			continue
		}
		seen[fl.Name] = true
		item := map[string]any{"label": strOr(fl.Label, fl.Name), "value": display(s.Values[fl.Name])}
		if u, ok := s.Files[fl.Name]; ok {
			item["value"], item["href"] = u.Filename, u.URL
		}
		if fl.Type == "email" {
			item["href"] = "mailto:" + display(s.Values[fl.Name])
		}
		if fl.Type == "textarea" {
			item["multiline"] = true
		}
		answers = append(answers, item)
	}
	// Answers to fields the form no longer has are kept, and shown.
	var extra []string
	for k := range s.Values {
		if !seen[k] {
			extra = append(extra, k)
		}
	}
	slices.Sort(extra)
	for _, k := range extra {
		answers = append(answers, map[string]any{"label": k + " (removed field)", "value": display(s.Values[k])})
	}
	name, _ := summary(f, s)
	details := []map[string]any{
		{"label": "Form", "value": strOr(f.Name, s.Form), "screen": "form", "params": map[string]string{"id": s.Form}},
		{"label": "Received", "value": s.SubmittedAt, "time": true},
		{"label": "Status", "value": s.Status, "badge": true},
		{"label": "From address", "value": s.IP},
		{"label": "Browser", "value": s.UserAgent},
		{"label": "Page", "value": s.Referer, "href": s.Referer},
	}
	if s.SpamReason != "" {
		details = append(details, map[string]any{"label": "Why it's spam", "value": s.SpamReason})
	}
	mail := []map[string]any{}
	for _, k := range []string{"admin", "client"} {
		if v, ok := s.Mail[k]; ok {
			mail = append(mail, map[string]any{"label": map[string]string{"admin": "To you", "client": "Confirmation"}[k], "value": v,
				"tone": map[bool]string{true: "danger", false: "success"}[!strings.HasPrefix(v, "sent")]})
		}
	}
	if len(mail) == 0 {
		mail = append(mail, map[string]any{"label": "Email", "value": "None sent"})
	}
	return reply(200, map[string]any{"submission": map[string]any{"id": s.ID, "summary": name, "status": s.Status, "form": s.Form,
		"answers": answers, "details": details, "mail": mail}})
}

func setStatus(s *Submission, status string) {
	if s.Status == status {
		return
	}
	st := formStats(s.Form)
	st.add(s.Status, -1)
	st.add(status, 1)
	s.Status = status
	kvSetJSON("stat:"+s.Form, st)
	kvSetJSON("sub:"+s.Form+":"+s.ID, *s)
}

//go:wasmexport set_submission_status
func setSubmissionStatus() int32 {
	req := input()
	var body struct {
		Status string `json:"status"`
	}
	json.Unmarshal([]byte(req.Body), &body)
	if body.Status != "new" && body.Status != "read" && body.Status != "spam" {
		return invalid(map[string][]string{"status": {"is new, read or spam"}})
	}
	s, ok := loadSubmission(req.q("id"))
	if !ok {
		return notFound("No submission " + req.q("id") + ".")
	}
	setStatus(&s, body.Status)
	return reply(200, map[string]any{"ok": true, "message": map[string]string{"spam": "Marked as spam.", "read": "Marked as read.", "new": "Marked as unread."}[body.Status]})
}

//go:wasmexport delete_submission
func deleteSubmission() int32 {
	req := input()
	s, ok := loadSubmission(req.q("id"))
	if !ok {
		return notFound("No submission " + req.q("id") + ".")
	}
	st := formStats(s.Form)
	st.add(s.Status, -1)
	kvSetJSON("stat:"+s.Form, st)
	kvDelete("sub:" + s.Form + ":" + s.ID)
	kvDelete("all:" + s.ID)
	return reply(200, map[string]any{"ok": true, "message": "Deleted."})
}

// export_submissions is a form's submissions (or every form's) as CSV, a
// column per field, newest first.
//
//go:wasmexport export_submissions
func exportSubmissions() int32 {
	req := input()
	slug, status := req.q("form"), req.q("status")
	forms := []Form{}
	if slug != "" {
		f, ok := loadForm(slug)
		if !ok {
			return notFound("No form " + slug + ".")
		}
		forms = append(forms, f)
	} else {
		forms = allForms()
	}
	var cols []Field
	seen := map[string]bool{}
	for _, f := range forms {
		for _, fl := range f.Fields {
			if !fl.layout() && !seen[fl.Name] {
				seen[fl.Name] = true
				cols = append(cols, fl)
			}
		}
	}
	var buf bytes.Buffer
	w := csv.NewWriter(&buf)
	head := []string{"Submitted", "Form", "Status"}
	for _, c := range cols {
		head = append(head, strOr(c.Label, c.Name))
	}
	w.Write(head)
	for _, f := range forms {
		for _, k := range kvAll("sub:" + f.Slug + ":") {
			var s Submission
			if !kvGetJSON(k, &s) || (status == "" && s.Status == "spam") || (status != "" && s.Status != status) {
				continue
			}
			row := []string{s.SubmittedAt, f.Name, s.Status}
			for _, c := range cols {
				row = append(row, csvSafe(display(s.Values[c.Name])))
			}
			w.Write(row)
		}
	}
	w.Flush()
	name := "submissions"
	if slug != "" {
		name = slug + "-submissions"
	}
	return replyRaw(200, map[string]string{"Content-Type": "text/csv; charset=utf-8",
		"Content-Disposition": `attachment; filename="` + name + `.csv"`}, "\ufeff"+buf.String())
}

// csvSafe keeps a spreadsheet from running what a visitor typed as a
// formula.
func csvSafe(v string) string {
	if v != "" && strings.ContainsRune("=+-@\t\r", rune(v[0])) {
		return "'" + v
	}
	return v
}
