# frozen_string_literal: true

# What a theme draws the website with: the CMS's content as fields held to
# their schemas (Website::Fields), links and images as the browser needs
# them, text made safe, and the <head> a page's SEO panel describes. Every
# read is of live content, so a theme never shows a draft unless the page is
# an editor's preview.
module WebsiteHelper
  # The widths an image is offered at (srcset). The browser picks by `sizes`:
  # the small ones are for thumbnails and narrow columns on a phone (8rem at
  # 2x is 256 pixels), which would otherwise take the 480.
  WEBSITE_IMAGE_WIDTHS = [240, 320, 480, 640, 800, 1200, 1600, 2400].freeze

  # A page's (or an entry's) blocks, each drawn by the theme's
  # website/blocks/_<type> partial with its fields as `data` (and what the
  # CMS resolved for it, a collection list's entries say, as data.resolved).
  # A type the theme has no partial for is left out.
  def website_blocks(record)
    if website_inline_edit && record.respond_to?(:blocks) && record.respond_to?(:expanded_blocks)
      # Each of the page's own blocks keeps its place in the form, so its
      # text can be edited where it's drawn; a synced pattern's can't.
      return safe_join(Array(record.blocks).each_with_index.flat_map do |raw, row|
        expanded = Page::BlockExpansion.new([raw], live: false).blocks
        expanded.filter_map { website_block(it, row: (raw.is_a?(Hash) && raw["type"] != "pattern") ? row : nil) }
      end)
    end

    blocks = record.respond_to?(:expanded_blocks) ? record.expanded_blocks(live: !previewing?) : Array(record.try(:blocks))
    safe_join(blocks.filter_map { website_block(it) })
  end

  # The editor's preview's markers (Website::InlineEdit), when it's drawing one.
  def website_inline_edit = controller.instance_variable_get(:@website_inline_edit)

  def website_block(block, row: nil)
    type = block["type"].to_s
    partial = "website/blocks/#{type}"
    unless lookup_context.exists?(partial, [], true)
      logger.warn("[website] the theme has no partial for #{type.inspect} blocks")
      return
    end

    @website_block_row = row
    html = render partial, data: Website::Fields.new(block["data"], website_block_types[type]&.fields, name: type, resolved: block["resolved"],
      inline_edit: website_inline_edit, row: row)
    @website_block_row = nil
    website_html Cms::Hooks.apply("website.block", html, block: block)
  end

  # What editors paste into the "scripts" global (analytics, a chat widget),
  # for the <head> (part: "head") or the end of <body> ("body"): trusted as
  # written, since only someone who can edit globals can put it there.
  # Plugins add theirs after (the website.head and website.body filters).
  # Read as stored, not through Website::Fields: an item may carry
  # "enabled": false (switched off over the API) though the global's fields
  # don't declare it, and Fields raises for a field it doesn't know, which
  # took every page down once a script was added.
  def website_scripts(part)
    items = Array(Global.find_by(slug: "scripts")&.data.to_h["items"]).grep(Hash)
    # A script saved as formatted text (Global::ScriptCode) runs as the code it was: put back before
    # any plugin sees it, so a consent plugin holds it like the rest.
    items = items.map { |item| item.merge(part => Global::ScriptCode.restore(item[part])) }
    # A plugin may rework them first (the website.scripts filter: a consent
    # plugin holds some back until a visitor agrees); a list of the same hashes.
    items = Array(Cms::Hooks.apply("website.scripts", items, part: part, request: request)).grep(Hash)
    pasted = items.filter_map { it[part].to_s.html_safe if it["enabled"] != false && it[part].present? } # rubocop:disable Rails/OutputSafety
    added = website_html Cms::Hooks.apply("website.#{part}", ActiveSupport::SafeBuffer.new, request: request)
    safe_join([*pasted, (added if added.present?)].compact, "\n")
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
  # Nothing for an address that would run script (SafeUrl), whatever got it
  # stored.
  def website_href(link)
    link = link.to_h.stringify_keys
    value = link["value"].to_s
    return if value.empty?

    case link["kind"]
    when "page" then Page.find_by(path: value)&.public_path || (value == "home" ? "/" : "/#{value}")
    when "entry" then "/#{link["collection"]}/#{value}"
    else value if SafeUrl.safe?(value)
    end
  end

  # Settings › General: the business's name, description and contact details.
  def website_settings = @website_settings ||= Setting.get("general").to_h

  # An asset (by id) as an <img>: a srcset of resized copies, its own width
  # and height so the page doesn't shift as it loads, its alt text (or
  # `alt:`; "" for a decorative image) and its focal point as the crop.
  # Nothing for a missing or deleted asset.
  # In the editor's preview, one of the block's image fields says which
  # (data-lp-image, Website::InlineEdit#image), for Replace and Edit.
  def website_image_tag(id, sizes: "100vw", alt: nil, loading: :lazy, fetchpriority: nil, position: nil, **options)
    image = website_image(id) or return
    if (field = @website_block_row && website_inline_edit&.image_field(@website_block_row, id))
      options[:data] = (options[:data] || {}).merge(lp_image: field)
    end
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
    website_html Cms::Hooks.apply("website.markdown", sanitize(html, tags: Markdown::TAGS, attributes: Markdown::ATTRIBUTES), text: text)
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

  # The <head> a record's SEO panel describes, complete: title,
  # description, canonical, robots, Open Graph (its overrides, the image's
  # size and alt, an entry's dates), Twitter, the record's translations
  # (hreflang), its Markdown for AI readers, and its structured data — the
  # panel's JSON-LD, or one made from the content (website_structured_data).
  # The keywords fill what the panel leaves blank.
  def website_seo_tags(record = nil, title: nil, description: nil, image: nil, noindex: false)
    seo = record.respond_to?(:seo) ? record.seo.to_h.stringify_keys : {}
    values = Cms::Hooks.apply("website.seo", {
      title: seo["meta_title"].presence || title || record&.title,
      description: seo["meta_description"].presence || description,
      canonical: seo["canonical_url"].presence || website_url(request.path),
      image: seo["og_image_id"].presence || image,
      # Asked for (a 404), neither indexed nor followed; hidden in the SEO
      # panel, not indexed but its links still followed, unless it says so.
      robots: website_robots(noindex: noindex || website_truthy?(seo["noindex"]), nofollow: noindex || website_truthy?(seo["nofollow"]))
    }, record: record)
    title, description, canonical, robots = values.values_at(:title, :description, :canonical, :robots)
    image = website_image(values[:image])
    og_title = seo["og_title"].presence || title
    og_description = seo["og_description"].presence || description
    article = record.is_a?(CollectionEntry)

    safe_join([
      tag.title(title),
      (tag.meta(name: "description", content: description) if description.present?),
      tag.link(rel: "canonical", href: canonical),
      tag.meta(name: "robots", content: robots),
      *website_hreflang_tags(record),
      (tag.link(rel: "alternate", type: "text/markdown", href: website_url(website_markdown_path(record))) if record.respond_to?(:public_path) && !robots.include?("noindex")),
      *website_feed_tags,
      tag.meta(property: "og:type", content: seo["og_type"].presence || (article ? "article" : "website")),
      tag.meta(property: "og:site_name", content: website_settings["title"]),
      tag.meta(property: "og:title", content: og_title),
      (tag.meta(property: "og:description", content: og_description) if og_description.present?),
      tag.meta(property: "og:url", content: canonical),
      (tag.meta(property: "og:locale", content: record.locale.to_s.tr("-", "_")) if record.respond_to?(:locale) && record.locale.present?),
      *(image ? [tag.meta(property: "og:image", content: website_url(image[:src])),
        (tag.meta(property: "og:image:width", content: image[:width]) if image[:width]),
        (tag.meta(property: "og:image:height", content: image[:height]) if image[:height]),
        (tag.meta(property: "og:image:alt", content: image[:alt]) if image[:alt].present?)] : []),
      *(article ? [(tag.meta(property: "article:published_time", content: record.published_at.iso8601) if record.published_at),
        tag.meta(property: "article:modified_time", content: record.updated_at.iso8601)] : []),
      tag.meta(name: "twitter:card", content: seo["twitter_card"].presence || (image ? "summary_large_image" : "summary")),
      tag.meta(name: "twitter:title", content: og_title),
      (tag.meta(name: "twitter:description", content: og_description) if og_description.present?),
      (website_json_ld(seo["json_ld"]) if seo["json_ld"].present?),
      website_json_ld(website_structured_data(record, title: og_title, description: og_description, canonical: canonical, image: image,
        custom: seo["json_ld"].present?))
    ].flatten.compact, "\n")
  end

  # The robots meta: an indexable page also lets search show a large image
  # preview and the full snippet (what Google Discover and AI overviews use).
  def website_robots(noindex:, nofollow:)
    return [noindex ? "noindex" : "index", nofollow ? "nofollow" : "follow"].join(", ") if noindex

    [nofollow ? "index, nofollow" : "index, follow", "max-image-preview:large", "max-snippet:-1"].join(", ")
  end

  # The record's translations, and itself, as hreflang links, with the
  # default locale's as x-default.
  def website_hreflang_tags(record)
    group = record.try(:translation_group) or return []
    members = group.members.select { it.try(:status) == "published" || it == record }
    return [] if members.size < 2

    default = members.find { it.locale.to_s == record.class.default_locale.to_s }
    members.map { tag.link(rel: "alternate", hreflang: it.locale, href: website_url(it.public_path)) } +
      [(tag.link(rel: "alternate", hreflang: "x-default", href: website_url(default.public_path)) if default)]
  end

  def website_markdown_path(record)
    path = record.public_path
    (path == "/") ? "/index.md" : "#{path}.md"
  end

  # Structured data made from the content (schema.org, one @graph): the
  # organization behind the site (Settings › General and Search), the site,
  # this page — as the SEO panel's schema.org type, an Article for an entry,
  # or a WebPage — and its breadcrumbs. With the panel's own JSON-LD, only the
  # organization, the site and the breadcrumbs, beside it.
  def website_structured_data(record, title:, description:, canonical:, image:, custom: false)
    general = website_settings
    search = SearchSettings.get
    home = website_url("/")
    organization = {
      "@type" => search["organization"], "@id" => "#{home}#organization",
      "name" => general["title"].presence, "url" => home, "description" => general["description"].presence,
      "email" => general["email"].presence, "telephone" => general["phone"].presence,
      "logo" => website_logo_url, "sameAs" => search["same_as"].presence
    }
    if search["organization"] == "LocalBusiness" && general["address_line1"].present?
      organization["address"] = {"@type" => "PostalAddress", "streetAddress" => general["address_line1"],
        "addressLocality" => general["city"].presence, "addressRegion" => general["state"].presence, "postalCode" => general["zip"].presence}.compact
    end
    site = {"@type" => "WebSite", "@id" => "#{home}#website", "url" => home, "name" => general["title"].presence,
            "publisher" => {"@id" => "#{home}#organization"}, "inLanguage" => record.try(:locale).presence}
    graph = [organization.compact, site.compact]
    return {"@context" => "https://schema.org", "@graph" => graph} unless record

    unless custom
      type = record.seo.to_h["schema_type"].presence || (record.is_a?(CollectionEntry) ? "Article" : "WebPage")
      node = {"@type" => type, "@id" => "#{canonical}#main", "url" => canonical, "name" => title, "description" => description.presence,
              "isPartOf" => {"@id" => "#{home}#website"}, "inLanguage" => record.try(:locale).presence,
              "image" => (website_url(image[:src]) if image), "dateModified" => record.updated_at&.iso8601,
              "datePublished" => record.try(:published_at)&.iso8601}
      if type.in?(%w[Article BlogPosting NewsArticle])
        node.merge!("headline" => (record.try(:title).presence || title).to_s.truncate(110), "author" => {"@id" => "#{home}#organization"},
          "publisher" => {"@id" => "#{home}#organization"}, "mainEntityOfPage" => canonical)
      end
      node["breadcrumb"] = {"@id" => "#{canonical}#breadcrumb"}
      graph << node.compact
    end
    crumbs = website_breadcrumbs(record)
    graph << {"@type" => "BreadcrumbList", "@id" => "#{canonical}#breadcrumb", "itemListElement" =>
      crumbs.each_with_index.map { |(name, path), index| {"@type" => "ListItem", "position" => index + 1, "name" => name, "item" => website_url(path)} }}
    {"@context" => "https://schema.org", "@graph" => graph}
  end

  # Home, then a page's parents (or an entry's collection), then the record.
  def website_breadcrumbs(record)
    trail = [["Home", "/"]]
    case record
    when Page
      # Only what visitors can open: a draft parent's title stays private
      # (except in an editor's preview, which shows drafts anyway).
      record.ancestors.each { trail << [it.title, it.public_path] if website_visible?(it) } if record.respond_to?(:ancestors)
    when CollectionEntry
      listing = Page.find_by(path: record.collection.slug)
      trail << [listing.title, listing.public_path] if listing && website_visible?(listing)
    end
    trail << [record.title, record.public_path] unless record.public_path == "/"
    trail
  end

  def website_visible?(record) = record.try(:status) == "published" || previewing?

  def website_logo_url
    logo = Setting.get("branding")["logo_id"].presence
    MediaLibrary.find(logo).try(:absolute_url) if logo
  end

  def website_truthy?(value) = value == true || value.to_s.in?(%w[true 1])

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

    "#{Site.public_base_url || request.base_url}#{path}"
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

  # A design setting's value (Website::Design): what an editor chose in
  # Settings › Themes › Customize, or the theme's default.
  def website_design(name) = Website::Design.value(name)

  # The design settings as CSS custom properties (--design-accent), for the
  # theme's layout to put in its <head>.
  def website_design_tags
    css = Website::Design.css
    tag.style(css.html_safe) if css.present? # rubocop:disable Rails/OutputSafety -- values are held to their type and stripped of ;{}<>
  end

  def previewing? = controller.respond_to?(:previewing?, true) && controller.send(:previewing?)

  private

  # What a filter returned, as HTML: escaped unless it's marked safe (a tag
  # helper's, safe_join's), as ERB would.
  def website_html(value) = value.to_s.html_safe? ? value : ERB::Util.html_escape(value.to_s)

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
