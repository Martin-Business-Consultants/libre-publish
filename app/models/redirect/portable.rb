# frozen_string_literal: true

require "csv"

# Redirect rules in and out as CSV, one rule per row. The admin's Import/Export
# buttons and `cms redirects import|export` share the format, so what one
# exports the other accepts.
module Redirect::Portable
  extend ActiveSupport::Concern

  CSV_COLUMNS = %w[source_path destination_url status_code active notes].freeze

  class_methods do
    def to_csv
      CSV.generate do |csv|
        csv << CSV_COLUMNS
        ordered.each { |redirect| csv << redirect.to_csv_row }
      end
    end

    def csv_filename
      "redirects-#{Site.key}-#{Time.current.strftime("%Y%m%d")}.csv"
    end

    # Upserts by source path, so re-running an import is a no-op rather than a
    # pile of duplicates. Takes the CSV as a string or an IO, read a row at a
    # time. Raises CSV::MalformedCSVError on unparseable input.
    # Runs the import and records it (redirect.imported), from the admin or
    # the API alike.
    def import_csv(source)
      Redirect::Import.new(source).tap do |import|
        import.run
        track_event(:imported, created: import.created, updated: import.updated, errored: import.errored)
      end
    end
  end

  def to_csv_row
    [source_path, destination_url, status_code, active ? "true" : "false", notes]
  end
end
