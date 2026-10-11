# frozen_string_literal: true

# The admin bar's search box (the ⌘K modal, searches/_quick): what a person
# is after, as they type. Titles match fuzzily, from the first letter: the
# term's letters in order, not necessarily together ("hmpg" finds "Home
# page"), best first (the term whole, letters that run together or start a
# word, shorter titles). Under them, for a term long enough for the index,
# records whose text holds it (GlobalSearch), with where. Only the kinds the
# person's role can read; Search's own screen has the rest.
#
#   GlobalSearch::Quick.new("hmpg", user: Current.user).titles
class GlobalSearch::Quick
  LIMIT = 8
  # Titles scored per search: plenty for an admin's records.
  CANDIDATES = 10_000

  # marks: the title's character positions the term matched.
  Result = Data.define(:record, :title, :marks, :snippet) do
    def kind = GlobalSearch.kind_label(record)
  end

  attr_reader :term

  def initialize(term, user:)
    @term = term.to_s.strip
    @user = user
  end

  def blank? = term.empty?

  # [score, marks] when every letter of term is in text, in order; else nil.
  def self.match(term, text)
    needle = term.downcase.delete(" ")
    haystack = text.downcase
    return if needle.empty? || haystack.length != text.length

    if (start = haystack.index(needle))
      word_start = start.zero? || haystack[start - 1].match?(/[^[:alnum:]]/)
      return [100 + (word_start ? 20 : 0) + (start.zero? ? 10 : 0) - haystack.length * 0.01, (start...start + needle.length).to_a]
    end

    marks = []
    score = 0
    needle.each_char do |char|
      at = haystack.index(char, marks.empty? ? 0 : marks.last + 1) or return
      score += 1
      score += 3 if marks.any? && at == marks.last + 1
      score += 2 if at.zero? || haystack[at - 1].match?(/[^[:alnum:]]/)
      marks << at
    end
    [score - haystack.length * 0.01, marks]
  end

  def titles
    @titles ||= blank? ? [] : best_titles
  end

  # Records whose text holds the term and whose title didn't already match.
  def texts
    @texts ||= begin
      search = GlobalSearch.new(term, user: @user)
      shown = titles.map { [it.record.class.name, it.record.id] }
      search.limit(LIMIT * 2)
        .reject { shown.include?([it.class.name, it.id]) }
        .first(LIMIT)
        .map { Result.new(record: it, title: it.search_document[:title].presence || "Untitled", marks: [], snippet: it.hit.highlight(:body)) }
    end
  end

  def any? = titles.any? || texts.any?

  private

  def kinds = GlobalSearch::KINDS.select { |_, (capability, _)| @user&.can?(capability) }.keys

  def best_titles
    return [] if kinds.empty?

    scored = candidates.filter_map do |type, id, title|
      score, marks = self.class.match(term, title.to_s)
      [score, type, id.to_i, title, marks] if score
    end
    best = scored.max_by(LIMIT) { it.first }
    records = load(best.map { [it[1], it[2]] })
    best.filter_map do |_, type, id, title, marks|
      record = records[[type, id]]
      Result.new(record:, title:, marks:, snippet: nil) if record
    end
  end

  def candidates
    ActiveRecord::Base.connection.select_rows(ActiveRecord::Base.sanitize_sql_array([<<~SQL, kinds, CANDIDATES]))
      SELECT d.record_type, d.record_id, f.title FROM record_documents d
      JOIN record_documents_fts f ON f.rowid = d.rowid
      WHERE d.record_type IN (?) LIMIT ?
    SQL
  end

  def load(keys)
    keys.group_by(&:first).flat_map { |type, pairs|
      scope = type.constantize.where(id: pairs.map(&:last))
      scope = scope.includes(:collection) if type == "CollectionEntry"
      scope.map { [[type, it.id], it] }
    }.to_h
  end
end
