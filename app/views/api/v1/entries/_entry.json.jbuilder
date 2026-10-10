# frozen_string_literal: true

# A live entry as a site renders it.
json.extract! entry, :id, :slug, :title, :locale
json.collection entry.collection.slug
json.url entry.public_path
json.extract! entry, :frontmatter, :body_markdown, :blocks, :seo, :published_at, :updated_at
json.partial! "api/collection_entries/taxonomy", entry: entry
json.partial! "api/v1/shared/translations", record: entry
