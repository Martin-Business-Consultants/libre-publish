package main

import (
	"encoding/json"
	"strings"

	"github.com/extism/go-pdk"
)

// The host's capabilities, as imports (see docs/plugins.md). One that
// wasn't granted answers {"error": …}.
//
//go:wasmimport extism:host/user lp_kv_get
func lpKvGet(uint64) uint64

//go:wasmimport extism:host/user lp_kv_set
func lpKvSet(uint64) uint64

//go:wasmimport extism:host/user lp_kv_delete
func lpKvDelete(uint64) uint64

//go:wasmimport extism:host/user lp_kv_list
func lpKvList(uint64) uint64

//go:wasmimport extism:host/user lp_mail
func lpMail(uint64) uint64

//go:wasmimport extism:host/user lp_media_put
func lpMediaPut(uint64) uint64

//go:wasmimport extism:host/user lp_site
func lpSite(uint64) uint64

//go:wasmimport extism:host/user lp_log
func lpLog(uint64) uint64

func call(fn func(uint64) uint64, in string) []byte {
	mem := pdk.AllocateString(in)
	defer mem.Free()
	out := pdk.FindMemory(fn(mem.Offset()))
	defer out.Free()
	return out.ReadBytes()
}

// hostError is the {"error": …} a refused or failed call answers.
func hostError(b []byte) string {
	var e struct {
		Error string `json:"error"`
	}
	json.Unmarshal(b, &e)
	return e.Error
}

func kvGet(key string) (string, bool) {
	var r struct {
		Found bool   `json:"found"`
		Value string `json:"value"`
	}
	json.Unmarshal(call(lpKvGet, key), &r)
	return r.Value, r.Found
}

func kvGetJSON(key string, v any) bool {
	s, ok := kvGet(key)
	return ok && json.Unmarshal([]byte(s), v) == nil
}

func kvSet(key, value string) string {
	b, _ := json.Marshal(map[string]string{"key": key, "value": value})
	return hostError(call(lpKvSet, string(b)))
}

func kvSetJSON(key string, v any) string {
	b, _ := json.Marshal(v)
	return kvSet(key, string(b))
}

func kvDelete(key string) { call(lpKvDelete, key) }

// kvKeys lists keys under a prefix, a page at a time: the keys and the
// cursor for the next page ("" at the end).
func kvKeys(prefix, after string, limit int) ([]string, string) {
	q, _ := json.Marshal(map[string]any{"prefix": prefix, "after": after, "limit": limit})
	var r struct {
		Keys []string `json:"keys"`
		Next string   `json:"next"`
	}
	json.Unmarshal(call(lpKvList, string(q)), &r)
	return r.Keys, r.Next
}

// kvAll is every key under a prefix.
func kvAll(prefix string) []string {
	var all []string
	after := ""
	for {
		keys, next := kvKeys(prefix, after, 1000)
		all = append(all, keys...)
		if next == "" {
			return all
		}
		after = next
	}
}

type site struct {
	Name         string   `json:"name"`
	URL          string   `json:"url"`
	CMSURL       string   `json:"cms_url"`
	ContactEmail string   `json:"contact_email"`
	Origins      []string `json:"origins"`
}

func siteInfo() site {
	var s site
	json.Unmarshal(call(lpSite, ""), &s)
	return s
}

type email struct {
	FromName  string   `json:"from_name,omitempty"`
	FromEmail string   `json:"from_email,omitempty"`
	ReplyTo   string   `json:"reply_to,omitempty"`
	To        []string `json:"to"`
	Cc        []string `json:"cc,omitempty"`
	Bcc       []string `json:"bcc,omitempty"`
	Subject   string   `json:"subject"`
	Text      string   `json:"text"`
	HTML      string   `json:"html,omitempty"`
}

// sendMail answers "" when the host took the message, or why it didn't.
func sendMail(m email) string {
	b, _ := json.Marshal(m)
	return hostError(call(lpMail, string(b)))
}

type upload struct {
	ID       int64  `json:"id"`
	URL      string `json:"url"`
	Filename string `json:"filename"`
	Type     string `json:"content_type"`
	Size     int64  `json:"byte_size"`
}

func putMedia(filename, contentType, b64, folder string) (upload, string) {
	in, _ := json.Marshal(map[string]string{"filename": filename, "content_type": contentType, "data": b64, "folder": folder})
	out := call(lpMediaPut, string(in))
	if e := hostError(out); e != "" {
		return upload{}, e
	}
	var u upload
	json.Unmarshal(out, &u)
	return u, ""
}

func logf(msg string) { call(lpLog, msg) }

// ---- requests and answers -------------------------------------------------

type request struct {
	Method  string              `json:"method"`
	Path    string              `json:"path"`
	Query   map[string][]string `json:"query"`
	Headers map[string]string   `json:"headers"`
	Body    string              `json:"body"`
	IP      string              `json:"ip"`
	Actor   *struct {
		Name string `json:"name"`
	} `json:"actor"`
}

func (r request) q(name string) string {
	if v := r.Query[name]; len(v) > 0 {
		return v[0]
	}
	return ""
}

func (r request) header(name string) string {
	for k, v := range r.Headers {
		if strings.EqualFold(k, name) {
			return v
		}
	}
	return ""
}

type response struct {
	Status  int               `json:"status"`
	Headers map[string]string `json:"headers,omitempty"`
	Body    string            `json:"body"`
}

func input() request {
	var req request
	pdk.InputJSON(&req)
	return req
}

func reply(status int, v any) int32 {
	b, _ := json.Marshal(v)
	pdk.OutputJSON(response{Status: status, Headers: map[string]string{"Content-Type": "application/json; charset=utf-8"}, Body: string(b)})
	return 0
}

func replyRaw(status int, headers map[string]string, body string) int32 {
	pdk.OutputJSON(response{Status: status, Headers: headers, Body: body})
	return 0
}

// invalid answers 422 the way the core does, so the admin marks the fields.
func invalid(errs map[string][]string) int32 {
	return reply(422, map[string]any{"error": "invalid", "message": "Validation failed", "errors": errs})
}

func notFound(msg string) int32 {
	return reply(404, map[string]string{"error": "not_found", "message": msg})
}
