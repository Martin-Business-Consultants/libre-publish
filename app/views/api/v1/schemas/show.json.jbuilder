# frozen_string_literal: true

# JSON Schema (2020-12) for what a site renders (DeliverySchema). Each field is
# annotated with its label (title) and the CMS's type (x-cms-type), which
# says how to render it: markdown, an asset id, a link, nested blocks…
# meta.schema_digest names this exact schema (CanonicalJson of `data`).
json.data @schema
json.meta({cms_version: Cms::VERSION, schema_digest: @schema_digest})
