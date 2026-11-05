# frozen_string_literal: true

# The JSON Schema of everything a site renders (GET /api/v1/schema's `data`)
# and its digest, which a site pins the types it generated to: "sha256:" and
# the hex SHA-256 of `data` in canonical JSON (CanonicalJson). Every /api/v1
# answer carries the digest (X-CMS-Schema-Digest), /schema has it in
# meta.schema_digest, and `schema.changed` tells webhooks and the deploy when
# it moves (DeliverySchema::Announcement). The Go core's contract
# (spec/fixtures/contracts/go, docs/delivery-api.md), which
# @librepublish/astro holds a site to.
#
#   {"$schema" => "…/2020-12/schema",
#    "blocks"      => {"hero" => {closed JSON Schema of its data, "title" => "Hero"}, …},
#    "collections" => {"posts" => {closed JSON Schema of an entry's frontmatter, "title" => "Posts"}, …},
#    "globals"     => {"nav" => {closed JSON Schema of its data, "title" => "Navigation"}, …},
#    "pages"       => {"about" => {closed JSON Schema of its frontmatter}, …},   # live pages with fields
#    "seo"         => closed JSON Schema of a record's seo (SeoFields.json_schema),
#    "block_types" => {…}}                                                        # deprecated, below
#
# Each part is a JSON Schema in its own right, closed (additionalProperties:
# false) all the way down, because the delivery API sends only the keys it
# declares (DeliverySchema::Declared). Synced patterns are expanded before
# delivery, so `blocks` has no `pattern`.
#
# Before 1.34 this answer had another shape, and its keys are still there
# for the clients that read it, deprecated until 2.0 (docs/compatibility.md):
# `block_types` ({slug => {title, version, data}}), and inside each
# collection `enable_blocks` and `frontmatter`, each global `data`, and each
# page `title` and `frontmatter` — extra keywords, which JSON Schema ignores.
class DeliverySchema
  JSON_SCHEMA = "https://json-schema.org/draft/2020-12/schema"
  HEADER = "X-CMS-Schema-Digest"

  # The schema now: rebuilt only when what it's made of changes (#version).
  def self.current
    stamp = version
    cached = @current
    return cached.last if cached&.first == stamp

    new.tap { @current = [stamp, it] }
  end

  def self.digest = current.digest

  # Where the digest last announced is kept.
  SETTING = "delivery_schema"
  # How long writes settle before the digest is read again: a schema edited
  # field by field announces once.
  SETTLE = 2.seconds

  # Something the schema is made of changed (SchemaSource): once writes
  # settle, read the digest again.
  def self.announce_later
    DeliverySchema::AnnounceJob.set(wait: SETTLE).perform_later
  end

  # Announces `schema.changed` ({schema_digest}) to webhooks and the deploy
  # (which rebuilds or purges, tag `schema`) when the digest isn't the one
  # last announced. The first reading is only noted: there's nothing it
  # changed from.
  def self.announce_now
    digest = self.digest
    before = nil
    Setting.set(SETTING) { |data| {"announced_digest" => digest}.tap { before = data["announced_digest"] } }
    Event.announce("schema.changed", {schema_digest: digest}) if before.present? && before != digest
  end

  # Changes whenever anything the schema is made of does: block types,
  # collections, globals, live pages (their fields), and Settings › General
  # (which collections are served). Each table answers as DeliveryVersion's
  # do: its row count, newest updated_at and their sum.
  def self.version
    Digest::SHA256.hexdigest([BlockType.all, Collection.all, Global.all, Page.live, Setting.where(key: Serving::KEY)]
      .map { it.pick(Arel.sql("COUNT(*)"), Arel.sql("MAX(updated_at)"), Arel.sql("SUM(julianday(updated_at))")) }.to_json)
  end

  def data
    @data ||= {
      "$schema" => JSON_SCHEMA,
      "blocks" => block_types.reject { it.slug == "pattern" }.to_h { |type|
        [type.slug, closed(type.fields).merge("$schema" => JSON_SCHEMA, "title" => type.label)]
      },
      "collections" => collections.to_h { |collection|
        [collection.slug, closed(collection.fields).merge("title" => collection.name,
          "enable_blocks" => collection.enable_blocks, "frontmatter" => collection.frontmatter_json_schema)]
      },
      "globals" => globals.to_h { |global|
        [global.slug, closed(global.fields).merge("title" => global.name, "data" => global.frontmatter_json_schema)]
      },
      "pages" => pages.to_h { |page|
        [page.path, closed(page.fields).merge("title" => page.title, "frontmatter" => BlockType.json_schema_for(page.fields))]
      },
      "seo" => SeoFields.json_schema,
      "block_types" => block_types.to_h { |type| [type.slug, {"title" => type.label, "version" => type.version, "data" => type.json_schema}] }
    }.as_json
  end

  def digest
    @digest ||= CanonicalJson.digest(data)
  end

  private

  def closed(fields) = BlockType.json_schema_for(fields, closed: true)

  def block_types = @block_types ||= BlockType.order(:slug).to_a

  def collections = Collection.order(:slug).to_a.select { Serving.collection?(it) }

  def globals = Global.order(:slug).to_a

  def pages = Page.live.order(:path).select { it.fields.any? }
end
