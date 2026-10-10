# frozen_string_literal: true

# URL redirect rule, applied at the edge by the public site (GET /api/redirects,
# /api/v1/redirects). How a request path finds its rule is
# Redirect::Matchable; moving rules in and out as CSV is Redirect::Portable.
class Redirect < ApplicationRecord
  include ListSearchable

  search_on :source_path, :destination_url, :notes
  include SearchIndexed

  # Its title and text in the admin's search (SearchIndexed).
  def search_document = {title: source_path, body: [destination_url, notes].compact.join("\n")}

  include Matchable, Portable
  include Eventable

  STATUS_CODES = [301, 302, 307, 308].freeze

  STATUS_LABELS = {
    301 => "Moved permanently",
    302 => "Found (temporary)",
    307 => "Temporary redirect",
    308 => "Permanent redirect"
  }.freeze

  validates :source_path,     presence: true, uniqueness: true
  validates :destination_url, presence: true
  validates :status_code,     inclusion: {in: STATUS_CODES}
  validate  :validate_wildcards

  scope :ordered, -> { order(updated_at: :desc) }
  scope :active,  -> { where(active: true) }
end
