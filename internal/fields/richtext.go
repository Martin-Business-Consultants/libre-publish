package fields

import (
	"fmt"
	"slices"
)

// A richtext field holds the admin's editor's own document: Tiptap's JSON
// (a ProseMirror doc), which the site turns into HTML. Its nodes and marks
// are the editor's (StarterKit with links, and task lists) and no others,
// so what's stored is always what the editor can open again and every site
// knows how to draw.

// richTextNodes are the node types, each with the attributes it may carry.
var richTextNodes = map[string][]string{
	"doc":            nil,
	"paragraph":      {"textAlign"},
	"text":           nil,
	"heading":        {"level", "textAlign"},
	"bulletList":     nil,
	"orderedList":    {"start", "type"},
	"listItem":       nil,
	"taskList":       nil,
	"taskItem":       {"checked"},
	"blockquote":     nil,
	"codeBlock":      {"language"},
	"hardBreak":      nil,
	"horizontalRule": nil,
}

// richTextMarks are the mark types, each with the attributes it may carry.
var richTextMarks = map[string][]string{
	"bold":   nil,
	"italic": nil,
	"strike": nil,
	"code":   nil,
	"link":   {"href", "target", "rel", "class", "title"},
}

const maxRichTextDepth = 32

// richTextProblem is what's wrong with v as a richtext value, or "".
func richTextProblem(v any) string {
	doc, ok := v.(map[string]any)
	if !ok || doc["type"] != "doc" {
		return `must be a rich text document ({"type": "doc", "content": […]})`
	}
	if err := checkNode(doc, 0); err != nil {
		return err.Error()
	}
	return ""
}

func checkNode(n map[string]any, depth int) error {
	if depth > maxRichTextDepth {
		return fmt.Errorf("is nested too deeply")
	}
	typ, _ := n["type"].(string)
	attrs, known := richTextNodes[typ]
	if !known {
		return fmt.Errorf("has a %q node, which the editor doesn't make", typ)
	}
	for k := range n {
		switch k {
		case "type":
		case "attrs":
			if err := checkAttrs(n[k], attrs, typ); err != nil {
				return err
			}
		case "text":
			if s, ok := n[k].(string); typ != "text" || !ok || s == "" {
				return fmt.Errorf("has text where it can't be")
			}
		case "marks":
			if err := checkMarks(n[k], typ); err != nil {
				return err
			}
		case "content":
			list, ok := n[k].([]any)
			if !ok || typ == "text" {
				return fmt.Errorf("has a %s whose content isn't a list of nodes", typ)
			}
			for _, item := range list {
				child, ok := item.(map[string]any)
				if !ok {
					return fmt.Errorf("has content that isn't a node")
				}
				if err := checkNode(child, depth+1); err != nil {
					return err
				}
			}
		default:
			return fmt.Errorf("has a %s with an unknown key %q", typ, k)
		}
	}
	if typ == "text" {
		if _, ok := n["text"].(string); !ok {
			return fmt.Errorf("has a text node without text")
		}
	}
	return nil
}

func checkMarks(v any, typ string) error {
	list, ok := v.([]any)
	if !ok || typ != "text" {
		return fmt.Errorf("has marks where they can't be")
	}
	for _, item := range list {
		m, ok := item.(map[string]any)
		if !ok {
			return fmt.Errorf("has a mark that isn't an object")
		}
		name, _ := m["type"].(string)
		attrs, known := richTextMarks[name]
		if !known {
			return fmt.Errorf("has a %q mark, which the editor doesn't make", name)
		}
		for k := range m {
			if k != "type" && k != "attrs" {
				return fmt.Errorf("has a %s mark with an unknown key %q", name, k)
			}
		}
		if err := checkAttrs(m["attrs"], attrs, name); err != nil {
			return err
		}
		if name == "link" {
			a, _ := m["attrs"].(map[string]any)
			href, _ := a["href"].(string)
			if href == "" || !SafeURL(href) {
				return fmt.Errorf("has a link that isn't a web, email or phone address, or a path")
			}
		}
	}
	return nil
}

func checkAttrs(v any, allowed []string, typ string) error {
	if v == nil {
		return nil
	}
	a, ok := v.(map[string]any)
	if !ok {
		return fmt.Errorf("has a %s whose attrs aren't an object", typ)
	}
	for k, val := range a {
		if !slices.Contains(allowed, k) {
			return fmt.Errorf("has a %s with an unknown attribute %q", typ, k)
		}
		switch val.(type) {
		case nil, string, float64, bool:
		default:
			return fmt.Errorf("has a %s whose %s isn't a plain value", typ, k)
		}
	}
	return nil
}
