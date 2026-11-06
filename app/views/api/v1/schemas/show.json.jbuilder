# frozen_string_literal: true

# JSON Schema (2020-12) for what a site renders (DeliverySchema): each part
# closed, each field annotated with its label (title) and the CMS's type
# (x-cms-type), which says how to render it: markdown, an asset id, a link,
# nested blocks… `meta.schema_digest` is what a site pins (cms.lock.json).
json.data @schema.data
json.meta({cms_version: Cms::VERSION, schema_digest: @schema.digest})
