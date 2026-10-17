# Libre Publish

A headless CMS as one file: the API, the admin, SQLite and a WebAssembly
plugin host, compiled into a single static binary (about 20 MB, no cgo) for
Linux, macOS and Windows.

```sh
curl -fsSL https://raw.githubusercontent.com/Martin-Business-Consultants/libre-publish/go-rewrite/install.sh | sh
librepublish serve --data ./data
# open http://localhost:8080/cms/ and make the first administrator
```

That is the whole install. No Ruby, no Docker, no separate database, no
restart to add a plugin. It idles at about 28 MB of memory. The script picks
the build for your machine from the latest release and checks it against the
release's checksums. Without it, download `librepublish-<os>-<arch>` from
[Releases](https://github.com/Martin-Business-Consultants/libre-publish/releases)
and run it.

This branch is a rewrite of the Rails core, which stays on `main` as the
reference. It is checked against that core's contracts: the same tables, the
same `/api` and `/api/v1` answers (docs/delivery-api.md), the same webhook
payloads (docs/webhooks.md, `contracts/webhook_contract.json`). So the `cms`
CLI, the Astro integration and existing webhook receivers keep working.

## Running it

From source (Go 1.26; `mise install` sets it up):

```sh
make run                      # go run …serve --data ./data, on :8080
make build                    # dist/librepublish for this machine
make test                     # vet + the integration tests
make dist                     # every platform, with checksums.txt
make plugin                   # dist/visits.wasm, the example plugin
```

Releases: push a `vX.Y.Z` tag and `.github/workflows/release.yml` tests,
builds every platform and publishes them with `checksums.txt`, which
`install.sh` downloads.

| Flag | Variable | What |
| --- | --- | --- |
| `--data` | `DATA_DIR` | Where everything lives: `cms.sqlite3`, `storage/` (uploads), `variants/`, `secret.key`. Back this directory up and you've backed up the site. |
| `--addr` | `ADDR` / `PORT` | Where to listen (`:8080`). |
| `--url` | `APP_URL` | The CMS's own address. Asset URLs start with it. |
| | `SITE_KEY` | The tenant name webhooks carry (default: the first label of the URL's host). |
| | `SECRET_KEY` | Instead of `DATA_DIR/secret.key`: the key that seals token plaintexts and webhook secrets. |
| | `CMS_DELIVERY_RATE_LIMIT` | Requests a minute per token on `/api/v1` (1200; `0` for none). |
| | `TRUST_PROXY=1` | Behind Caddy, nginx or a load balancer: read the client's address from `X-Forwarded-For`. |

Put TLS in front of it (Caddy is one line: `cms.example.com { reverse_proxy :8080 }`).

From the command line, without the admin:

```sh
librepublish user create --email you@example.com --name You --password '…'   # --role Editor, …
librepublish user password --email you@example.com --password '…'            # locked out
librepublish token create --name PRODUCTION --role "Production site"          # the site's read token
librepublish seed-blocks                                                      # the starter block types
```

`GET /api/tools/backup` (the `tools:use` capability) streams a `.tar.gz` of
a consistent copy of the database and every upload; unpacking it into a data
directory restores it.

## Moving over from the Rails core

Point `--data` at a directory holding a copy of the Rails install's
production database as `cms.sqlite3`, with its `storage/` directory (Active
Storage's files) beside it:

```sh
mkdir -p data && cp /path/to/rails/storage/production.sqlite3 data/cms.sqlite3
cp -r /path/to/rails/storage/?? data/storage/        # the two-letter blob folders
./librepublish serve --data data --url https://cms.example.com
```

The schema keeps Rails' table and column names, so the Go core reads the
database as it is and only adds its own tables (`admin_sessions`,
`revisions`, `plugins`, `plugin_kv`). Pages, entries, collections, globals,
block types, redirects, settings, roles, users, the audit log, content
references and media all carry over, and media URLs move to `/files/<key>/…`.

What doesn't carry over is what Rails encrypted with its own key
(`config/credentials`). The Go core can't read those values:

- **Personal and service tokens** still authenticate, because both cores look
  them up by SHA-256 digest. They just can't be revealed again: rotate one to
  see a new secret. `cms login` hands a person a fresh token for the same reason.
- **Webhook secrets** can't sign. Rotate each webhook's secret (Webhooks › …,
  or `POST /api/webhooks/<id>/rotate_secret`) and give the receiver the new one.
- **Two-factor sign-in.** An account with it on is refused at sign-in rather
  than let in on its password alone. `librepublish user disable-2fa --email …`
  turns it off, knowingly. The Go core has no 2FA of its own yet.
- **Settings' secrets** (the GitHub token, mail credentials) need entering again.

Passwords carry over: both cores use bcrypt.

The serving modes: this core has no theme, so it is headless. `api_only`
serves everything live over `/api/v1`. `website_api`, and a Rails install's
`website`, serve only what was chosen: collections marked "Available over
the API", plus pages and globals when `api_pages` is on.

## What's in it

**The management API (`/api`)**, frozen at the Rails core's shapes, which the
CLI, MCP and agents read:

- Pages (the tree, paths, bulk delete and status, page schemas) and
  collections with entries (frontmatter schemas, taxonomy, `toggle_field`,
  `update_field`), globals and block types (with the starter pack, exported
  from the Rails core's `BlockType::Defaults`).
- Assets: upload, metadata, folders, `?unused=1`, `used_by`, and on-demand
  width variants (`w640`, `w1280`, `w1920`).
- Redirects (`all`, `resolve`, CSV export and import), settings (secrets
  masked, masked values written back left alone), deploy (`GET`, `PATCH`,
  `trigger`), the audit log, trash (restore, purge; a page takes its children),
  webhooks (deliveries, test, secret rotation), service tokens (reveal,
  rotate, revoke), users, roles, search, references, the manifest,
  `api_tokens/me`, the device login (`cms login`), site health and backup.
- The agent envelope (`X-Agent-Envelope: 1` or `?envelope=1`), with
  breadcrumbs naming real records.
- One error shape: `{"error": code, "message": …}`, with `errors` on a 422
  and `capability` on a 403.

**The publish gate and review.** A write to something live from a role
without `<resource>:publish` is held as a revision, not applied: **202**
`{"status": "pending_review", "revision": {"id", "fields"}, "review_url"}`,
with `ignored_fields` when the write tried to change status. A second
proposal for the same record is a **409**. A write that changes nothing is
`{"status": "unchanged"}`. A person approves the revision in the admin
(Review) or with `POST /api/revisions/<id>/approve`, which applies it as
theirs. In the Rails core this lives in a plugin. Here it's core, because
agents depend on it.

**The delivery API (`/api/v1`)**: `site`, `content` (with `?since=` cursors
and `removed`), `pages`, `collections`, `entries`, `globals`, `schema`,
`sitemap`, `robots(.txt)`, `redirects(.txt)` (a Cloudflare `_redirects`) and
`site_health`. It uses one answer shape, `{data, meta, included.assets}`,
returns live content only, and expands blocks (`collection_list`,
`contact_info`, synced `pattern`). Every answer carries an `ETag`, honours
`If-None-Match` and sends `Cache-Tag` headers, all under a per-token rate limit.

**Webhooks** signed `X-CMS-Signature: sha256=<HMAC>`, with the envelope and
payload keys `contracts/webhook_contract.json` pins (copied from the Rails
core, which is held to the same file). The tests read it.

**Scheduling.** `publish_at` and `unpublish_at` are acted on within 30 seconds.

**The admin**: Svelte 5 and Tailwind 4 (`ui/`), built into
`internal/admin/dist` and embedded in the binary. It recreates the Rails
admin's look from the same design tokens: the admin bar, the WordPress-style
menu with fly-outs, postboxes and the Publish box, status filters, quick
filters, bulk actions and row actions. It's built from its own component
library (`ui/src/lib/components`): buttons, fields, a searchable combobox, tag
input, switches, dialogs and sheets, confirmations, toasts, tables,
pagination and ⌘K search. Forms are drawn from field schemas (every field
type, nested), blocks are edited in place with a block picker, media is
picked or uploaded inline, and schemas are edited as rows rather than JSON.
It follows the system's light or dark mode, and works on a phone. `make ui`
rebuilds it, and `make ui-dev` serves it with hot reload against `make run`.
The built `dist/` is committed, so `go install` needs no Node.

## Plugins: WebAssembly, with declared permissions

A plugin is one `.wasm` file built with [Extism](https://extism.org), so it
can be written in Go, Rust, TypeScript, Python, C# or Zig. Its `manifest`
export says what it is and what it needs. Installing it means uploading it.
It stays off until a person grants what it asks for, and it is loaded without
a restart. It can reach only the host's fixed capabilities: live content,
its own storage, outbound HTTP to the hosts it named, and logging. It can't
touch the database, the files, other plugins or the rest of the network, and
each call has a time limit. Its admin screens are data that the admin draws,
not code.

The contract is in [docs/plugins.md](docs/plugins.md), and
[plugins/visits](plugins/visits) is a working example in Go. The tests build
it, install it, grant it, call its public route, watch it hear
`page.published`, and check that it's refused storage once that grant is
taken back.

## How it's put together

```
cmd/librepublish/       the binary: serve, user, token, seed-blocks
contracts/              what clients rely on, pinned (from the Rails core)
install.sh              the one-command install
internal/cms/           the core (one package)
  store.go schema.sql   SQLite (modernc.org/sqlite, pure Go), Rails-compatible tables
  auth.go               capabilities, roles, tokens, sessions, sealed secrets
  fields.go             the field DSL: validation, JSON Schema, references (Rails' rules)
  content.go            pages and entries: writes, the publish gate, tree, trash, events
  revisions.go          held writes and review
  structure.go          collections, globals, block types, settings, audit, seeding
  assets.go             uploads, Active Storage layout, variants, file serving
  services.go           webhooks, deploys, the scheduler
  delivery.go           /api/v1
  api_*.go              /api
  plugins.go            the WebAssembly host
internal/admin/         the admin, embedded (dist/, built from ui/)
ui/                     the admin's source: Svelte 5 + Tailwind 4
plugins/visits/         an example plugin
```

## Not yet

These Rails-core features aren't in the Go core, so the CLI commands that
reach them get a 404:

- **The plugins that were Rails engines**: Forms (submissions), Commerce
  (quote requests, invoices), Leads, AI and Market. These are the first to
  port to the WebAssembly contract (docs/plugins.md, "Porting the Rails
  engines").
- **Agent runs and reporting**: `cms work`, `run-*`, `recommend`, `findings`,
  `reports`. **Brand** is read from the `brand` setting (and the manifest),
  but `cms brand` has no endpoint of its own yet.
- **Themes and website mode**: by design, as this core is headless.
- **The rest:** email (password reset, notifications), two-factor sign-in,
  block patterns' CRUD (synced patterns still expand), version history
  browsing and restore (versions are still recorded), the Build board,
  the image optimizer and bulk uploads, full-text search (search uses
  `LIKE`), IndexNow, CSP reports, the update checker, the MCP server, and the
  agent bootstrap (`/agent/install.sh`).
