# frozen_string_literal: true

# The admin bar's search: one term across every kind of record in the search
# index (SearchIndexed) the person's role can read, best match first, each
# with a highlighted snippet of where it matched. The audit log is searched
# on its own screen, not here. Paged as a list is (Pagination): it answers
# count and offset/limit.
#
#   GlobalSearch.new("pricing", user: Current.user)
class GlobalSearch
  # Each kind of record it finds, the capability that reads it, and what to
  # call it.
  KINDS = {
    "Page" => ["pages:read", "Page"],
    "CollectionEntry" => ["entries:read", "Entry"],
    "Collection" => ["collections:read", "Collection"],
    "Global" => ["globals:read", "Global"],
    "BlockType" => ["block_types:read", "Block type"],
    "Redirect" => ["redirects:read", "Redirect"],
    "User" => ["users:read", "User"],
    "Role" => ["roles:read", "Role"]
  }.freeze
  SNIPPET = {body: {markers: ["<mark>", "</mark>"], snippet: {words: 16}}}.freeze

  attr_reader :term

  def self.kind_label(record) = KINDS.dig(record.class.name, 1) || record.class.model_name.human

  def initialize(term, user:, offset: 0)
    @term = term.to_s.strip
    @user = user
    @offset = offset
  end

  # Whether there's a term long enough to search for.
  def searchable? = term.length >= SearchIndexed::MIN_LENGTH && kinds.any?

  def count(*)
    @count ||= searchable? ? query.limit(1).results.total : 0
  end

  def offset(n) = self.class.new(term, user: @user, offset: n)

  def limit(n)
    return [] unless searchable?

    query.offset(@offset).limit(n).results.to_a
  end

  private

  def kinds = KINDS.select { |_, (capability, _)| @user&.can?(capability) }.keys

  def query = ActiveSearch.index(:records).search(term).filter(record_type: kinds).highlight(**SNIPPET)
end
