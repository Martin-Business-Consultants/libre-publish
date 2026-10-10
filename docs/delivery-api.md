# The delivery API (`/api/v1`)

What a site reads to build and serve itself. It is read-only, frozen at v1,
and only ever shows what's live — a draft never reaches a site, whatever
token asks. `/api` stays the admin's and the CLI's (writes, drafts,
management).

Authenticate with the site's service token (Settings › Service tokens, the
"Production site" role): `Authorization: Bearer <token>`.

## One answer shape

    {"data": …, "meta": {…}, "included": {"assets": {"<id>": {…}}}}

- `meta` on lists: `{page, per, total, next_page}` (`?page=`, `?per=` up to 100).
- `included.assets`: every asset the records point at, resolved — absolute
  URLs on the CMS host, `width`, `height`, `alt`, and `variants`
  (`w640`, `w1280`, `w1920`). Present when a media library is installed.
- `Cache-Tag` header: the tags a publish purges (below).

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
| `GET /api/v1/site` | Name, public URL, `default_locale`, `locales` (every one but the default is a path prefix: `/fr/…`), contact details, enabled plugins, and `plugin_config` (Forms: its captcha; Commerce: where quote requests post). `meta.cms_url` is the CMS's own address (`APP_HOST`), which asset URLs start with. |
| `GET /api/v1/content[?since=<cursor>]` | Every live page (blocks expanded), entry and global — or, with a previous read's `meta.cursor`, only what changed, plus `data.removed` (what stopped being live). `meta.full: true` means replace what you have. A cursor older than 30 days gets a full answer. |
| `GET /api/v1/pages[?locale=]`, `/api/v1/pages/<path>` | Live pages, blocks expanded (below), with `translations: [{locale, path}]`. |
| `GET /api/v1/collections`, `/collections/<slug>` | Collections and their fields. |
| `GET /api/v1/collections/<slug>/entries[?locale=]`, `…/entries/<slug>` | Live entries, with translations. |
| `GET /api/v1/globals`, `/globals/<slug>` | Globals' data (secret-looking values masked). |
| `GET /api/v1/schema` | JSON Schema (2020-12) for each block type's data, each collection's fields, each global, pages with fields, and SEO. Each field carries `title` and `x-cms-type` (markdown, asset, link, blocks…) — what a build generates its types from. |
| `GET /api/v1/sitemap` | URLs on the public site, with `lastmod` and hreflang `alternates`. |
| `GET /api/v1/redirects`, `/api/v1/redirects.txt` | Active rules; the `.txt` is a Cloudflare `_redirects` file (exact rules first, wildcards longest first, `:splat`). |
| `GET /api/v1/site_health` | Site health's checks (`state`: passes, fails, yours_to_judge) for a build to hold the site to. |
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

## Builds and publishing

A build reports itself to `POST /api/frontend/builds` with how it renders
(`render`: static, server or hybrid), its `webhook_url` and the
`content_cursor` it built from (docs/install.md, "Static or on demand").
Publishing then rebuilds a static site through the deploy provider (GitHub,
a build hook, or Cloudflare), and sends an on-demand site a signed purge
(`X-CMS-Signature: sha256=<HMAC>`) naming what changed. A report can only
keep a site rebuilt on publish; one that switches it to purges, or moves where
they go, waits for approval in Settings › Deploy (`POST
/api/frontend/delivery_approval`, settings:write) — the site's read-only
token can't make that change on its own.

Cache tags, the same in `Cache-Tag` headers and purges: `page:<path>`,
`entry:<collection>/<slug>`, `collection:<slug>`, `global:<slug>`, `pages`,
`sitemap`, `redirects`, `site` (Settings › General's name, URL and contact
details: changing them rebuilds or purges like a publish), and, from Forms,
`form:<slug>`.
