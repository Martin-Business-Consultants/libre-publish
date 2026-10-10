# Webhooks

A webhook tells another system when content changes: an analytics tool, a
search index, a chat channel, your own service. Add one in Settings ›
Webhooks (or `cms webhooks`), choose its events, and the CMS POSTs to its URL
each time one happens.

What a receiver can rely on is pinned in
`spec/fixtures/contracts/webhook_contract.json`, and
`spec/contracts/webhook_contract_spec.rb` holds the CMS to it.

## The request

```http
POST <the webhook's URL>
Content-Type: application/json
User-Agent: librepublish-webhooks/1
X-CMS-Signature: sha256=<hex HMAC-SHA256 of the raw body, keyed with the webhook's secret>

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
  (`published`, `updated`, `unpublished`, `deleted`), `global.updated`, and
  the plugins' events (`submission.created`, `quote_request.created`, …).
- `tenant` is the install's site key: `SITE_KEY`, else the first label of
  `APP_HOST`. A receiver serving several sites tells them apart by it, so
  when an install moves to a new host, keep `SITE_KEY` as it was.
- A page's `data` and an entry's carry the keys the contract lists; an entry
  has `collection_slug` in place of `path`.

## Verifying the signature

Compute the HMAC-SHA256 of the raw request body with the webhook's secret and
compare it, in constant time, with `X-CMS-Signature` (after `sha256=`). The
CMS generates a secret for every webhook, and can rotate it. A receiver
that issues its own secret instead can have the webhook carry it:

```ruby
Webhook.create!(name: "analytics", url: "https://hooks.example.com/content",
                events: Webhook::EVENTS.grep(/\A(page|entry)\./),
                secret: "<the secret the receiver issued>")
```

## The URL is the record's address

`data.url` is the address the site publishes the record at: absolute,
following its SEO canonical, and the same as the sitemap's (both come from
`PubliclyAddressable`). A receiver can match it to rows that arrive keyed by
URL — search performance, analytics. It is absolute only once Settings ›
General has the site's URL; until then it is a path. A new content type that
receivers should see includes `PubliclyAddressable` and gives a
`default_public_path`, rather than computing its address another way.

## Deliveries

Each delivery is logged with its status, timing and any error, and a webhook
that keeps failing is shown as failing. A webhook's URL must not resolve to a
private, loopback or link-local address unless the install sets
`CMS_ALLOW_PRIVATE_WEBHOOKS=true` (docs/install.md).
