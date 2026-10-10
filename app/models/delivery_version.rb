# frozen_string_literal: true

# A stamp that changes whenever anything the delivery API serializes from
# changes, for caching what it renders (GET /api/v1/content): every table a
# page, entry or global's JSON reads — the records (trashed ones too, so a
# trash or restore counts), their taxonomy and translation siblings, their
# collections, and Settings (the default locale shapes every URL, General's
# contact details fill contact_info blocks). Each table answers with its row
# count, its newest updated_at and the sum of them all, so an insert, an edit
# and a delete all move it — the sum even when the edited row's new time
# isn't the newest (a row imported with a later clock's timestamp).
#
# The media library's assets aren't in it, and needn't be: the API resolves
# them on every request (`included.assets`), never from this cache.
module DeliveryVersion
  module_function

  def current
    Digest::SHA256.hexdigest(stamps.to_json)
  end

  def stamps
    scopes.map { it.pick(Arel.sql("COUNT(*)"), Arel.sql("MAX(updated_at)"), Arel.sql("SUM(julianday(updated_at))")) }
  end

  def scopes
    [Page.with_discarded, CollectionEntry.with_discarded, Global.with_discarded, Collection.all, Tagging.all,
      TranslationGroup.all, Setting.all]
  end
end
