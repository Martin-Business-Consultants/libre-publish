# frozen_string_literal: true

# A script pasted into the Scripts global through a rich text editor comes back
# as formatted text ("<p>&lt;script…&gt;<br>…</p>"), which a page prints as
# words instead of running. Undone here: the code as it was pasted. Code that
# was never formatted is left as it is.
module Global::ScriptCode
  FORMATTED = %r{\A\s*<(p|div)\b[^>]*>.*&lt;/?(script|noscript|iframe|img|link|meta|style|!--)}im

  module_function

  def formatted?(code) = code.to_s.match?(FORMATTED)

  def restore(code)
    return code unless formatted?(code)

    text = code.to_s.gsub(%r{<br\s*/?>}i, "\n").gsub(%r{</(p|div)>\s*<(p|div)\b[^>]*>}i, "\n").gsub(%r{</?(p|div|span|strong|em)\b[^>]*>}i, "")
    CGI.unescapeHTML(text).gsub(" ", " ").strip
  end
end
