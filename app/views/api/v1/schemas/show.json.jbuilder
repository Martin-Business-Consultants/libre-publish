# frozen_string_literal: true

# JSON Schema (2020-12) for what a site renders. Each field is annotated with
# its label (title) and the CMS's type (x-cms-type), which says how to render
# it: markdown, an asset id, a link, nested blocks…
json.data do
  json.set! "$schema", "https://json-schema.org/draft/2020-12/schema"
  json.block_types(@block_types.to_h { |block_type| [block_type.slug, {title: block_type.label, version: block_type.version, data: block_type.json_schema}] })
  json.collections(@collections.to_h { |collection| [collection.slug, {title: collection.name, enable_blocks: collection.enable_blocks, frontmatter: collection.frontmatter_json_schema}] })
  json.globals(@globals.to_h { |global| [global.slug, {title: global.name, data: global.frontmatter_json_schema}] })
  json.pages(@pages.to_h { |page| [page.path, {title: page.title, frontmatter: BlockType.json_schema_for(page.fields)}] })
  json.seo BlockType.json_schema_for(SeoFields::ALL)
end
json.meta({cms_version: Cms::VERSION})
