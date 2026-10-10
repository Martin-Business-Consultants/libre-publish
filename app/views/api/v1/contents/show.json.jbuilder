# frozen_string_literal: true

# Every live page, entry and global, or what changed since `since`
# (ContentSnapshot). With `full: true`, replace what you have; otherwise
# apply `data` and drop `removed`. Read again with ?since=<meta.cursor>.
#
# `data` is cached while nothing it's built from changes (DeliveryVersion):
# expanding blocks and finding translations is most of a build's read.
# `included.assets` is resolved fresh every time.
json.data do
  # Keyed on what the token reads too: a pages-only token's answer carries no
  # entries or globals, and must not be served one that does.
  json.cache! ["api/v1/content", @version, @snapshot.since&.utc&.iso8601(6), @snapshot.full?, @readable] do
    json.pages @pages, partial: "api/v1/pages/page", as: :page
    json.entries @entries, partial: "api/v1/entries/entry", as: :entry
    json.globals @globals, partial: "api/v1/globals/global", as: :global
    json.removed @removed
  end
end
json.meta({cursor: @snapshot.cursor, full: @snapshot.full?, since: @snapshot.since&.utc&.iso8601(6)})
json.partial! "api/v1/shared/included", assets: @assets
