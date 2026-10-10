# frozen_string_literal: true

# Tools › Search and replace: a word or phrase found across the site's
# content — pages, entries and globals: their titles, their blocks' fields,
# their own fields, an entry's body, the SEO panel — and, when asked,
# replaced everywhere at once. Only text is touched: a block's type, id and
# version, slugs and addresses stay as they are. Each changed record is
# saved as an edit would be (its validations, its version history, the audit
# log), and one that won't save is reported and left alone.
#
#   search = SearchReplace.new("Acme Ltd", "Acme Inc.", case_sensitive: true)
#   search.matches        # [Match(record, count), …]
#   search.replace!       # {replaced: 12, records: 4, failed: [[record, message]]}
class SearchReplace
  Match = Data.define(:record, :count)

  # What's searched, per kind of record: its text columns and its JSON ones.
  FIELDS = {
    Page => {text: %w[title], json: %w[blocks frontmatter seo]},
    CollectionEntry => {text: %w[title body_markdown], json: %w[blocks frontmatter seo]},
    Global => {text: [], json: %w[data]}
  }.freeze
  # A block's own keys, never rewritten.
  KEPT_KEYS = %w[id type version].freeze
  MIN_LENGTH = 2

  attr_reader :term, :replacement

  def initialize(term, replacement = "", case_sensitive: false)
    @term = term.to_s
    @replacement = replacement.to_s
    @case_sensitive = case_sensitive
  end

  def valid? = term.strip.length >= MIN_LENGTH

  def matches
    return [] unless valid?

    FIELDS.keys.flat_map do |model|
      model.find_each.filter_map do |record|
        count = count_in(record)
        Match.new(record:, count:) if count.positive?
      end
    end
  end

  def replace!
    result = {replaced: 0, records: 0, failed: []}
    matches.each do |match|
      record = match.record
      status = record.try(:status)
      fields = FIELDS.fetch(record.class)
      fields[:text].each { |column| record[column] = replace_in(record[column]) }
      fields[:json].each { |column| record[column] = deep_replace(record[column]) }
      if record.save
        record.is_a?(Global) ? record.track_update : record.track_update(from: status)
        result[:replaced] += match.count
        result[:records] += 1
      else
        result[:failed] << [record, record.errors.full_messages.to_sentence]
      end
    end
    Event.record("content.replaced", term: term, replacement: replacement, count: result[:replaced], records: result[:records]) if result[:records].positive?
    result
  end

  private

  def pattern = @pattern ||= Regexp.new(Regexp.escape(term), @case_sensitive ? nil : Regexp::IGNORECASE)

  def count_in(record)
    fields = FIELDS.fetch(record.class)
    fields[:text].sum { record[it].to_s.scan(pattern).size } +
      fields[:json].sum { strings_in(record[it]).sum { it.scan(pattern).size } }
  end

  def strings_in(value)
    case value
    when String then [value]
    when Array then value.flat_map { strings_in(it) }
    when Hash then value.flat_map { |key, inner| KEPT_KEYS.include?(key.to_s) ? [] : strings_in(inner) }
    else []
    end
  end

  def deep_replace(value)
    case value
    when String then replace_in(value)
    when Array then value.map { deep_replace(it) }
    when Hash then value.to_h { |key, inner| [key, KEPT_KEYS.include?(key.to_s) ? inner : deep_replace(inner)] }
    else value
    end
  end

  def replace_in(text) = text.nil? ? text : text.gsub(pattern) { replacement }
end
