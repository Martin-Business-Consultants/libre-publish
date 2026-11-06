# frozen_string_literal: true

# A live entry as a site renders it: blocks expanded as a page's are, and its
# frontmatter, block data and SEO only what /api/v1/schema declares
# (DeliveryHelper).
json.extract! entry, :id, :slug, :title, :locale
json.collection entry.collection.slug
json.url entry.public_path
json.frontmatter delivered.data(entry.collection.fields, entry.frontmatter)
json.extract! entry, :body_markdown
json.blocks entry.blocks.nil? ? nil : delivered_blocks(entry.blocks)
json.seo SeoFields.delivered(entry.seo)
json.extract! entry, :published_at, :updated_at
json.partial! "api/collection_entries/taxonomy", entry: entry
json.partial! "api/v1/shared/translations", record: entry
