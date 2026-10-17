# Plugins: contract v2

A plugin is a WebAssembly module that uses [Extism](https://extism.org)'s
ABI. It does what it declared, gets only the capabilities a person granted,
and nothing else. It doesn't depend on the core's language, so the core can
change underneath it.

Why not Rails engines: an engine runs with full access to everything, and it
reaches into internals, so core can never change them. Plugins written by AI
for site owners who can't review the code make that the biggest risk the CMS
carries. A WebAssembly module can only call what the host hands it.

## The file

One `.wasm`. Build it with an Extism PDK:

| Language | PDK | Build |
| --- | --- | --- |
| Go | `github.com/extism/go-pdk` | `GOOS=wasip1 GOARCH=wasm go build -buildmode=c-shared -o p.wasm .` |
| Rust | `extism-pdk` | `cargo build --target wasm32-unknown-unknown --release` |
| TypeScript/JS | `@extism/js-pdk` | `extism-js plugin.js -i plugin.d.ts -o p.wasm` |
| Python | `extism-py` | `extism-py plugin.py -o p.wasm` |

## Exports

### `manifest` (required)

It takes no input and outputs JSON:

```json
{
  "key": "visits",
  "name": "Visits",
  "version": "1.0.0",
  "description": "Counts the page views a site reports.",
  "permissions": { "content:read": true, "storage": true, "http": ["api.example.com"] },
  "hooks": ["page.published"],
  "routes": [
    { "method": "POST", "path": "/hit", "export": "hit", "public": true },
    { "method": "GET", "path": "/stats", "export": "stats" }
  ],
  "admin": { "screens": [ { "id": "stats", "title": "Visits", "source": "/stats",
    "table": { "rows": "pages", "columns": [ { "key": "path", "label": "Page" }, { "key": "views", "label": "Views" } ] } } ] },
  "site_config": { "endpoint": "/api/x/visits/hit" }
}
```

- `key`: lowercase letters, digits and `_`. It is the plugin's namespace
  (storage, routes) and stays the same across versions.
- `permissions`: what it asks for. Hosts are names (`api.example.com`), never
  `*` or URLs.
- `site_config`: what `/api/v1/site` publishes under `plugin_config.<key>`
  for the site's build.

The manifest is read in a sandbox with nothing granted. The plugin is stored
switched off.

### `on_event`

Each event the plugin hooks arrives as input: `{"event": "page.published",
"data": {…}}`, where `data` is the webhook payload. Events are delivered in
the background, so a slow or failing plugin never holds up a save. The
events are `page.published|updated|unpublished|deleted`,
`entry.published|updated|unpublished|deleted` and `global.updated`.

### Route exports

A route is served at `/api/x/<key><path>`. The export gets:

```json
{ "method": "POST", "path": "/hit", "query": {…}, "headers": {"Content-Type": "…"},
  "body": "<the request body, up to 1 MB>", "ip": "…",
  "actor": { "name": "…", "type": "User|ServiceToken", "capabilities": [ … ] } }
```

`actor` is `null` on a public route called by no one signed in. A route
that isn't `public` needs a caller with `plugins:read`.

It answers `{"status": 200, "headers": {…}, "body": "…"}`. Any other output
is sent as JSON with a 200. `Set-Cookie` is dropped, and every answer is
served with `Content-Security-Policy: sandbox`, so a plugin can't run script
as the CMS's origin.

## The host's capabilities

These are imports from `extism:host/user`. Each one takes a string and
returns JSON (memory offsets, Extism's convention). One that wasn't granted
answers `{"error": "lp_kv_set wasn't granted to this plugin"}` instead of
trapping.

| Import | Needs | Input | Output |
| --- | --- | --- | --- |
| `lp_log` | always | a message | `{"ok": true}` |
| `lp_content` | `content:read` | `{"page": "about"}`, `{"pages": true}`, `{"collection": "posts"}`, `{"collection": "posts", "entry": "hello"}` or `{"global": "nav"}` | live content, shaped as `/api/v1` shapes it |
| `lp_kv_get` | `storage` | a key | `{"found": bool, "value": "…"}` |
| `lp_kv_set` | `storage` | `{"key": "…", "value": "…"}` (value ≤ 1 MB, ≤ 100,000 keys) | `{"ok": true}` |
| `lp_kv_delete` | `storage` | a key | `{"ok": true}` |
| `lp_kv_list` | `storage` | a key prefix | `{"keys": […]}` (≤ 1000) |
| Extism `http_request` | `http` | the PDK's HTTP call | only to granted hosts, responses ≤ 4 MB |

Storage is the plugin's own (`plugin_kv`, keyed by its `key`). Other plugins
can't see it, and it survives upgrades. Removing a plugin keeps its storage
unless removal is asked to purge it.

Limits: each call gets a fresh instance, 10 seconds, and 64 MB of memory.

## Installing, granting, upgrading

```
POST   /api/plugins            the .wasm as the body (or multipart "file")   plugins:write
PATCH  /api/plugins/<key>      {"plugin": {"granted": {…}, "enabled": true}}  plugins:write
DELETE /api/plugins/<key>[?purge_data=1]                                      plugins:write
GET    /api/plugins[/<key>]                                                   plugins:read
```

A grant is never wider than what's asked: granting more than the manifest
requests grants what it requests. Uploading a new version of an installed
plugin keeps the grants it still asks for. If it asks for more, it stays off
until someone grants the rest. A plugin that fails to load is left off and
logged, never fatal, so plugins can't break the site.

## Admin screens, as data

The admin draws what `admin.screens` describes. Today that's a table filled
from one of the plugin's GET routes (`source`), with the rows under
`table.rows` and the columns as listed. Forms (fields in the CMS's own field
DSL, posted to a route) come next. A sandboxed iframe served from a route is
the escape hatch for what data can't describe.

## Porting the Rails engines

The engines map onto this contract like this:

- **Forms**: a form's definition in storage, a public `POST /submit` route
  (honeypot and captcha checks via `http` to the captcha provider's host),
  submissions in storage, an admin table of submissions, `site_config`
  publishing each form's fields and action.
- **Commerce (quotes and invoices)**: a public `POST /quote` route, quotes and
  invoices in storage, and admin screens. Sending an invoice needs email,
  which is a host capability still to add (`lp_mail`, granted per plugin,
  sent through the install's mail settings).
- **Leads, AI, Market**: these need `content:read`, storage and `http` to
  their APIs. AI's writes to content need a `content:write` capability that
  goes through the same publish gate as any other writer, so its writes to
  live content come back as revisions.
