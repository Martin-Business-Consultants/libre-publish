# Plugins: contract v3

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
  "permissions": { "content:read": true, "storage": true, "mail": false, "media:write": false, "http": ["api.example.com"] },
  "capabilities": [ { "key": "visits:read", "label": "See page views" } ],
  "hooks": ["page.published"],
  "routes": [
    { "method": "POST", "path": "/hit", "export": "hit", "public": true },
    { "method": "GET", "path": "/stats", "export": "stats", "capability": "visits:read" }
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
- `capabilities`: what it adds to the role editor, each `<key>:<name>` with
  a label. Administrators have them; other roles get them when ticked.

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
that isn't `public` needs a caller with its `capability` (one of the
plugin's own, or `plugins:read`/`plugins:write`); without one, a GET needs
`plugins:read` and anything else `plugins:write`. A route takes a body of up
to 1 MB unless it sets `max_body` (at most 10 MB). Public routes take 30
calls a minute from one address, and browsers on the origins in Settings ›
General may call them (CORS).

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
| `lp_site` | always | anything | `{"name", "url", "cms_url", "locale", "contact_email", "origins"}` (`origins`: the site's own, as CORS allows them) |
| `lp_content` | `content:read` | `{"page": "about"}`, `{"pages": true}`, `{"collection": "posts"}`, `{"collection": "posts", "entry": "hello"}` or `{"global": "nav"}` | live content, shaped as `/api/v1` shapes it |
| `lp_kv_get` | `storage` | a key | `{"found": bool, "value": "…"}` |
| `lp_kv_set` | `storage` | `{"key": "…", "value": "…"}` (value ≤ 1 MB, ≤ 100,000 keys) | `{"ok": true}` |
| `lp_kv_delete` | `storage` | a key | `{"ok": true}` |
| `lp_kv_list` | `storage` | a key prefix, or `{"prefix", "after", "limit"}`, or `{"prefix", "count": true}` | `{"keys": […], "next": "…"}` (≤ 1000 a page; `next` is the next page's `after`), or `{"count": n}` |
| `lp_mail` | `mail` | `{"to": […], "cc", "bcc", "subject", "text", "html", "from_name", "from_email", "reply_to"}` | `{"ok": true}`, sent through Settings › Email (from its defaults where blank); ≤ 50 recipients, ≤ 200 messages an hour |
| `lp_media_put` | `media:write` | `{"filename", "data": "<base64>", "content_type", "folder", "alt"}` (≤ 10 MB) | the asset, as the media API shows it; the folder defaults to `Plugins/<key>` |
| Extism `http_request` | `http` | the PDK's HTTP call | only to granted hosts, responses ≤ 4 MB |

Storage is the plugin's own (`plugin_kv`, keyed by its `key`). Other plugins
can't see it, and it survives upgrades. Removing a plugin keeps its storage
unless removal is asked to purge it.

Limits: each call gets a fresh instance, 10 seconds, and 64 MB of memory,
with the real clock and real randomness.

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

The admin draws what `admin` describes; a plugin ships no code into it.

```json
"admin": {
  "menu": { "label": "Forms", "icon": "form", "group": "Content", "badge": "/submissions?count=new" },
  "screens": [ … ]
}
```

`menu` puts the plugin in the sidebar (in `group`: Content, Insights, Tools,
Access or Settings), its submenu the screens that have a `menu` label;
`badge` is a GET route answering `{"count": n}`. Someone sees a screen when
they may call its `source` route, so a role with the plugin's capabilities
but not `plugins:read` still gets the plugin's screens.

A screen is `{id, title, source, …}` and one of `table`, `form` or `detail`.
Its query string (`#/plugins/<key>/<id>?id=…`) is passed to `source`.

- **table**: `rows` (the key in the source's answer), `key`, `columns`
  (`{key, label, link: {screen, params}, sub, num, badge, time}`),
  `row_actions` (`{label, screen, params}` or `{label, post, params, body,
  confirm, danger}`), `status_links` and `filters` (`{param, options}`, the
  options a key in the answer), `cursor` (`{param, next}` for paging) and
  `empty` (`{title, text}`).
- **form**: `record` (the key holding it), `save` (a POST route, sent
  `{<record>: …}` with the screen's `id`; a 422's `errors` mark the fields;
  `redirect: {screen, params}` moves on), and sections in `top` (full
  width), `main` and `side`, each `{title, fields}` in the CMS's field
  types, or `{title, readonly: "<key>"}` for items to show. Plugins add
  `form_builder` (a visual builder over `palette: [{type, label, icon,
  input, props}]`), `password`, and `select` with `options_from: {builder,
  types}` (choices taken from the record's builder fields).
- **detail**: `record`, `main` and `side` sections of `items`
  (`[{label, value, href, multiline, time, badge, tone, screen, params}]`),
  and `actions` (`post` actions, with `hide_if`/`show_if` on the record and
  `then` a screen to go to).

Screens can carry `actions` too: `{label, screen}`, `{label, download,
keep}` (a GET route, keeping the given query params) or `{label, post}`.

A sandboxed iframe served from a route is still the escape hatch for what
data can't describe.

## Default plugins

The binary ships some plugins (`internal/cms/defaults`, built from
`plugins/<key>` with `make plugins`). On first run each is installed,
granted what it asks for and switched on. A new binary upgrades it in place,
on or off as it was. Removing one removes it for good: it isn't put back.
Today that's **Forms** ([docs/forms.md](forms.md)).

## Porting the Rails engines

The engines map onto this contract like this:

- **Forms**: done, as the first default plugin (`plugins/forms`).
- **Commerce (quotes and invoices)**: a public `POST /quote` route, quotes and
  invoices in storage, and admin screens. Sending an invoice uses `lp_mail`.
- **Leads, AI, Market**: these need `content:read`, storage and `http` to
  their APIs. AI's writes to content need a `content:write` capability that
  goes through the same publish gate as any other writer, so its writes to
  live content come back as revisions.
