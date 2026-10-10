# frozen_string_literal: true

# What a theme draws the website with: the CMS's content as fields held to
# their schemas (Website::Fields), links and images as the browser needs
# them, text made safe, and the <head> a page's SEO panel describes. Every
# read is of live content, so a theme never shows a draft unless the page is
# an editor's preview.
module WebsiteHelper
  # The widths an image is offered at (srcset). The browser picks by `sizes`.
  WEBSITE_IMAGE_WIDTHS = [480, 800, 1200, 1600, 2400].freeze

  # A page's (or an entry's) blocks, each drawn by the theme's
  # website/blocks/_<type> partial with its fields as `data` (and what the
  # CMS resolved for it, a collection list's entries say, as data.resolved).
  # A type the theme has no partial for is left out.
  def website_blocks(record)
    blocks = record.respond_to?(:expanded_blocks) ? record.expanded_blocks(live: !previewing?) : Array(record.try(:blocks))
    safe_join(blocks.filter_map { website_block(it) })
  end

  def website_block(block)
    type = block["type"].to_s
    partial = "website/blocks/#{type}"
    unless lookup_context.exists?(partial, [], true)
      logger.warn("[website] the theme has no partial for #{type.inspect} blocks")
      return
    end

    render partial, data: Website::Fields.new(block["data"], website_block_types[type]&.fields, name: type, resolved: block["resolved"])
  end

  # What editors paste into the "scripts" global (analytics, a chat widget),
  # for the <head> (part: "head") or the end of <body> ("body"): trusted as
  # written, since only someone who can edit globals can put it there.
  def website_scripts(part)
    items = Global.find_by(slug: "scripts") ? website_global(:scripts).items : []
    safe_join(items.filter_map { it[part].to_s.html_safe if it.enabled != false && it[part].present? }, "\n") # rubocop:disable Rails/OutputSafety
  end

  # A global's data, by slug.
  def website_global(slug)
    (@website_globals ||= {})[slug.to_s] ||= begin
      global = Global.find_by!(slug: slug)
      Website::Fields.new(global.data, global.fields, name: "global #{slug}")
    end
  end

  # An entry's frontmatter (a page's, for a page with fields of its own).
  def website_fields(record)
    (@website_fields ||= {})[record] ||= case record
    when CollectionEntry then Website::Fields.new(record.frontmatter, record.collection.fields, name: "#{record.collection.slug}/#{record.slug}")
    else Website::Fields.new(record.frontmatter, record.try(:schema)&.dig("fields"), name: record.try(:path).to_s)
    end
  end

  # A collection's published entries, by a frontmatter field (lowest first;
  # unset last), then title.
  def website_entries(collection_slug, order: "order")
    (@website_entries ||= {})[[collection_slug.to_s, order]] ||= begin
      entries = Collection.find_by!(slug: collection_slug).entries
      entries = entries.live unless previewing?
      entries.sort_by { [it.frontmatter.to_h[order].nil? ? 1 : 0, it.frontmatter.to_h[order].to_f, it.title.to_s] }
    end
  end

  def website_path(record) = record.public_path

  # A link field ({kind, value}) as an href: a URL as written ("#contact"
  # too), a page by its path ("home" is "/"), an entry at its own address.
  def website_href(link)
    link = link.to_h.stringify_keys
    value = link["value"].to_s
    return if value.empty?

    case link["kind"]
    when "page" then Page.find_by(path: value)&.public_path || (value == "home" ? "/" : "/#{value}")
    when "entry" then "/#{link["collection"]}/#{value}"
    else value
    end
  end

  # Settings › General: the business's name, description and contact details.
  def website_settings = @website_settings ||= Setting.get("general").to_h

  # An asset (by id) as an <img>: a srcset of resized copies, its own width
  # and height so the page doesn't shift as it loads, its alt text (or
  # `alt:`; "" for a decorative image) and its focal point as the crop.
  # Nothing for a missing or deleted asset.
  def website_image_tag(id, sizes: "100vw", alt: nil, loading: :lazy, fetchpriority: nil, position: nil, **options)
    image = website_image(id) or return
    style = [options.delete(:style), ("object-position: #{position || image[:position]}" if position || image[:position])].compact.join("; ")
    tag.img(src: image[:src], srcset: image[:srcset], sizes: (sizes if image[:srcset]), width: image[:width], height: image[:height],
      alt: alt || image[:alt], loading:, decoding: (loading.to_s == "eager" ? "sync" : "async"), fetchpriority:,
      style: style.presence, **options)
  end

  # {src:, srcset:, width:, height:, alt:, position:} for an asset id, or nil.
  # Resized copies are proxied through the site, so a CDN in front of it
  # caches them like any other file.
  def website_image(id)
    return if id.blank?

    (@website_images ||= {})[id.to_s] ||= begin
      asset = MediaLibrary.find(id)
      asset&.file&.attached? ? website_image_attributes(asset) : false
    end.presence
  end

  # An asset's absolute URL at one width (no wider than the image), for
  # where a srcset won't do: an email, a sharing card. Nil for a missing one.
  def website_image_url(id, width: 1200)
    asset = id.presence && MediaLibrary.find(id)
    return unless asset&.file&.attached?

    file = asset.variantable? && ApplicationHelper.variants_supported? && asset.width.to_i > width ? asset.file.variant(resize_to_limit: [width, nil]) : asset.file
    website_url(rails_storage_proxy_path(file))
  end

  # Markdown (a markdown field, an entry's body) as HTML. HTML written into
  # it is kept, then everything is held to Markdown's safe tags.
  def website_markdown(text)
    return "" if text.blank?

    html = Commonmarker.to_html(text.to_s, options: Markdown::OPTIONS.deep_merge(render: {unsafe: true}), plugins: {syntax_highlighter: nil})
    sanitize(html, tags: Markdown::TAGS, attributes: Markdown::ATTRIBUTES)
  end

  # A text field (rich text from the editor, or plain text sent over the
  # API) as safe HTML.
  def website_rich_text(value)
    text = value.to_s.strip
    return "" if text.empty?
    return tag.p(text) unless text.start_with?("<")

    sanitize(text, tags: Markdown::TAGS, attributes: Markdown::ATTRIBUTES)
  end

  # A text field as one line of plain text.
  def website_plain_text(value)
    Nokogiri::HTML5.fragment(value.to_s.gsub(%r{</p>\s*<p>}, " ")).text.squish
  end

  # The <head> a record's SEO panel describes: title, description,
  # canonical, robots, Open Graph, Twitter and its JSON-LD. The keywords
  # fill what the panel leaves blank.
  def website_seo_tags(record = nil, title: nil, description: nil, image: nil, noindex: false)
    seo = record.respond_to?(:seo) ? record.seo.to_h.stringify_keys : {}
    title = seo["meta_title"].presence || title || record&.title
    description = seo["meta_description"].presence || description
    canonical = seo["canonical_url"].presence || website_url(request.path)
    image = website_image(seo["og_image_id"].presence || image)
    robots = "noindex, nofollow" if noindex || seo["noindex"]

    safe_join([
      tag.title(title),
      (tag.meta(name: "description", content: description) if description.present?),
      tag.link(rel: "canonical", href: canonical),
      (tag.meta(name: "robots", content: robots) if robots),
      tag.meta(property: "og:type", content: "website"),
      tag.meta(property: "og:site_name", content: website_settings["title"]),
      tag.meta(property: "og:title", content: title),
      (tag.meta(property: "og:description", content: description) if description.present?),
      tag.meta(property: "og:url", content: canonical),
      (tag.meta(property: "og:image", content: website_url(image[:src])) if image),
      tag.meta(name: "twitter:card", content: image ? "summary_large_image" : "summary"),
      (website_json_ld(seo["json_ld"]) if seo["json_ld"].present?)
    ].compact, "\n")
  end

  def website_json_ld(data)
    data = JSON.parse(data) if data.is_a?(String)
    tag.script(ERB::Util.json_escape(data.to_json).html_safe, type: "application/ld+json")
  rescue JSON::ParserError
    nil
  end

  # An address on the website, absolute: Settings › General's site URL, or
  # the request's own origin.
  def website_url(path)
    return path if path.to_s.start_with?("http://", "https://")

    "#{website_settings["site_base_url"].presence&.chomp("/") || request.base_url}#{path}"
  end

  # The theme's own importmap and its entry point: none of the admin's.
  def website_javascript_tags(entry_point = Website.theme.key)
    javascript_importmap_tags(entry_point, importmap: Website.theme.importmap)
  end

  # A form's field, by name, held to the form's definition: a theme that
  # draws a form by hand names its fields through this, so one the form
  # doesn't declare (the CMS would drop what it posts) fails in its spec.
  def website_form_field(form, name)
    form.fields.find { it["name"] == name.to_s } ||
      raise(Website::Fields::Unknown.new("form #{form.slug} has no field #{name.to_s.inspect} (it has #{form.fields.map { it["name"] }.to_sentence})", name))
  end

  def previewing? = controller.respond_to?(:previewing?, true) && controller.send(:previewing?)

  private

  def website_block_types = @website_block_types ||= BlockType.all.index_by(&:slug)

  def website_image_attributes(asset)
    position = "#{(asset.focal_x * 100).round}% #{(asset.focal_y * 100).round}%" if asset.focal_x && asset.focal_y
    original = {src: rails_storage_proxy_path(asset.file), width: asset.width, height: asset.height, alt: asset.alt.to_s, position:}
    return original unless asset.variantable? && ApplicationHelper.variants_supported? && asset.width && asset.height

    widths = WEBSITE_IMAGE_WIDTHS.select { it < asset.width }
    widths = [asset.width] if widths.empty?
    urls = widths.map { [it, rails_storage_proxy_path(asset.file.variant(resize_to_limit: [it, nil]))] }
    width = widths.last
    original.merge(src: urls.last.last, srcset: urls.map { |w, url| "#{url} #{w}w" }.join(", "),
      width:, height: (asset.height * width.fdiv(asset.width)).round)
  end
end
