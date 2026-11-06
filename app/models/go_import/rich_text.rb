# frozen_string_literal: true

require "cgi"

# A Go core rich text value (its `richtext` field type: the admin editor's
# Tiptap document, ProseMirror JSON) as the HTML a `text` field holds here.
#
# Only the nodes and marks the Go editor makes are drawn (its
# internal/fields/richtext.go: StarterKit with links and task lists); a node
# it doesn't make keeps its text, and is named in #dropped so the import can
# say so. A task list is drawn as Markdown's are here (Markdown.to_html): a
# list whose items start with a disabled checkbox. A link that isn't a web,
# email or phone address, or a path, loses its link and keeps its words.
#
#   GoImport::RichText.new({"type" => "doc", "content" => [...]}).to_html
#   # => "<h2>Welcome</h2><p>We are <strong>bold</strong></p>"
class GoImport::RichText
  BLOCKS = {
    "paragraph" => "p", "blockquote" => "blockquote", "bulletList" => "ul", "orderedList" => "ol",
    "listItem" => "li", "taskList" => "ul", "taskItem" => "li"
  }.freeze
  MARKS = {"bold" => "strong", "italic" => "em", "strike" => "s", "code" => "code"}.freeze
  LINK_ATTRIBUTES = %w[href target rel title].freeze
  MAX_DEPTH = 32

  def self.doc?(value) = value.is_a?(Hash) && value["type"] == "doc"

  attr_reader :dropped

  def initialize(doc)
    @doc = doc
    @dropped = []
  end

  def to_html
    children(@doc, 0)
  end

  private

  def children(node, depth)
    Array(node["content"]).filter_map { node_html(it, depth + 1) if it.is_a?(Hash) }.join
  end

  def node_html(node, depth)
    return text_of(node) if depth > MAX_DEPTH

    type = node["type"].to_s
    attrs = node["attrs"].is_a?(Hash) ? node["attrs"] : {}
    case type
    when "text" then marked(node["text"].to_s, node["marks"])
    when "hardBreak" then "<br>"
    when "horizontalRule" then "<hr>"
    when "heading"
      level = attrs["level"].to_i.clamp(1, 6)
      "<h#{level}>#{children(node, depth)}</h#{level}>"
    when "orderedList"
      start = attrs["start"].to_i
      "<ol#{%( start="#{start}") if start > 1}>#{children(node, depth)}</ol>"
    when "taskItem"
      box = attrs["checked"] == true ? %(<input type="checkbox" checked="" disabled="">) : %(<input type="checkbox" disabled="">)
      "<li>#{box} #{children(node, depth)}</li>"
    when "codeBlock"
      language = attrs["language"].to_s[/\A[\w+#.-]+\z/]
      code = Array(node["content"]).sum("") { it.is_a?(Hash) ? it["text"].to_s : "" }
      "<pre><code#{%( class="language-#{language}") if language}>#{escape(code)}</code></pre>"
    when *BLOCKS.keys
      "<#{BLOCKS[type]}>#{children(node, depth)}</#{BLOCKS[type]}>"
    else
      @dropped << type
      text = text_of(node)
      text.empty? ? nil : "<p>#{text}</p>"
    end
  end

  # The first mark is the outermost, as the editor nests them.
  def marked(text, marks)
    Array(marks).reverse.reduce(escape(text)) do |html, mark|
      next html unless mark.is_a?(Hash)

      if (tag = MARKS[mark["type"]])
        "<#{tag}>#{html}</#{tag}>"
      elsif mark["type"] == "link"
        link(html, mark["attrs"].is_a?(Hash) ? mark["attrs"] : {})
      else
        @dropped << "#{mark["type"]} mark"
        html
      end
    end
  end

  def link(html, attrs)
    href = attrs["href"].to_s.strip
    return html unless safe_url?(href)

    rendered = LINK_ATTRIBUTES.filter_map { |name| %( #{name}="#{escape(attrs[name].to_s)}") if attrs[name].present? }.join
    "<a#{rendered}>#{html}</a>"
  end

  # The Go core's SafeURL: http(s), mailto:, tel:, or no scheme at all (a path).
  def safe_url?(url)
    return false if url.empty?

    scheme = url.gsub(/[\x00-\x20\x7f]/, "")[/\A([a-zA-Z][a-zA-Z0-9+.-]*):/, 1]
    scheme.nil? || %w[http https mailto tel].include?(scheme.downcase)
  end

  def text_of(node)
    return escape(node["text"].to_s) if node["type"] == "text"

    Array(node["content"]).sum("") { it.is_a?(Hash) ? text_of(it) : "" }
  end

  def escape(text) = CGI.escapeHTML(text)
end
