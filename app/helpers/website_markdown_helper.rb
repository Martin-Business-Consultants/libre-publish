# frozen_string_literal: true

# The website for machines that read: every page and entry as Markdown
# (/about.md), and /llms.txt, the site's index of them (llmstxt.org). AI
# answer engines and agents read these instead of picking the text out of
# the theme's HTML, so what they quote is the content, whole and in order.
# A block becomes Markdown by its type's fields (BlockType): headings,
# text, links, images and lists, whatever the theme draws it as.
module WebsiteMarkdownHelper
  TITLE_FIELDS = /\A(heading|title|headline|name)\z/
  # A block's settings rather than its words: how it's laid out, where an
  # image is cropped, which form a submission came from.
  SETTING_FIELDS = /(\A|_)(position|style|layout|source|variant|theme|align|alignment|size|class|anchor|id|key|slug|kind)\z/
  BODY_TYPES = %w[text markdown plain_text code].freeze

  def website_markdown_document(record)
    parts = ["# #{record.title}"]
    description = record.seo.to_h["meta_description"].presence
    parts << "> #{website_plain_text(description)}" if description
    if record.is_a?(CollectionEntry)
      # An entry's own fields (a case study's goal and outcome, a service's details), then its body.
      fields = Array(record.collection.fields)
      parts.concat(fields.filter_map { website_field_markdown(it, record.frontmatter.to_h[it["name"]], labelled: true) })
      parts << record.body_markdown.to_s.strip if record.body_markdown.present?
    end
    blocks = record.respond_to?(:expanded_blocks) ? record.expanded_blocks(live: !previewing?) : Array(record.try(:blocks))
    parts.concat(blocks.filter_map { website_block_markdown(it) })
    parts << "---\nSource: #{website_url(record.public_path)}\nUpdated: #{record.updated_at.to_date.iso8601}"
    parts.compact_blank.join("\n\n") + "\n"
  end

  # /llms.txt: the site, then its pages and each collection's entries, each
  # linking to its Markdown with its description.
  def website_llms_txt(entries)
    general = website_settings
    lines = ["# #{general["title"].presence || "Website"}"]
    lines << "" << "> #{website_plain_text(general["description"])}" if general["description"].present?
    records = website_sitemap_records(entries)

    entries.group_by { it.collection_slug }.sort_by { |slug, _| slug.to_s }.each do |slug, rows|
      heading = slug ? (Collection.find_by(slug: slug)&.name || slug.titleize) : "Pages"
      lines << "" << "## #{heading}" << ""
      rows.sort_by(&:loc).each do |row|
        record = records[[row.source, row.id]]
        description = record&.seo.to_h["meta_description"].presence
        markdown = row.loc == "/" ? "/index.md" : "#{row.loc}.md"
        lines << "- [#{row.title}](#{website_url(markdown)})#{": #{website_plain_text(description)}" if description}"
      end
    end
    lines.join("\n") + "\n"
  end

  # A collection's RSS: each entry's title, address, date and description.
  def website_feed_xml(collection, entries)
    general = website_settings
    require "builder"
    xml = ::Builder::XmlMarkup.new
    xml.instruct! :xml, version: "1.0", encoding: "UTF-8"
    xml.rss(version: "2.0", "xmlns:atom": "http://www.w3.org/2005/Atom") do
      xml.channel do
        xml.title [collection.name, general["title"].presence].compact.join(" — ")
        xml.link website_url("/")
        xml.description general["description"].presence || collection.name
        xml.tag! "atom:link", href: website_url("/#{collection.slug}/feed.xml"), rel: "self", type: "application/rss+xml"
        xml.lastBuildDate entries.map(&:updated_at).max&.rfc2822 if entries.any?
        entries.each do |entry|
          xml.item do
            xml.title entry.title
            xml.link website_url(entry.public_path)
            xml.guid website_url(entry.public_path), isPermaLink: "true"
            xml.pubDate (entry.published_at || entry.created_at).rfc2822
            summary = entry.seo.to_h["meta_description"].presence || entry.frontmatter.to_h.values_at("excerpt", "summary", "description").compact_blank.first
            xml.description website_plain_text(summary) if summary.present?
          end
        end
      end
    end
  end

  # Every feed the website has, for a page's <head>.
  def website_feed_tags
    @website_feed_tags ||= Collection.order(:name).select { lookup_context.exists?("website/entries/#{it.slug}", [], false, [], formats: [:html]) }.map do |collection|
      tag.link(rel: "alternate", type: "application/rss+xml", title: collection.name, href: website_url("/#{collection.slug}/feed.xml"))
    end
  end

  private

  def website_sitemap_records(entries)
    entries.group_by(&:source).flat_map do |source, rows|
      model = Sitemap::SOURCES[source]&.constantize or next []
      model.where(id: rows.map(&:id)).map { [[source, it.id], it] }
    end.to_h
  end

  def website_block_markdown(block)
    return unless block.is_a?(Hash)

    data = block["data"].to_h
    # A heading block says its own level.
    if block["type"] == "heading" && data["text"].present?
      return "#{"#" * data["level"].to_i.clamp(2, 6)} #{website_plain_text(data["text"])}"
    end

    fields = website_block_types[block["type"].to_s]&.fields || data.keys.map { {"name" => it, "type" => "text"} }
    parts = fields.filter_map { website_field_markdown(it, data[it["name"]]) }
    if block["resolved"].is_a?(Hash) && block["resolved"]["entries"].is_a?(Array)
      parts << block["resolved"]["entries"].map { "- [#{it["title"]}](#{website_url(it["url"].presence || it["path"].to_s)})" }.join("\n")
    end
    parts.compact_blank.join("\n\n").presence
  end

  def website_field_markdown(field, value, labelled: false)
    return if value.blank?
    return if field["type"].in?(%w[string plain_text]) && field["name"].to_s.match?(SETTING_FIELDS)

    text = website_field_markdown_value(field, value)
    # An entry's fields are named, since nothing around them says what they are.
    return text unless labelled && text.present? && !field["type"].in?(%w[asset repeater group])
    field["name"].to_s.match?(TITLE_FIELDS) ? text : "**#{field["label"].presence || field["name"].to_s.humanize}:** #{text.sub(/\A#+\s*/, "")}"
  end

  def website_field_markdown_value(field, value)
    case field["type"]
    when "string" then field["name"].to_s.match?(TITLE_FIELDS) ? "## #{website_plain_text(value)}" : website_plain_text(value)
    when *BODY_TYPES then value.to_s.lstrip.start_with?("<") ? website_html_markdown(value) : value.to_s.strip
    when "select", "boolean", "integer", "datetime", "record_ref", "record_refs" then nil
    when "string_list" then Array(value).map { "- #{it}" }.join("\n")
    when "url" then "<#{value}>"
    when "link"
      href = website_href(value)
      label = value.to_h["label"].presence || href
      "[#{label}](#{website_url(href)})" if href
    when "asset"
      image = MediaLibrary.find(value)
      "![#{image.try(:alt)}](#{image.try(:absolute_url)})" if image.try(:absolute_url)
    when "repeater", "group"
      items = (field["type"] == "group") ? [value] : Array(value)
      items.filter_map do |item|
        text = Array(field["of"]).filter_map { website_field_markdown(it, item.to_h[it["name"]]) }.join(" — ")
        "- #{text.gsub(/\A#+\s*/, "")}" if text.present?
      end.join("\n")
    end
  end

  # Rich text's HTML, kept as plain paragraphs and lists.
  def website_html_markdown(html)
    fragment = Nokogiri::HTML5.fragment(html.to_s)
    fragment.css("li").each { it.inner_html = "- #{it.inner_html}" }
    fragment.css("h1, h2, h3, h4").each { it.inner_html = "#{"#" * (it.name[1].to_i + 1).clamp(2, 6)} #{it.inner_html}" }
    fragment.css("p, li, h1, h2, h3, h4, blockquote, br").each { it.after("\n\n") }
    fragment.text.gsub(/\n{3,}/, "\n\n").strip
  end
end
