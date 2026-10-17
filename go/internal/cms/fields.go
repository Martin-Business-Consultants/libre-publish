package cms

import (
	"encoding/json"
	"fmt"
	"math"
	"regexp"
	"slices"
	"strings"
	"time"
)

// The field DSL, as the Rails core has it (BlockType::Validator): field
// definitions are [{"name", "label", "type", …}] arrays, shared by block
// types, collection and page schemas, and globals. Definitions are kept as
// written (keys this core doesn't know travel untouched); Field is the view
// of one this core reasons with.

var FieldTypes = []string{
	"string", "text", "markdown", "code", "integer", "boolean", "select", "url", "datetime",
	"link", "asset", "record_ref", "record_refs", "repeater", "group", "blocks", "string_list",
}

var (
	fieldNameFormat = regexp.MustCompile(`^[a-z][a-z0-9_]*$`)
	blockSlugFormat = regexp.MustCompile(`^[a-z][a-z0-9_]*$`)
)

const maxFieldDepth = 4

type Field struct {
	Name         string
	Label        string
	Type         string
	Required     bool
	Help         string
	Options      []string
	OfCollection string
	AllowedTypes []string
	Of           []Field
}

// ParseFields reads definitions from JSON ([…] or {"fields": […]}).
func ParseFields(raw any) []Field {
	switch x := raw.(type) {
	case JSON:
		var v any
		json.Unmarshal(x, &v)
		return ParseFields(v)
	case map[string]any:
		return ParseFields(x["fields"])
	case []any:
		out := make([]Field, 0, len(x))
		for _, item := range x {
			m, ok := item.(map[string]any)
			if !ok {
				continue
			}
			f := Field{
				Name: str(m["name"]), Label: str(m["label"]), Type: str(m["type"]),
				Required: boolOf(m["required"]), Help: str(m["help"]), OfCollection: str(m["of_collection"]),
			}
			for _, o := range asList(m["options"]) {
				if om, ok := o.(map[string]any); ok {
					f.Options = append(f.Options, str(om["value"]))
				} else {
					f.Options = append(f.Options, str(o))
				}
			}
			for _, t := range asList(m["allowed_types"]) {
				f.AllowedTypes = append(f.AllowedTypes, str(t))
			}
			f.Of = ParseFields(m["of"])
			out = append(out, f)
		}
		return out
	}
	return []Field{}
}

func asList(v any) []any {
	l, _ := v.([]any)
	return l
}

func (f Field) title() string {
	if f.Label != "" {
		return f.Label
	}
	return strings.ReplaceAll(strings.ToUpper(f.Name[:1])+f.Name[1:], "_", " ")
}

// ValidateDefinitions checks a schema's field definitions themselves.
func ValidateDefinitions(raw any, allowBlocks bool, into Invalid, prefix string) {
	list, ok := raw.([]any)
	if raw == nil {
		return
	}
	if !ok {
		into.Add(prefix, "must be a list of field definitions")
		return
	}
	validateDefs(list, allowBlocks, into, prefix, 1)
}

func validateDefs(list []any, allowBlocks bool, into Invalid, prefix string, depth int) {
	if depth > maxFieldDepth {
		into.Add(prefix, fmt.Sprintf("nests deeper than %d levels", maxFieldDepth))
		return
	}
	seen := map[string]bool{}
	for i, item := range list {
		at := fmt.Sprintf("%s[%d]", prefix, i)
		m, ok := item.(map[string]any)
		if !ok {
			into.Add(at, "must be an object")
			continue
		}
		name, typ := str(m["name"]), str(m["type"])
		if !fieldNameFormat.MatchString(name) {
			into.Add(at+".name", "must start with a letter and use only a-z, 0-9 and _")
		}
		if seen[name] {
			into.Add(at+".name", "is used twice: "+name)
		}
		seen[name] = true
		if !slices.Contains(FieldTypes, typ) || (typ == "blocks" && !allowBlocks) {
			into.Add(at+".type", "isn't a field type here: "+typ)
		}
		if typ == "select" && len(asList(m["options"])) == 0 {
			into.Add(at+".options", "a select needs options")
		}
		if typ == "repeater" || typ == "group" {
			validateDefs(asList(m["of"]), allowBlocks, into, at+".of", depth+1)
		}
	}
}

// BlockTypes resolves a block's type to its fields; nil for an unknown one.
type BlockTypes func(slug string) ([]Field, bool)

// ValidateData checks data written against fields, adding problems under
// prefix ("frontmatter", "data", "blocks[2].data"), by the Rails core's
// rules (BlockType::Validator), so what one core accepts the other reads.
func ValidateData(fields []Field, data map[string]any, types BlockTypes, into Invalid, prefix string) {
	for _, f := range fields {
		at := joinPath(prefix, f.Name)
		v := data[f.Name]
		if l, isList := v.([]any); v == nil || v == "" || (isList && len(l) == 0) {
			if f.Required {
				into.Add(at, "is required")
			}
			continue
		}
		validateValue(f, v, types, into, at, 1)
	}
}

func joinPath(prefix, name string) string {
	if prefix == "" {
		return name
	}
	return prefix + "." + name
}

var safeSchemes = []string{"http", "https", "mailto", "tel"}
var schemePattern = regexp.MustCompile(`^([a-zA-Z][a-zA-Z0-9+.\-]*):`)

// SafeURL: http(s), mailto:, tel:, or a path — never javascript: and kin.
func SafeURL(u string) bool {
	clean := strings.Map(func(r rune) rune {
		if r <= ' ' || r == 0x7f {
			return -1
		}
		return r
	}, u)
	m := schemePattern.FindStringSubmatch(clean)
	return m == nil || slices.Contains(safeSchemes, strings.ToLower(m[1]))
}

const unsafeURLMessage = "must be a web address (http or https), mailto:, tel:, or a path"

func validateValue(f Field, v any, types BlockTypes, into Invalid, at string, depth int) {
	switch f.Type {
	case "string", "text", "markdown", "code", "asset", "record_ref":
		if _, ok := v.(string); !ok {
			into.Add(at, "must be a string")
		}
	case "url":
		s, ok := v.(string)
		if !ok || strings.TrimSpace(s) == "" {
			into.Add(at, "must be a URL")
		} else if !SafeURL(s) {
			into.Add(at, unsafeURLMessage)
		}
	case "integer":
		if n, ok := v.(float64); !ok || n != math.Trunc(n) {
			into.Add(at, "must be an integer")
		}
	case "boolean":
		if _, ok := v.(bool); !ok {
			into.Add(at, "must be true or false")
		}
	case "select":
		if s, ok := v.(string); !ok || !slices.Contains(f.Options, s) {
			into.Add(at, "must be one of "+strings.Join(f.Options, ", "))
		}
	case "datetime":
		s, ok := v.(string)
		if _, err := time.Parse(time.RFC3339, s); !ok || err != nil {
			into.Add(at, "must be an ISO 8601 datetime")
		}
	case "link":
		m, ok := v.(map[string]any)
		val, _ := m["value"].(string)
		kind := str(m["kind"])
		if !ok || !slices.Contains([]string{"url", "page", "entry"}, kind) || strings.TrimSpace(val) == "" {
			into.Add(at, "must be { kind: url|page|entry, value: string }")
			return
		}
		if kind == "url" && !SafeURL(val) {
			into.Add(at, unsafeURLMessage)
		}
		if col, _ := m["collection"].(string); kind == "entry" && strings.TrimSpace(col) == "" {
			into.Add(at, "kind=entry requires a collection")
		}
	case "record_refs":
		l, ok := v.([]any)
		for _, item := range l {
			if s, isStr := item.(string); !isStr || s == "" {
				ok = false
			}
		}
		if !ok {
			into.Add(at, "must be an array of record slugs")
		}
	case "string_list":
		l, ok := v.([]any)
		for _, item := range l {
			if _, isStr := item.(string); !isStr {
				ok = false
			}
		}
		if !ok {
			into.Add(at, "must be an array of strings")
		}
	case "group":
		m, ok := v.(map[string]any)
		if !ok {
			into.Add(at, "must be an object")
			return
		}
		if depth < maxFieldDepth {
			ValidateData(f.Of, m, types, into, at)
		}
	case "repeater":
		l, ok := v.([]any)
		if !ok {
			into.Add(at, "must be an array")
			return
		}
		for i, item := range l {
			m, ok := item.(map[string]any)
			if !ok {
				into.Add(fmt.Sprintf("%s[%d]", at, i), "must be an object")
				continue
			}
			if depth < maxFieldDepth {
				ValidateData(f.Of, m, types, into, fmt.Sprintf("%s[%d]", at, i))
			}
		}
	case "blocks":
		l, ok := v.([]any)
		if !ok {
			into.Add(at, "must be an array")
			return
		}
		ValidateBlocks(l, f.AllowedTypes, types, into, at)
	}
}

// ValidateBlocks checks a body of blocks: [{id, type, version, data}].
func ValidateBlocks(list []any, allowed []string, types BlockTypes, into Invalid, prefix string) {
	for i, item := range list {
		at := fmt.Sprintf("%s[%d]", prefix, i)
		b, ok := item.(map[string]any)
		if !ok {
			into.Add(at, "must be a block object")
			continue
		}
		typ := str(b["type"])
		if typ == "" {
			into.Add(at+".type", "is required")
			continue
		}
		if len(allowed) > 0 && !slices.Contains(allowed, typ) {
			into.Add(at+".type", "'"+typ+"' isn't allowed here")
			continue
		}
		fields, known := types(typ)
		if !known {
			into.Add(at+".type", "unknown block type '"+typ+"'")
			continue
		}
		data, _ := b["data"].(map[string]any)
		if b["data"] != nil && data == nil {
			into.Add(at+".data", "must be an object")
			continue
		}
		if data == nil {
			data = map[string]any{}
		}
		ValidateData(fields, data, types, into, at+".data")
	}
}

// ---- JSON Schema ---------------------------------------------------------

// JSONSchema is the JSON Schema for data written against fields, each
// property annotated with its label (title), help (description) and the
// CMS's own type (x-cms-type), as the Rails core publishes it.
func JSONSchema(fields []Field) map[string]any {
	props := map[string]any{}
	required := []string{}
	for _, f := range fields {
		props[f.Name] = fieldSchema(f)
		if f.Required {
			required = append(required, f.Name)
		}
	}
	return map[string]any{"type": "object", "properties": props, "required": required, "additionalProperties": false}
}

func fieldSchema(f Field) map[string]any {
	s := map[string]any{"x-cms-type": f.Type}
	if f.Label != "" {
		s["title"] = f.Label
	}
	if f.Help != "" {
		s["description"] = f.Help
	}
	nested := func() (map[string]any, []string) {
		props, req := map[string]any{}, []string{}
		for _, sf := range f.Of {
			props[sf.Name] = fieldSchema(sf)
			if sf.Required {
				req = append(req, sf.Name)
			}
		}
		return props, req
	}
	switch f.Type {
	case "integer":
		s["type"] = "integer"
	case "boolean":
		s["type"] = "boolean"
	case "datetime":
		s["type"], s["format"] = "string", "date-time"
	case "select":
		s["type"], s["enum"] = "string", f.Options
	case "link":
		s["type"] = "object"
		s["properties"] = map[string]any{
			"kind":       map[string]any{"type": "string", "enum": []string{"url", "page", "entry"}},
			"value":      map[string]any{"type": "string"},
			"collection": map[string]any{"type": "string"},
		}
		s["required"] = []string{"kind", "value"}
	case "record_refs", "string_list":
		s["type"], s["items"] = "array", map[string]any{"type": "string"}
	case "repeater":
		props, req := nested()
		s["type"], s["items"] = "array", map[string]any{"type": "object", "properties": props, "required": req}
	case "group":
		props, req := nested()
		s["type"], s["properties"], s["required"] = "object", props, req
	case "blocks":
		s["type"] = "array"
		s["items"] = map[string]any{"type": "object", "required": []string{"type", "data"}, "properties": map[string]any{
			"type": map[string]any{"type": "string"}, "version": map[string]any{"type": "integer"}, "data": map[string]any{"type": "object"},
		}}
	case "url":
		s["type"], s["format"] = "string", "uri-reference"
	default:
		s["type"] = "string"
	}
	return s
}

// ---- references ----------------------------------------------------------

// Ref is something content points at, as the Rails core indexes it in
// content_references: kind asset (ref_type "asset", the asset id), record
// (ref_type the collection slug, the entry slug), page (ref_type "page", the
// page path) or link (ref_type "url", the address).
type Ref struct {
	Kind    string
	RefType string
	RefID   string
}

// FieldRefs walks data against fields for what it points at.
func FieldRefs(fields []Field, data map[string]any, types BlockTypes, out *[]Ref) {
	for _, f := range fields {
		v, ok := data[f.Name]
		if !ok || v == nil {
			continue
		}
		s, _ := v.(string)
		switch f.Type {
		case "asset":
			if s != "" {
				*out = append(*out, Ref{"asset", "asset", s})
			}
		case "record_ref", "record_refs":
			col := f.OfCollection
			if col == "" {
				col = "record"
			}
			items := asList(v)
			if s != "" {
				items = []any{s}
			}
			for _, item := range items {
				if slug, ok := item.(string); ok && slug != "" {
					*out = append(*out, Ref{"record", col, slug})
				}
			}
		case "url":
			if s != "" {
				*out = append(*out, Ref{"link", "url", s})
			}
		case "link":
			m, _ := v.(map[string]any)
			val, _ := m["value"].(string)
			if val == "" {
				continue
			}
			switch str(m["kind"]) {
			case "url":
				*out = append(*out, Ref{"link", "url", val})
			case "page":
				*out = append(*out, Ref{"page", "page", val})
			case "entry":
				if col, ok := m["collection"].(string); ok {
					*out = append(*out, Ref{"record", col, val})
				}
			}
		case "group":
			if m, ok := v.(map[string]any); ok {
				FieldRefs(f.Of, m, types, out)
			}
		case "repeater":
			for _, item := range asList(v) {
				if m, ok := item.(map[string]any); ok {
					FieldRefs(f.Of, m, types, out)
				}
			}
		case "blocks":
			for _, item := range asList(v) {
				BlockRefs(item, types, out)
			}
		}
	}
}

// BlockRefs walks one block.
func BlockRefs(item any, types BlockTypes, out *[]Ref) {
	b, ok := item.(map[string]any)
	if !ok {
		return
	}
	fields, known := types(str(b["type"]))
	data, _ := b["data"].(map[string]any)
	if known && data != nil {
		FieldRefs(fields, data, types, out)
	}
}
