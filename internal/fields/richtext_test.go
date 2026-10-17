package fields

import (
	"encoding/json"
	"testing"
)

func TestRichTextProblem(t *testing.T) {
	t.Parallel()
	for _, tc := range []struct {
		name, doc string
		ok        bool
	}{
		{"empty doc", `{"type":"doc"}`, true},
		{"paragraph with marks", `{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"Built in "},{"type":"text","text":"1869","marks":[{"type":"bold"}]}]}]}`, true},
		{"heading, lists, quote, break, rule", `{"type":"doc","content":[{"type":"heading","attrs":{"level":2},"content":[{"type":"text","text":"Hi"}]},{"type":"bulletList","content":[{"type":"listItem","content":[{"type":"paragraph","content":[{"type":"text","text":"a"},{"type":"hardBreak"},{"type":"text","text":"b"}]}]}]},{"type":"blockquote","content":[{"type":"paragraph"}]},{"type":"horizontalRule"},{"type":"taskList","content":[{"type":"taskItem","attrs":{"checked":true},"content":[{"type":"paragraph"}]}]}]}`, true},
		{"link", `{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"menu","marks":[{"type":"link","attrs":{"href":"/menu/","target":null,"rel":"noopener noreferrer nofollow","class":null}}]}]}]}`, true},
		{"mailto link", `{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"mail","marks":[{"type":"link","attrs":{"href":"mailto:a@b.c"}}]}]}]}`, true},
		{"a string", `"<p>hi</p>"`, false},
		{"not a doc", `{"type":"paragraph"}`, false},
		{"unknown node", `{"type":"doc","content":[{"type":"image","attrs":{"src":"x"}}]}`, false},
		{"unknown mark", `{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"x","marks":[{"type":"textStyle","attrs":{"color":"red"}}]}]}]}`, false},
		{"javascript link", `{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"x","marks":[{"type":"link","attrs":{"href":"javascript:alert(1)"}}]}]}]}`, false},
		{"unknown attribute", `{"type":"doc","content":[{"type":"paragraph","attrs":{"onclick":"x"}}]}`, false},
		{"text outside a text node", `{"type":"doc","content":[{"type":"paragraph","text":"x"}]}`, false},
		{"empty text node", `{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":""}]}]}`, false},
		{"marks on a paragraph", `{"type":"doc","content":[{"type":"paragraph","marks":[{"type":"bold"}]}]}`, false},
		{"object attr", `{"type":"doc","content":[{"type":"heading","attrs":{"level":{"x":1}}}]}`, false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			var v any
			if err := json.Unmarshal([]byte(tc.doc), &v); err != nil {
				t.Fatal(err)
			}
			if got := richTextProblem(v); (got == "") != tc.ok {
				t.Fatalf("richTextProblem = %q, want ok=%v", got, tc.ok)
			}
		})
	}
}
