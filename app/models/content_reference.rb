# frozen_string_literal: true

# Denormalized index of references that live inside Page blocks or
# CollectionEntry frontmatter / markdown. Maintained by `sync_references` on
# the owner side. Lets us answer "which pages use asset X?" without scanning
# JSON, and clean up when an asset/record is deleted.
class ContentReference < ApplicationRecord
  belongs_to :owner, polymorphic: true

  # The records that point at one thing, a page at a time: [reference, owner]
  # pairs, one per owner (a record that links twice is listed once), plus the
  # total number of owners.
  #
  # `owners` narrows them to what the caller may see: owner type => the
  # records of that type it may (`{"Page" => Page.live}`); a type left out
  # isn't listed, or counted.
  def self.owners_of(ref_type:, ref_id:, kind: nil, page: 1, per: 50, owners: nil)
    scope = where(ref_type: ref_type, ref_id: ref_id)
    scope = scope.where(kind: kind) if kind.present?
    scope = scope.owned_by(owners) if owners
    total = scope.distinct.count("(owner_type || ':' || owner_id)")

    refs = scope.order(created_at: :asc).offset((page - 1) * per).limit(per).includes(:owner)
    owned = refs.select(&:owner).uniq { |ref| [ref.owner.class.name, ref.owner.id] }
    [owned, total]
  end

  # The live entries and pages that records (pages, entries, globals) point
  # at through their fields and blocks, for the delivery API's
  # `?include=entries,pages`: [entries, pages], at most 500 references read.
  def self.live_referenced_by(records)
    records = Array(records)
    return [[], []] if records.empty?

    refs = records.group_by { it.class.base_class.name }.map { |type, owners| where(owner_type: type, owner_id: owners.map(&:id)) }.reduce(:or)
      .where(kind: %w[record page]).distinct.limit(500).pluck(:kind, :ref_type, :ref_id)
    pages = Page.live.where(path: refs.filter_map { |kind, _, id| id if kind == "page" }).order(:id).to_a
    entries = refs.select { |kind, _, _| kind == "record" }.group_by { it[1] }.flat_map { |collection, rows|
      CollectionEntry.live.joins(:collection).where(collections: {slug: collection}, slug: rows.map(&:last)).order(:id).to_a
    }
    [entries, pages]
  end

  def self.owned_by(owners)
    return none if owners.empty?

    owners.map { |type, records| where(owner_type: type, owner_id: records.select(:id)) }.reduce(:or)
  end
end
