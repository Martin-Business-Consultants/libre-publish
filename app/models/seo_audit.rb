# frozen_string_literal: true

# What stands between the site and search: missing or poorly sized titles
# and descriptions, the same title or description on two pages, links to
# pages that don't exist, images without alt text, and the site-wide details
# search engines and AI tie everything to. Tools › SEO audit lists it all;
# a page's or entry's SEO tab shows its own (for_record).
#
#   SeoAudit.new.issues              # [Issue, …], problems first
#   SeoAudit.new.for_record(page)    # this record's issues
class SeoAudit
  Issue = Data.define(:severity, :message, :record) do
    def problem? = severity == :problem
  end

  SEVERITIES = %i[problem warning tip].freeze
  TITLE_MAX = 60
  DESCRIPTION_RANGE = (50..160)
  HREF = /href=["']([^"']+)["']|\]\((\/[^)\s]*)\)/

  def issues
    (site_issues + records.flat_map { record_issues(it) } + duplicate_issues + image_issues)
      .sort_by { SEVERITIES.index(it.severity) }
  end

  def for_record(record)
    return [] unless indexable?(record)

    record_issues(record) + duplicate_issues.select { it.record == record }
  end

  private

  # What search engines may show: published, not hidden from search.
  def records
    @records ||= (Page.live.to_a + CollectionEntry.live.includes(:collection).to_a).select { indexable?(it) }
  end

  def indexable?(record) = record.status == "published" && !ActiveModel::Type::Boolean.new.cast(record.seo.to_h["noindex"])

  def record_issues(record)
    seo = record.seo.to_h
    found = []
    description = seo["meta_description"].to_s.strip
    title = (seo["meta_title"].presence || record.title).to_s

    if description.empty?
      found << Issue.new(:problem, "No meta description: search and AI answers show whatever text they pick.", record)
    elsif !DESCRIPTION_RANGE.cover?(description.length)
      found << Issue.new(:warning, "The meta description is #{description.length} characters; #{DESCRIPTION_RANGE.min}–#{DESCRIPTION_RANGE.max} reads best in results.", record)
    end
    found << Issue.new(:warning, "The title is #{title.length} characters; past #{TITLE_MAX} it's cut off in results.", record) if title.length > TITLE_MAX
    broken_links(record).each { found << Issue.new(:problem, "Links to #{it}, which isn't a page on the site.", record) }
    found
  end

  def duplicate_issues
    @duplicate_issues ||= begin
      titles = records.group_by { (it.seo.to_h["meta_title"].presence || it.title).to_s.strip.downcase }
      descriptions = records.group_by { it.seo.to_h["meta_description"].to_s.strip.downcase }.except("")
      titles.values.select { it.size > 1 }.flat_map { |same| same.map { Issue.new(:warning, "Shares its title with #{(same - [it]).map(&:title).to_sentence}.", it) } } +
        descriptions.values.select { it.size > 1 }.flat_map { |same| same.map { Issue.new(:warning, "Shares its meta description with #{(same - [it]).map(&:title).to_sentence}.", it) } }
    end
  end

  # Internal links (/path, or the site's own address) in its text that lead
  # nowhere: no page, entry or redirect at that address.
  def broken_links(record)
    return [] unless Website.enabled?

    site = Setting.get("general")["site_base_url"].to_s.chomp("/")
    text_of(record).scan(HREF).flatten.compact.filter_map do |href|
      href = href.delete_prefix(site) if site.present?
      next unless href.start_with?("/") && !href.start_with?("//", "/rails/", "/#{Cms::PATH}/", "/api/")

      path = href.split(/[?#]/).first.chomp("/").presence || "/"
      next if path.end_with?(".md", ".xml", ".txt") || path.match?(/\.\w{2,4}\z/)

      path if Website::Address.new(path).record.nil? && Redirect.match(path).nil?
    end.uniq
  end

  def text_of(record)
    strings = ->(value) {
      case value
      when String then [value]
      when Array then value.flat_map { strings.(it) }
      when Hash then value.values.flat_map { strings.(it) }
      else []
      end
    }
    (strings.(record.blocks) + [record.try(:body_markdown).to_s]).join("\n")
  end

  def image_issues
    missing = Array(Array(MediaLibrary.images_without_alt).last).size
    missing.positive? ? [Issue.new(:warning, "#{missing} #{"image".pluralize(missing)} in the media library #{(missing == 1) ? "has" : "have"} no alt text, which search and screen readers read.", nil)] : []
  end

  def site_issues
    general = Setting.get("general")
    found = []
    found << Issue.new(:problem, "Settings › General has no site URL: canonical addresses, the sitemap and structured data fall back to the address the CMS is visited at.", nil) if general["site_base_url"].blank?
    found << Issue.new(:warning, "Settings › General has no description of the business, which llms.txt and the structured data lead with.", nil) if general["description"].blank?
    found << Issue.new(:tip, "Settings › Branding has no logo for search engines to show beside the business.", nil) if Setting.get("branding")["logo_id"].blank?
    found << Issue.new(:tip, "Settings › Search lists no profiles elsewhere (LinkedIn, Instagram, Google Business…) to tie to the business.", nil) if SearchSettings.get["same_as"].empty?
    found << Issue.new(:warning, "Settings › Search keeps AI answer engines out, so ChatGPT search, Perplexity and Claude won't cite the site.", nil) unless SearchSettings.ai_search?
    found
  end
end
