# The delivery API (`/api/v1`)

What a site reads to build and serve itself. It is read-only, frozen at v1,
and only ever shows what's live — a draft never reaches a site, whatever
token asks. `/api` stays the admin's and the CLI's (writes, drafts,
management).

Authenticate with the site's service token (Settings › Service tokens, the
"Production site" role): `Authorization: Bearer <token>`.

## The contract

It answers the same contract as the Go core (librepublishgo), which
[@librepublish/astro](https://github.com/Martin-Business-Consultants/librepublish-astro)
holds every site to: its recorded answers are copied into
`spec/fixtures/contracts/go` (`bin/contracts-sync ../librepublishgo`, pinned
in `go.sha256`), and `spec/contracts/delivery_contract_spec.rb` seeds the same
site here, makes each request and fails on a missing key, a key of another
type, a missing header, a key the Go core doesn't send that isn't listed as
this CMS's own, a schema that isn't closed, or a digest made another way.

The integration is strict — a record with a key it doesn't know fails the
site's build — so this CMS's own keys are few and listed in the spec
(`RAILS_ONLY`): `/site`'s `description` and `meta.api_version`, `/sitemap`'s
`url`, `changefreq`, `priority` and `meta.site_url`, `/site_health`'s `group`,
`title`, `detail`, `ok`, `for_site` and its summary in `meta`, `meta.total`
on `/globals` and `/redirects`, `data.removed` on a full `/content`, and a
collection_list's entries' `body_markdown` (@librepublish/astro reads it
from its `rails-core` change on; 0.8.2 refuses it).

## On, off, or some of it

It's off unless the site is served over the API: Settings › General › How
the site is served.

| Mode | The delivery API |
| --- | --- |
| **Website** (the default) | Off: `/api/v1` and the frontend's endpoints (`/api/frontend`, `/frontend/…`) answer 404. The theme draws the site. |
| **Website + API** | What's chosen: each collection that's "Available over the API" (its settings, or General), and the pages with the globals, all or none. The rest answers 404. |
| **API only** | Everything live. The theme is off, and the CMS's own address shows a blank page (`robots.txt` disallows all; `sitemap.xml` is the frontend's, from `/api/v1/sitemap`). |

The management API (`/api/pages`… for the `cms` CLI, MCP and agents) is on
in every mode, as are the Forms plugin's public submissions and webhooks. A
404 says why to a token holder only; anyone else is refused before that.

## One answer shape

    {"data": …, "meta": {…}, "included": {"assets": {"<id>": {…}}}}

- `meta` on lists: `{page, per, total, next_page}` (`?page=`, `?per=` up to 100),
  and the same in headers on pages and entries: `X-Total-Count`,
  `X-Total-Pages`, and a `Link` with `first`, `prev`, `next` and `last`.
- `included.assets`: every asset the records point at, resolved — absolute
  URLs on the CMS host, `width`, `height`, `alt`, `focal_x`/`focal_y`,
  `srcset`, `thumb_url` and `variants` (`w640`, `w1280`, `w1920`: the widths
  `/site`'s `image_widths` names).
- `Cache-Tag` header: the tags a publish purges (below).
- `X-CMS-Schema-Digest` header, on every answer to a token: the digest of the
  schema it was answered under (below). A build that sees it move stops.

What a site asks for besides the records:

- `?fields=title,slug,seo.meta_title`: only those keys of each record (and
  its `id`); a dot path reaches into an object.
- `?include=assets,entries,pages`: what goes in `included` — the assets the
  records point at (the default), the live entries
  (`{"<collection>/<slug>": entry}`) and pages (`{path: page}`) their fields
  and blocks link to, or `none`.
- `OPTIONS` on `/pages`, `/pages/<path>`, `/collections/<slug>/entries`,
  `…/entries/<slug>` and `/globals/<slug>` answers the resource's parameters
  and the JSON Schema of its answer (`{resource, methods, params, schema}`).

## Files

An asset's URLs are `<CMS>/files/<key>/<name>`, and an image's renditions
`<CMS>/files/<key>/w<width>/<name>`, as the Go core's are: @librepublish/astro
allows `/files/**` as remote images and copies what a built page links there
into the site, so the live site serves its own. Each redirects to the file
as Active Storage serves it; the Active Storage URLs the API gave before 1.34
keep working.

## Errors

Every `/api` error — the delivery API's and the management API's — is JSON
in one shape:

    {"error": "<code>", "message": "…"}

with `errors` (per field) on a 422 and `capability` (what the role lacks) on
a 403. The codes: `bad_request` (400: a missing parameter, a body that isn't
JSON), `unauthorized` (401), `forbidden` (403), `not_found` (404, also for an
`/api` path no route matches), `not_acceptable` (406: a format the endpoint
doesn't serve), `conflict` (409), `invalid` (422), `rate_limited` (429, with
`Retry-After`) and `internal_error` (500, never with a backtrace).

## Caching and limits

- **Conditional GET.** Every answer carries an `ETag`; send it back as
  `If-None-Match` and an unchanged answer is `304 Not Modified`. For
  `/content` the tag stands for the content it was built from, not its
  bytes (each read carries a fresh `meta.cursor`): on a 304, keep what you
  have, cursor included.
- **The CMS caches `/content`** while nothing it's built from changes
  (DeliveryVersion); `included.assets` is resolved on every read.
- **Rate limit.** Each token gets 1,200 requests a minute across `/api/v1`
  (`CMS_DELIVERY_RATE_LIMIT`, requests a minute, `0` for none); past it,
  `429` with `Retry-After`. A build reads about ten times; a site rendered on
  demand reads on each cache miss, so raise it for a busy one.
- **Lists.** Pages and entries are paged (`meta.next_page`); `/content`,
  `/globals`, `/collections`, `/redirects`, `/schema` and `/sitemap` answer
  whole — they're a site's configuration and what a build reads in one go,
  bounded by the site itself.

**`/api` pages differently, on purpose.** The management API's lists keep the
shape they've always had, `{"<items>": […], "page", "per", "total"}` at the
top level (references add `total_pages`); `/api/v1` puts paging in `meta`
with `next_page`. `/api`'s contract is frozen — the CLI, integrations and agents
read it — so it won't move to v1's shape; a new client reading lists should
use `/api/v1`.

## Endpoints

| Endpoint | What |
|---|---|
| `GET /api/v1/site` | Name, public URL, `default_locale`, `locales` (every one but the default is a path prefix: `/fr/…`), contact details (the business name as `title`, phone, email, address), enabled plugins, `plugin_config` (Forms: its captcha; Commerce: where quote requests post), `api_version`, `image_widths` (the widths renditions are made at) and `branding` (Settings › Branding, only what's set: `logo` and `favicon` as assets, `primary_color`, `secondary_color`, `font`, `border_radius`, `box_shadow`). `meta.cms_url` is the CMS's own address (`APP_HOST`), which asset URLs start with. |
| `GET /api/v1/content[?since=<cursor>]` | Every live page (blocks expanded), entry and global — or, with a previous read's `meta.cursor`, only what changed, plus `data.removed` (what stopped being live). `meta.full: true` means replace what you have. A cursor older than 30 days gets a full answer. |
| `GET /api/v1/pages[?locale=]`, `/api/v1/pages/<path>` | Live pages, blocks expanded (below), with `translations: [{locale, path}]`. |
| `GET /api/v1/collections`, `/collections/<slug>` | Collections and their fields. |
| `GET /api/v1/collections/<slug>/entries[?locale=]`, `…/entries/<slug>` | Live entries, with translations. |
| `GET /api/v1/globals`, `/globals/<slug>` | Globals' data (secret-looking values masked). |
| `GET /api/v1/schema` | JSON Schema (2020-12) for each block type's data, each collection's fields, each global, pages with fields, and SEO, and its digest in `meta.schema_digest` (below). Each field carries `title` and `x-cms-type` (markdown, asset, link, blocks…) — what a build generates its types from. |
| `GET /api/v1/sitemap` | URLs on the public site: `loc` (absolute once the site's URL is set), `path`, `type` (`page` or `entry`), `locale`, `lastmod`, and hreflang `alternates` (`{hreflang, href}`; each also has the older `locale` and `url`), with `url` (as `loc`), `changefreq` and `priority`. A record whose SEO says `exclude_from_sitemap` isn't listed. |
| `GET /api/v1/robots` | The site's robots.txt (`data.text`, and `data.mode`: `generated` or `custom`); `/api/v1/robots.txt` is the file itself. Cache tag `robots`. |
| `GET /api/v1/redirects`, `/api/v1/redirects.txt` | Active rules; the `.txt` is a Cloudflare `_redirects` file (exact rules first, wildcards longest first, `:splat`). |
| `GET /api/v1/site_health` | Site health's checks for a build to hold the site to: `key`, `state` (passes, fails, yours_to_judge) and `message` (the check, and what to do when it doesn't pass), with `group`, `title`, `detail`, `ok` and `for_site` (false for how the CMS itself is run: backups, two-factor… which no build can fix). Cache tag `site`. |
| `GET /api/v1/forms`, `/forms/<slug>` (Forms) | Published forms: fields, `action` (where the browser posts, on the CMS), `honeypot`, `captcha: {provider, site_key}`. |

Forms and quote requests post straight from the browser to the CMS; CORS
allows the origins in Settings › General.

**Expanded blocks.** A block the CMS fills in carries `resolved` beside its
`data`: a `collection_list` gets `{collection, entries, total, groups?}` —
each entry with its `collection` and `url`, and only published entries, even
when the block is set to show any status (that's for the admin's preview) —
and a `contact_info` gets `{contact}`: the business name, phone, email and
address from Settings › General. A page's `Cache-Tag` names what its blocks
pull in (`collection:<slug>`, `site`), so publishing an entry purges the pages
listing it.

An entry's blocks (a collection with blocks) are expanded the same way, and
a collection_list's entries carry their `seo`, as a record does.

## The schema and its digest

`GET /api/v1/schema`'s `data` is the Go core's shape:

    {"$schema": "https://json-schema.org/draft/2020-12/schema",
     "blocks":      {"hero": {"$schema": …, "title": "Hero", "type": "object", "properties": {…}, "required": […], "additionalProperties": false}, …},
     "collections": {"posts": {"title": "Posts", "type": "object", "properties": {…}, …}, …},
     "globals":     {"nav": {"title": "Navigation", …}, …},
     "pages":       {"about": {…}},      // live pages with fields of their own, by path
     "seo":         {…}}

Each part is a JSON Schema of its own, closed (`additionalProperties: false`)
all the way down — groups and repeater items too — because only declared
keys are delivered (below). A synced pattern is expanded into its blocks
before a site sees it, so `blocks` has no `pattern`.

`meta.schema_digest` (and the `X-CMS-Schema-Digest` header on every answer)
is `sha256:` and the hex SHA-256 of `data` in canonical JSON, made byte for
byte as the Go core makes it (`CanonicalJson`): object keys sorted by their
bytes, no whitespace, `<`, `>`, `&`, U+2028 and U+2029 written `<`…,
control characters as `\n`, `\r`, `\t`, `\b`, `\f` or `\u00xx`, integral
numbers without a fraction. A site pins it (@librepublish/astro's
`cms.lock.json`) and a build stops when it moves; `schema.changed`
(docs/webhooks.md) says when it has.

**Deprecated, going in 2.0:** the shape before 1.34 is still there for the
clients that read it — `data.block_types` (`{slug: {title, version, data}}`,
`pattern` included), and inside each collection `enable_blocks` and
`frontmatter`, each global `data`, and each page `title` and `frontmatter`,
which JSON Schema reads as annotations. Read `blocks` and the parts
themselves instead. Since a page's `title` is part of the schema until then,
retitling a page that has fields of its own moves the digest.

## Only what the schema declares

A record's frontmatter, its blocks' data, a global's data and its SEO are
delivered with only the keys the schema declares, however old the data: a
field since removed, a key an API client stored. What isn't declared stays
in the record and in `/api`. A page without fields of its own has
`frontmatter: {}`. SEO's declared keys are the SEO panel's (with
`exclude_from_sitemap`), and this CMS's own `sitemap_priority`,
`sitemap_changefreq` and `twitter_image_id`; an older record's `canonical`
is given as `canonical_url` too, and stays (deprecated) as itself.

## Forms

The Forms plugin's public routes (`/api/x/forms/list`, `/definition`,
`/submit`, and a form's hook) are the plugin's, from its own repository. For
@librepublish/astro's `<Form>` and `<StaticForm>` it must answer as the Go
core's Forms does (`spec/fixtures/contracts/go/forms`): `{forms: [{slug,
name, digest, …}]}` and `{form: {…, digest}}` with each form's `digest` the
canonical JSON digest of its definition without `digest` (CanonicalJson),
`Cache-Control: public, max-age=60` on both, a submit answering 200, 422
with each field's errors, or 410 for a closed form, and a hook signed as
webhooks are (`X-CMS-Signature`, `X-CMS-Signature-V2`, `X-CMS-Timestamp`,
`X-CMS-Delivery`, `X-CMS-Form`; Webhook::Signature), with `site_config`'s
`forms` giving `/site`'s `plugin_config.forms` its `list`, `definition` and
`submit` addresses.

## Builds and publishing

A build reports itself to `POST /api/frontend/builds` with how it renders
(`render`: static, server or hybrid), its `webhook_url` and the
`content_cursor` it built from (docs/install.md, "Static or on demand"),
the `schema_digest` it was checked against, and its launch checklist
(`checks`, with `checks_url` where the live site answers the rest), which
Settings › Deploy shows; it answers `ok` and `approval_pending`.
Publishing then rebuilds a static site through the deploy provider (GitHub,
a build hook, or Cloudflare), and sends an on-demand site a signed purge
(`X-CMS-Signature` and `X-CMS-Signature-V2`, docs/webhooks.md) naming
what changed. A report can only
keep a site rebuilt on publish; one that switches it to purges, or moves where
they go, waits for approval in Settings › Deploy (`POST
/api/frontend/delivery_approval`, settings:write) — the site's read-only
token can't make that change on its own.

Cache tags, the same in `Cache-Tag` headers and purges: `page:<path>`,
`entry:<collection>/<slug>`, `collection:<slug>`, `global:<slug>`, `pages`,
`sitemap`, `redirects`, `robots`, `site` (Settings › General's name, URL and contact
details: changing them rebuilds or purges like a publish), `schema`
(`/api/v1/schema`, and `schema.changed`), and, from Forms, `form:<slug>`.
