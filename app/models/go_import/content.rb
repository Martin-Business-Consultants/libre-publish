# frozen_string_literal: true

# The copied content brought onto this core's terms, in the new database:
#
# - **Rich text.** The Go core's `richtext` fields become `text` fields
#   (this core's rich text, edited with the admin's editor, stored as HTML),
#   wherever fields are defined (block types, collections, pages, globals,
#   nested in repeaters and groups); and every value that is a Go rich text
#   document (pages' and entries' blocks and fields, globals, versions,
#   patterns, defaults) becomes its HTML (GoImport::RichText).
# - **File addresses.** The Go core serves an upload at
#   /files/<key>/<name> (and /files/<key>/w640/<name> for a rendition), on
#   its own host. Each one in the content points at the same file as this
#   core serves it (Active Storage's blob address, on this install's host when
#   the old one was absolute); a rendition becomes the original.
# - **Roles.** The Go core's system role is "Administrator", this core's
#   "Admin"; capabilities this install doesn't know (a Go plugin's) go, and
#   are named.
class GoImport::Content
  DEFINITIONS = {"block_types" => "fields", "collections" => "schema", "pages" => "schema", "globals" => "schema"}.freeze
  VALUES = {
    "pages" => %w[blocks frontmatter seo], "page_versions" => %w[blocks],
    "collection_entries" => %w[blocks frontmatter seo body_markdown], "collection_entry_versions" => %w[blocks frontmatter body_markdown],
    "globals" => %w[data], "global_versions" => %w[data], "block_types" => %w[defaults], "block_patterns" => %w[blocks]
  }.freeze
  FILE_URL = %r{(https?://[^\s/"'<>()]+)?/files/([a-z0-9]{4,128})(/w\d+)?/([^\s"'<>()?#]+)}

  def initialize(db, report:, tables:)
    @db = db
    @report = report
    @tables = tables
    columns = db.execute("SELECT name FROM pragma_table_info('active_storage_blobs')").flatten
    @blobs = db.execute("SELECT * FROM active_storage_blobs").to_h { |row| columns.zip(row).to_h.then { [it["key"], it] } }
  end

  def convert
    DEFINITIONS.each { |table, column| rewrite(table, column) { definitions(it) } }
    VALUES.each { |table, columns| columns.each { |column| rewrite(table, column) { values(it) } } }
    roles
  end

  private

  def rewrite(table, column)
    return unless @tables.include?(table) && @db.execute("SELECT 1 FROM pragma_table_info(?) WHERE name = ?", [table, column]).any?

    @db.execute("SELECT id, #{column} FROM #{table} WHERE #{column} IS NOT NULL").each do |id, raw|
      value = json?(column, raw) ? JSON.parse(raw) : raw
      changed = yield(value)
      next if changed == value

      @db.execute("UPDATE #{table} SET #{column} = ? WHERE id = ?", [changed.is_a?(String) ? changed : JSON.generate(changed), id])
    end
  end

  # Every column here is JSON but an entry's body, which is Markdown.
  def json?(column, raw) = column != "body_markdown" && raw.is_a?(String) && raw.start_with?("{", "[")

  def definitions(value)
    case value
    when Array then value.map { definitions(it) }
    when Hash
      value.to_h do |key, item|
        if key == "type" && item == "richtext"
          @report.content[:rich_text_fields] += 1
          [key, "text"]
        else
          [key, definitions(item)]
        end
      end
    else value
    end
  end

  def values(value)
    case value
    when Array then value.map { values(it) }
    when Hash
      if GoImport::RichText.doc?(value)
        @report.content[:rich_text_values] += 1
        rich_text = GoImport::RichText.new(value)
        rich_text.to_html.then { file_urls(it) }.tap do
          rich_text.dropped.uniq.each { @report.not_carry("rich text: a #{it}, which the Go editor doesn't make (its words are kept)") }
        end
      else
        value.transform_values { values(it) }
      end
    when String then file_urls(value)
    else value
    end
  end

  def file_urls(text)
    return text unless text.include?("/files/")

    text.gsub(FILE_URL) do |match|
      host, key, rendition = $1, $2, $3
      blob = @blobs[key]
      next match unless blob

      @report.content[:file_addresses] += 1
      @report.content[:renditions_made_originals] += 1 if rendition
      blob_url(blob, absolute: host.present?)
    end
  end

  def blob_url(blob, absolute:)
    record = ActiveStorage::Blob.instantiate(blob)
    helpers = Rails.application.routes.url_helpers
    absolute ? helpers.rails_blob_url(record, **Site.url_options) : helpers.rails_blob_path(record, only_path: true)
  end

  def roles
    taken = @db.execute("SELECT name FROM roles").flatten
    @db.execute("SELECT id, name, permissions, system FROM roles").each do |id, name, raw, system|
      permissions = Array(JSON.parse(raw.presence || "[]"))
      known, unknown = permissions.partition { Permissions.known?(it) }
      unknown.each { @report.not_carry("role #{name}: #{it} (no such capability here)") }
      renamed = (system.to_i == 1 && known.include?(Permissions::WILDCARD) && name != "Admin" && taken.exclude?("Admin")) ? "Admin" : name
      @db.execute("UPDATE roles SET name = ?, permissions = ? WHERE id = ?", [renamed, JSON.generate(known), id])
      taken << renamed
    end
  end
end
