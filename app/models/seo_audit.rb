# frozen_string_literal: true

# What stands between a page or entry and search: a missing or poorly sized
# title or description, the same title or description as another page, and
# links to pages that don't exist. Its SEO tab shows them.
#
#   SeoAudit.new.for_record(page)    # this record's issues
class SeoAudit
  Issue = Data.define(:severity, :message, :record) do
    def problem? = severity == :problem
  end

  TITLE_MAX = 60
  DESCRIPTION_RANGE = (50..160)
  HREF = /href=["']([^"']+)["']|\]\((\/[^)\s]*)\)/

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

    site = Site.configured_base_url.chomp("/")
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
end
