# frozen_string_literal: true

# What a Go core import found and did, for the person running it: the
# records it carries, the files (whole, missing or damaged), the secrets
# (carried or cleared), the content brought onto this core's terms, the
# forms, and what doesn't round-trip. A dry run prints the same report.
class GoImport::Report
  attr_reader :source, :manifest, :tables, :files, :secrets, :content, :forms, :skipped, :not_carried, :warnings
  attr_accessor :target_users, :owners, :kept, :plugin_data, :dry_run

  def initialize(source:, manifest:)
    @source = source
    @manifest = manifest || {}
    @tables = {}
    @files = Hash.new(0)
    @secrets = {total: 0, carried: 0, cleared: Hash.new(0)}
    @content = Hash.new(0)
    @forms = Hash.new(0)
    @skipped = {}
    @not_carried = []
    @warnings = []
    @owners = []
  end

  def warn(message) = @warnings << message

  def not_carry(message) = @not_carried << message

  def count_table(table, source:, carried:)
    @tables[table] = {source:, carried:}
  end

  def to_h
    {source:, manifest:, tables:, files: files.to_h, secrets: secrets.merge(cleared: secrets[:cleared].to_h), content: content.to_h,
     forms: forms.to_h, skipped:, owners:, target_users:, not_carried:, warnings:, kept: kept&.to_s, plugin_data: plugin_data&.to_s}
  end

  def lines
    out = ["Importing the Go core backup #{source}#{" (dry run)" if dry_run}"]
    out << "  made by Libre Publish #{manifest["cms_version"] || "?"} at #{manifest["generated_at"] || "?"} (schema #{manifest["schema_version"] || "?"})"
    out << "  records: #{tables.select { |_, n| n[:carried].positive? }.map { |table, n| "#{table} #{n[:carried]}" }.join(", ")}"
    out << "  files: #{tally(files)}"
    out << "  secrets: #{secrets_line}"
    out << "  content: #{tally(content)}" if content.any?
    out << "  forms: #{tally(forms)}" if forms.any?
    out << "  left behind: #{skipped.map { |table, n| "#{table} #{n}" }.join(", ")}" if skipped.any?
    out << "  owners: #{owners.join(", ").presence || "none"}"
    out << "  this install has #{target_users} user(s) now: importing replaces them and everything else" if target_users.to_i.positive?
    out.concat(not_carried.uniq.map { "  - not carried: #{it}" })
    out.concat(warnings.uniq.map { "  ! #{it}" })
  end

  private

  def tally(counts) = counts.map { |what, n| "#{n} #{what.to_s.tr("_", " ")}" }.join(", ").presence || "none"

  def secrets_line
    cleared = secrets[:cleared].map { |where, n| "#{where} × #{n}" }.join(", ")
    "#{secrets[:total]} sealed, #{secrets[:carried]} carried#{", cleared: #{cleared}" if cleared.present?}"
  end
end
