# frozen_string_literal: true

require "rails_helper"

RSpec.describe GoImport::RichText do
  def doc(*content) = {"type" => "doc", "content" => content}

  def text(words, *marks) = {"type" => "text", "text" => words, **(marks.any? ? {"marks" => marks} : {})}

  def para(*content) = {"type" => "paragraph", "content" => content}

  def html(value) = described_class.new(value).to_html

  it "draws every node the Go editor makes" do
    value = doc(
      {"type" => "heading", "attrs" => {"level" => 3, "textAlign" => "center"}, "content" => [text("Title")]},
      para(text("a"), {"type" => "hardBreak"}, text("b")),
      {"type" => "bulletList", "content" => [{"type" => "listItem", "content" => [para(text("one"))]}]},
      {"type" => "orderedList", "attrs" => {"start" => 4}, "content" => [{"type" => "listItem", "content" => [para(text("four"))]}]},
      {"type" => "taskList", "content" => [
        {"type" => "taskItem", "attrs" => {"checked" => true}, "content" => [para(text("done"))]},
        {"type" => "taskItem", "attrs" => {"checked" => false}, "content" => [para(text("to do"))]}
      ]},
      {"type" => "blockquote", "content" => [para(text("quoted"))]},
      {"type" => "codeBlock", "attrs" => {"language" => "ruby"}, "content" => [text("a < b")]},
      {"type" => "horizontalRule"}
    )

    expect(html(value)).to eq(
      "<h3>Title</h3><p>a<br>b</p><ul><li><p>one</p></li></ul><ol start=\"4\"><li><p>four</p></li></ol>" \
      "<ul><li><input type=\"checkbox\" checked=\"\" disabled=\"\"> <p>done</p></li><li><input type=\"checkbox\" disabled=\"\"> <p>to do</p></li></ul>" \
      "<blockquote><p>quoted</p></blockquote><pre><code class=\"language-ruby\">a &lt; b</code></pre><hr>"
    )
  end

  it "nests marks as the editor does, the first outermost, and escapes the text" do
    link = {"type" => "link", "attrs" => {"href" => "https://example.test/?a=1&b=2", "target" => "_blank", "class" => "x"}}
    value = doc(para(text("<b>&", {"type" => "bold"}, {"type" => "italic"}), text("go", {"type" => "strike"}, link), text("x", {"type" => "code"})))

    expect(html(value)).to eq(
      "<p><strong><em>&lt;b&gt;&amp;</em></strong><s><a href=\"https://example.test/?a=1&amp;b=2\" target=\"_blank\">go</a></s><code>x</code></p>"
    )
  end

  it "keeps a link's words but not the link when it isn't a web, email or phone address, or a path" do
    value = doc(para(
      text("bad", {"type" => "link", "attrs" => {"href" => "java\nscript:alert(1)"}}),
      text(" mail", {"type" => "link", "attrs" => {"href" => "mailto:a@example.test"}}),
      text(" path", {"type" => "link", "attrs" => {"href" => "/about"}})
    ))

    expect(html(value)).to eq('<p>bad<a href="mailto:a@example.test"> mail</a><a href="/about"> path</a></p>')
  end

  it "keeps the words of a node or mark the Go editor doesn't make, and names it" do
    rich_text = described_class.new(doc({"type" => "table", "content" => [para(text("cell <1>"))]}, para(text("u", {"type" => "underline"}))))

    expect(rich_text.to_html).to eq("<p>cell &lt;1&gt;</p><p>u</p>")
    expect(rich_text.dropped).to contain_exactly("table", "underline mark")
  end

  it "draws an empty document as nothing, and knows a document" do
    expect(html(doc)).to eq("")
    expect(html(doc(para))).to eq("<p></p>")
    expect(described_class.doc?(doc)).to be(true)
    expect(described_class.doc?({"type" => "hero"})).to be(false)
    expect(described_class.doc?("<p>x</p>")).to be(false)
  end
end
