# frozen_string_literal: true

# A live page as a site renders it: blocks expanded (Page#expanded_blocks).
json.extract! page, :id, :path, :slug, :title, :locale
json.url page.public_path
json.blocks page.expanded_blocks(live: true)
json.extract! page, :frontmatter, :seo, :published_at, :updated_at
json.partial! "api/pages/taxonomy", page: page
json.partial! "api/v1/shared/translations", record: page
