# frozen_string_literal: true

# A live entry as a site renders it.
json.extract! entry, :id, :slug, :title, :locale
json.collection entry.collection.slug
json.url entry.public_path
# Field data holds only the keys the schema declares (DeliveredData).
delivered = (@delivered_data ||= DeliveredData.new)
json.frontmatter delivered.fields(entry.collection.fields, entry.frontmatter || {})
json.body_markdown entry.body_markdown
json.blocks delivered.blocks(entry.blocks)
json.seo delivered.fields(SeoFields::ALL, entry.seo || {})
json.extract! entry, :published_at, :updated_at
json.partial! "api/collection_entries/taxonomy", entry: entry
json.partial! "api/v1/shared/translations", record: entry
