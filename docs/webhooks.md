# Webhooks

A webhook tells another system when content changes: an analytics tool, a
search index, a chat channel, your own service. Add one in Settings ›
Webhooks (or `cms webhooks`), choose its events, and the CMS POSTs to its URL
each time one happens.

What a receiver can rely on is pinned in
`spec/fixtures/contracts/webhook_contract.json`, the Go core's contract word
for word (`spec/fixtures/contracts/go`), and
`spec/contracts/webhook_contract_spec.rb` and
`spec/contracts/delivery_contract_spec.rb` hold the CMS to it: a receiver
written for either core reads both.

## The request

```http
POST <the webhook's URL>
Content-Type: application/json
User-Agent: librepublish-webhooks/1
X-CMS-Event: page.published
X-CMS-Delivery: <the delivery's id, the same on every retry of it>
X-CMS-Timestamp: <Unix seconds when this attempt was signed>
X-CMS-Signature: sha256=<hex HMAC-SHA256 of the raw body, keyed with the webhook's secret>
X-CMS-Signature-V2: sha256=<hex HMAC-SHA256 of "<X-CMS-Timestamp>.<raw body>", the same key>

{"event": "page.published",
 "tenant": "acme",
 "delivered_at": "2026-09-17T10:00:00Z",
 "data": {"id": 12, "slug": "about", "path": "about",
          "url": "https://acme.test/about", "title": "About us",
          "status": "published", "locale": "en",
          "published_at": "2026-09-17T09:59:00Z",
          "updated_at": "2026-09-17T09:59:00Z"}}
```

- `event` is one of the webhook's events: `page.*` and `entry.*`
  (`published`, `updated`, `unpublished`, `deleted`), `global.updated`
  (`{id, slug, name, updated_at}`), `schema.changed` (below), and
  the plugins' events (`submission.created`, `quote_request.created`,
  `lead.created`, `lead.stage_changed`, …).
- `tenant` is the install's site key: `SITE_KEY`, else the first label of
  `APP_HOST`. A receiver serving several sites tells them apart by it, so
  when an install moves to a new host, keep `SITE_KEY` as it was.
- A page's `data` and an entry's carry the keys the contract lists; an entry
  has `collection_slug` in place of `path`.

## Verifying the signature

Compute the HMAC-SHA256 of `<X-CMS-Timestamp>.<raw body>` with the
webhook's secret and compare it, in constant time, with
`X-CMS-Signature-V2` (after `sha256=`); refuse a timestamp more than five
minutes from now, so a captured request can't be replayed later. Drop an
`X-CMS-Delivery` you've already handled: a retry carries the same one.
`X-CMS-Signature`, the HMAC of the body alone, is still sent for receivers
written before V2 (1.33 and earlier), and keeps working.

The CMS generates a secret for every webhook, and can rotate it. A receiver
that issues its own secret instead can have the webhook carry it:

```ruby
Webhook.create!(name: "analytics", url: "https://hooks.example.com/content",
                events: Webhook::EVENTS.grep(/\A(page|entry)\./),
                secret: "<the secret the receiver issued>")
```

## schema.changed

Sent when `/api/v1/schema`'s digest moves (`meta.schema_digest`, the
`X-CMS-Schema-Digest` header: docs/delivery-api.md): a block type,
collection, global or a live page's own fields changed. `data` is
`{"schema_digest": "sha256:…"}`. Writes settle for two seconds first, so
a schema edited field by field is announced once, and only when the digest
actually differs from the last one announced (before any, from the one the
site's last build was checked against). It also rebuilds or purges the
site (cache tag `schema`), as a content change does. A site built with
@librepublish/astro answers it with a rebuild that needs `npx
librepublish-astro sync` first: CI can subscribe a webhook to it and open a
pull request with the new `cms.lock.json`.

## The URL is the record's address

`data.url` is the address the site publishes the record at: absolute,
following its SEO canonical, and the same as the sitemap's (both come from
`PubliclyAddressable`). A receiver can match it to rows that arrive keyed by
URL — search performance, analytics. It is absolute only once Settings ›
General has the site's URL; until then it is a path. A new content type that
receivers should see includes `PubliclyAddressable` and gives a
`default_public_path`, rather than computing its address another way.

## Deliveries

Each attempt is logged with its status, timing and any error, and a webhook
that keeps failing is shown as failing. An attempt that can't connect, times
out, or is answered 408, 429 or 5xx is sent again after 30s, 2m, 5m, 15m and
40m (six attempts in all), each signed afresh, under the same
`X-CMS-Delivery`; any other answer is final.

A webhook's URL must not resolve to a private, loopback or link-local
address unless the install sets `CMS_ALLOW_PRIVATE_WEBHOOKS=true`
(docs/install.md).

## Purges

A site that renders on demand gets its cache purges from Settings › Deploy
(Deploys::Purge) as a POST to the `/_cms/webhook` its build reported, signed
the same way with the purge secret (its `CMS_WEBHOOK_SECRET`):
`X-CMS-Event: cms.purge`, `X-CMS-Signature`, `X-CMS-Signature-V2`,
`X-CMS-Timestamp` and `X-CMS-Delivery`, and a body naming the cache tags
to drop: `{"event": "cms.purge", "reason", "site", "all", "tags", "changes", "sent_at"}`.
