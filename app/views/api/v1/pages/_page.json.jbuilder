# frozen_string_literal: true

# A live page as a site renders it: blocks expanded (Page::BlockExpansion),
# and its frontmatter, block data and SEO only what /api/v1/schema declares
# (DeliveryHelper).
json.extract! page, :id, :path, :slug, :title, :locale
json.url page.public_path
json.blocks delivered_blocks(page.blocks)
json.frontmatter delivered.data(page.fields, page.frontmatter)
json.seo SeoFields.delivered(page.seo)
json.extract! page, :published_at, :updated_at
json.partial! "api/pages/taxonomy", page: page
json.partial! "api/v1/shared/translations", record: page
