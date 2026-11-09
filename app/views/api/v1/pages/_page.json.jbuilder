# frozen_string_literal: true

# A live page as a site renders it: blocks expanded (Page#expanded_blocks).
json.extract! page, :id, :path, :slug, :title, :locale
json.url page.public_path
# Field data holds only the keys the schema declares (DeliveredData).
delivered = (@delivered_data ||= DeliveredData.new)
json.blocks delivered.blocks(page.expanded_blocks(live: true))
json.frontmatter delivered.fields(page.fields, page.frontmatter || {})
json.seo delivered.fields(SeoFields::ALL, page.seo || {})
json.extract! page, :published_at, :updated_at
json.partial! "api/pages/taxonomy", page: page
json.partial! "api/v1/shared/translations", record: page
