# Plugins

A plugin adds to the CMS without the core knowing about it: a Rails engine
that owns its tables, reaches core records by id, and extends the core only
through `Cms::Plugins` (`lib/cms/plugins.rb`) and in-process content events.
Remove its gem and the CMS runs as before. `engines/hello` is the reference;
this guide walks through it.

One plugin comes with the core's code, as the reference, and only for
working on the core: it's in the development and test bundle, so no install
carries it.

| Plugin | Key | Default | Holds |
|---|---|---|---|
| Hello (`engines/hello`) | `hello` | development and test only | The reference plugin |

Every install gets the two default plugins, Forms and Media; the others are
installed from their own repositories (below):

| Plugin | Key | Default | Holds |
|---|---|---|---|
| Forms (`cms-plugins/forms`) | `forms` | on | Forms, their emails, the public `/api/forms/:slug/submissions` endpoint, the Submissions inbox, Settings › Forms |
| Media (`cms-plugins/media`) | `media` | on, installed by default | The media library at `/media` (files, folders, uploads, zips), the picker asset fields open, `/api/assets`, `/api/asset_folders`, `/api/bulk_uploads`. It provides the core's `MediaLibrary` (`provide :media`): without it an asset field takes an id by hand, `?resolve=assets` is left out, and Branding has no logo |
| Commerce (`cms-plugins/commerce`) | `commerce` | off | Quote requests and the public `/api/quote_requests` endpoint, invoices and their hosted `/i/:token` page, Settings › Commerce |

## Where plugins live

- **From Settings › Plugins**: an admin gives a plugin's GitHub repository
  (`owner/name`) under "Add a plugin", and the CMS installs its latest
  release on the server, in `CMS_DATA_DIR/plugins/<key>`, where it stays
  through deploys and core updates, then restarts (`PluginChange`,
  `config/installed_plugins.rb`). Each one installed this way has an Update
  button (its newest release) and a Remove button (its code goes, its tables
  stay). These aren't bundled: a plugin's `lib/` goes on the load path and
  it's required by name, so it may depend only on gems the core bundles, as
  a plugin built like `engines/hello` does. One the install already bundles
  (below) wins. `CMS_INSTALLED_PLUGINS=off` boots without them.
- **Bundled** plugins ship with the core in `engines/<name>`. Only
  `engines/hello` does, as the reference, and only in development and test.
- **Installed** plugins live in `plugins/<name>` (ignored by git — they
  belong to the install, like its data), one repository each:

      bin/rails "plugins:install[https://github.com/org/cms-plugin,v1.0.0]"
      bin/rails "plugins:update[cms-plugin]"      # or all of them, with no name
      bin/rails "plugins:remove[cms-plugin]"      # its tables stay
      bin/rails plugins:list

  Installing clones the repo, then bundles, migrates and asks Puma to
  restart. A Docker install (Kamal, or a tool that runs it) lists its plugins in the
  `CMS_PLUGINS` builder secret instead, and each build fetches them into
  `plugins/` before bundling (`bin/fetch-plugins`, docs/install.md).

  - **Default** plugins are installed ones that every install gets at
    setup: `config/default_plugins.yml` lists them (Forms and Media), each
    pinned to the commit the release is tested with (CI runs their specs);
    `plugins:update` leaves a pinned plugin where it is.
    `bin/setup` and `bin/install` run `bin/rails plugins:install_defaults`,
    which installs any that aren't there; a Docker build fetches them along
    with `CMS_PLUGINS`. They stay ordinary plugins, so an install can go
    without one or swap it for another: `plugins:remove` it, or list `-forms`
    in `CMS_PLUGINS`. A Docker install with nothing beyond the defaults sets
    `CMS_PLUGINS=default`, since some hosts won't keep an empty secret.

  Forms and Commerce, which were part of the core, are installed this way
  now. Working on one beside the core, keep its repository next to the
  checkout (`../cms-plugins/forms`) and link it in:
  `ln -s ../../cms-plugins/forms plugins/forms`.

The Gemfile picks up every `engines/*/*.gemspec` and `plugins/*/*.gemspec`.
Every plugin is off until an administrator switches it on in Settings ›
Plugins, unless its manifest says `enabled_by_default: true`. Off keeps its
data.

## The shape of one

    engines/hello/
      hello.gemspec
      lib/hello.rb                  # module Hello; table_name_prefix "hello_"
      lib/hello/engine.rb           # registration, routes, migrations, event subscribers
      db/migrate/…_create_hello_greetings.rb
      app/models/hello/greeting.rb  # records, their concerns, and plain objects
      app/jobs/hello/…              # shallow: perform calls a model's *_now
      app/controllers/hello/…       # include PluginGated; plugin :hello
      app/views/hello/…             # Herb rules as in the core
      app/assets/stylesheets/hello/hello.css

- **Tables** are prefixed with the plugin's key (`hello_greetings`) and never
  change core tables. Migrations join the app's (an initializer adds the
  engine's `db/migrate`), so `db:migrate` runs them. The exception is a
  feature that moved out of the core into a plugin: its tables predate
  plugins and keep their names (`forms`, `form_submissions`, `form_emails`,
  `quote_requests`, `invoices`), as do its model and controller class names
  (`Form`, `Invoice`), so polymorphic references and audit rows stay valid.
  Its old migrations stay in the core's `db/migrate`.
- **Routes** join the app's route set from an initializer
  (`app.routes.append { scope "hello", module: "hello", as: "hello" … }`) rather
  than mounting an isolated engine, so the core's layout and helpers work on
  plugin pages. API routes go under `/api/<key>/`.
- **Controllers** inherit the core's (`ApplicationController`,
  `Settings::BaseController`, `Api::BaseController`), `include PluginGated`
  and say `plugin :hello`: every action is a 404 while the plugin is off. They
  declare capabilities with `requires_capability` like core controllers. An
  API controller also says `enforce_authorization`: the core's API refuses
  an action that declares nothing, but keeps a plugin's open until it opts
  in, as plugins written before that expect.
- **Behaviour** lives in the plugin's `app/models`, as in the core
  (STYLE.md): verbs on its records, concerns under `app/models/<model>/`, and
  plain objects for anything without a record (a client for an outside API,
  an import pipeline, a report definition). A plugin has no `app/services`;
  `spec/architecture` fails the build if one appears.
- **Jobs** are shallow and named for their record (`Invoice::DeliveryJob`):
  the model has `deliver_later`, which enqueues it, and `deliver_now`, which
  the job calls. Renaming a job keeps the old class one release as a
  subclass, so jobs already queued still run.
- **API responses** are jbuilder views under the plugin's `app/views/api/`;
  a controller renders JSON itself only for an error body. 
- **Views** follow the core's frontend rules (STYLE.md: Litewind's Tailwind
  classes and the core's `ui(...)` recipes and partials, strict locals, no
  inline styles); `bin/ci` lints `engines/` with Herb, and the classes spec
  checks a plugin's views as it does the core's. A plugin's stylesheet holds
  only what classes can't say.

## Registering

In the engine's `config.to_prepare` (re-run on every code reload, so it
replaces rather than duplicates):

    Cms::Plugins.register :hello, name: "Hello", version: "0.1.0", description: "…",
      author: "…", bundled: true, enabled_by_default: false,
      requires: ">= 1.0",          # core versions it runs on (VERSION)
      depends_on: [:forms],        # plugins that must be on too
      homepage: "https://…"

A plugin whose `requires` this version doesn't meet can't be switched on;
one whose `depends_on` aren't on is switched on but "waiting". Changes to
`engine.rb` need a server restart.

`adopt_if: -> { Form.with_discarded.exists? }` is for a feature moved out of
the core: while nobody has switched the plugin on or off, an install that
already holds its data gets it switched on (and saved as on), so an upgrade
never takes a feature away. A check that can't run yet — tables missing
while the database is being prepared — counts as no. Adopting a plugin also
switches on the plugins it `depends_on` that nobody has switched either.

## Extension points

| Call | Adds |
|---|---|
| `menu key, :id, label:, icon:, group:, path: -> { … }, capability:, after: :globals, group_after: "Content"` | A top-level item in the admin menu (WordPress's `add_menu_page`), with an `icon_tag` name, in a core group (`"Content"`, `"Insights"`, `"Tools"`, `"Access"`) or a new one, which `group_after:` places (else it goes last, before Settings). `after:` is the id of the item it follows; `:start` puts it first. The item goes to `path`, or to its first submenu link when `path` is nil. |
| `submenu key, :parent, label:, path: -> { … }, capability:, after: "Redirects"` | A link in a top-level item's submenu (`add_submenu_page`): a core item's (`:pages`, `:collections`, `:globals`, `:audit_log`, `:trash`, `:tools`, `:plugins`, `:users`, `:roles`, `:settings`; Media adds `:media`) or a plugin's own. `after:` is the label it follows. A plugin's settings page (`settings`) joins the Settings submenu by itself. |
| `new_item key, label:, path: -> { … }, capability:, after: "Global"` | An entry in the admin bar's "+ New" menu. |
| `slot name, key, "partial"` | A partial in a core view: `:nav_actions` (the admin bar, no locals), `:dashboard` (no locals), `:webhook_filters` (the webhook form, `webhook:`). |
| `settings key, label, -> { path }, description:, capability:, group: "Workspace", after: "Brand context"` | A page in Settings (under "Plugins" unless `group:` names another), linked from the plugin's card. Its controller inherits `Settings::BaseController`. |
| `permissions key, "Group", %w[key:read key:write], after: "Globals", defaults: {editor: […], author: […], site: […], agent: […]}` | Capabilities, offered in the role editor while the plugin is on and kept on roles while it's off; `defaults:` is what the built-in roles start with (`Permissions.defaults_for`) — on a fresh install seeded with the plugin on, or granted the first time someone switches it on (see below). |
| `counts key, after: :globals, things: -> { Thing.count }` | Counts in `/api/manifest`'s `counts` and the backup summary (`backup: false` for the manifest only). |
| `manifest_section key, :things, -> { […] }, after: :collections` | A top-level key in `/api/manifest`. |
| `trashable key, "thing", "Thing", label: "Things", meta: ->(r) { {slug: r.slug} }, after: "entry"` | A soft-deletable model the trash lists, restores and purges (`Trash`). |
| `hold_api_writes key, ->(write) { … }` | Holds content writes made over the API with a token (the CLI, MCP, a script) instead of applying them: creating, changing or deleting a page, entry or global. The lambda gets a `Cms::Plugins::HeldWrite` (`action`, `record` — unsaved for a create —, `attributes`, `prefix`) and returns what the API answers with 202, or nil to let the write through. While one is on, the bulk content endpoints refuse tokens (409). Approvals (`cms-plugins/approvals`) is the one that does. |
| `provide key, :name, -> { … }` | Something the core reads if a plugin supplies it (`Cms::Plugins.provided(:name)`, nil otherwise; a lambda is called): Site Health reads `:published_forms` and `:spam_protection` from Forms. |
| `stylesheet key, "key/name"` | A stylesheet from the engine's `app/assets/stylesheets`, on the pages that show the plugin: its own (its controllers' `plugin :key`), those rendering one of its slots (Media's picker in the content form), and every page when it has a `:nav_actions` slot in the admin bar. |
| `nightly key, -> { … }` | Work for `PluginsNightlyJob` (1am); a failure is logged and doesn't stop the others. |
| `minutely key, :name, -> { … }, every: 2` | Work for `PluginsMinutelyJob` (every minute), run on the minutes divisible by `every`; each task is named so one failing doesn't stop another. Keep it to enqueueing a job. |
| `bootstrap key, -> { … }` | What the plugin sets up on a site: run by `SiteBootstrap` on a fresh install while the plugin is on, the first time someone switches it on in Settings › Plugins, or by `plugins:settle` for a plugin that's on but was never set up (see below). Must be idempotent. |
| `api key, "/api/key/things", description:` | Lists an endpoint with the plugin in `/api/manifest` (`plugins`), where the CLI and agents find it. |
| `block_types key, [block type hashes], package: "@org/blocks"` | A block type pack, with the npm package holding its Astro components. |
| `field_type key, "type", validator: ->(value) { errors }, partial: "…"` | A field type for collection and page schemas. |
| `deploy_provider key, "provider_key", ProviderClass` | A way to rebuild the site (a `Deploys::Provider` subclass), offered in Settings › Deploy. |
| `update_strategy key, "via", -> { RunnerClass }` | Another way Settings › Updates can update the install (Update strategies, below). |
| `webhook_event_filter key, "thing.created", permit: ->(raw) { hash or nil }, validate: ->(value, errors) { … }, match: ->(value, payload) { bool }` | Per-event criteria a webhook stores in `event_filters[event]` (Forms narrows `submission.created` to chosen forms): `permit` is the only shape kept from submitted params, `validate` adds to the webhook's errors, `match` decides a delivery (value nil: no criteria). Pair it with a `:webhook_filters` slot for the form. |
| `webhook_events key, "Label", %w[thing.created thing.done], after: "submission.created", deploy: false` | Events the plugin announces (`announce("thing.created")` from a model that includes `Eventable`), in `Webhook.events` and `/api/webhooks`. A webhook may subscribe to any installed plugin's events, on or off; the webhook form offers only those of plugins that are on. `deploy: true` makes one schedule a site rebuild. |

A plugin's own Stimulus controllers live in the engine's
`app/javascript/controllers/<key>/` and load with the admin's: the engine adds
its `config/importmap.rb` (`pin_all_from … under: "controllers/<key>"`) to
`config.importmap.paths` and its `app/javascript` to `config.assets.paths`, and
the controllers are named `<key>--<name>`. Forms does this for its builder
(`forms--builder`).

The block type pack and field type registries are read-only so far: the core
lists them (`Cms::Plugins.enabled_block_type_packs` and friends) but doesn't
yet offer them anywhere.

The first time someone switches a plugin on in Settings › Plugins, the
built-in roles (Editor, Author, Production site, Agent) get the capabilities
its `defaults:` names that they don't hold yet, and the audit log records
`plugin.permissions_granted`. It never revokes, and it doesn't happen on a
later switch-on — so a capability someone took away stays away.

A plugin that starts on (Forms, Media) is set up with the roles on a fresh
install. One that arrives later — installed into a running site with
`plugins:install`, Settings › Plugins or `CMS_PLUGINS`, or adopted by an
upgrade — is set up by `bin/rails plugins:settle`, which runs after every
`db:migrate` and `db:prepare` (every way in ends with one): its bootstrap task,
its block types, and its `defaults:` for each built-in role that holds none of
its capabilities yet. Each plugin's setup runs once (Setting
`plugin_setups`), so the site's Production site token can read the forms a
plugin installed after it was issued.

`after:` puts an addition straight after the item it names (a menu item's id or a submenu label, a
permission group, a trash kind, a manifest key, a webhook event),
after earlier additions to the same place; without it, or when that item isn't
there, the addition goes last; `after: :start` puts it first. It keeps what people read — and what the API
returns — in the order it had before a feature moved into a plugin.

It may name another plugin's addition — the addition waits for it, so the
order plugins load in (alphabetically) doesn't matter — and may be a list, the
first one present winning: Commerce's permission group says
`after: ["Forms", "Globals"]`, so it follows Forms, or Globals when Forms is
off.

## Update strategies

Settings › Updates updates an install one of a few ways (`Upgrade.via`): the
core's `local`, `github` and `in_place`, or `manual`. A plugin adds another —
through a deploy tool the install runs under, say — with
`update_strategy :key, "via", -> { Runner }`. `CMS_UPDATES=via` picks it, and
a production install with `CMS_UPDATES` unset picks the first plugin
strategy whose runner says it's `configured?`.

A runner is a plain class. On the class:

- `label`, `description` — how Settings › Updates names it;
- `configured?` — whether this install is set up for it;
- `unavailable_reason` — why the button can't use it yet, or nil;
- `redeploys?` (optional) — true when it deploys a new image, so an in-place
  update that needs one goes through it.

`new(upgrade)` takes the Upgrade record, and the instance answers:

- `start` — ask for the deploy, keeping its handle in `upgrade.external_id`
  and a link in `external_url`;
- `check` — follow it, and `upgrade.fail_with(message)` when it fails;
- `timing_out_since` — when the clock started (nil while it's waiting on a
  person), and `where_to_look` — where to read why after a timeout;
- `follow_text`, `note` (optional) — the link's label and a line under it.

Raise a subclass of `Upgrade::Error` for an answer that fails the update.
The update succeeds when the install boots on the new version.

## The admin menu

The admin is laid out like WordPress's: the admin bar across the top, the
admin menu down the left in groups, the page beside it
(`NavigationHelper::ADMIN_MENU`, `layouts/shared/_admin_menu`). A plugin adds
to it the way a WordPress plugin does. `engines/hello` adds a top-level item
with its own submenu, a link in the core's Tools submenu, and a "+ New" entry:

```ruby
Cms::Plugins.menu :hello, :hello, label: "Hello", icon: "reaction", group: "Tools", after: :tools,
  path: -> { hello_greetings_path }, capability: "hello:read"
Cms::Plugins.submenu :hello, :hello, label: "Greetings", path: -> { hello_greetings_path }
Cms::Plugins.submenu :hello, :hello, label: "Settings", path: -> { hello_settings_path }, after: "Greetings"
Cms::Plugins.submenu :hello, :tools, label: "Hello greetings", path: -> { hello_greetings_path }
Cms::Plugins.new_item :hello, label: "Greeting", path: -> { hello_greetings_path(anchor: "new_greeting") }
```

The current item is the one whose links best match the page; it opens with
its submenu, and every other item's submenu flies out on hover and keyboard
focus. Everything shows only while the plugin is on and the role holds the
capability.

A plugin's screens use the same conventions as the core's:
`layouts/shared/page_header` (the title, its primary action beside it through
`content_for :page_actions`, then the notices), and for a list
`layouts/shared/status_links`, `layouts/shared/bulk_actions` (the "Bulk
actions" select, Apply, and the search box) and `layouts/shared/row_links`
(Edit | … | Delete under the title).

## Events

Everything goes out through `Event` (STYLE.md, Events). A plugin's model
includes `Eventable` and uses the same two calls the core does:

    invoice.track_event(:voided)       # an audit row, "invoice.voided"
    invoice.announce("invoice.paid")   # webhooks, subscribers, in-process

`track_event` rows land in the audit log with everyone else's; name the
action after the model (`eventable_prefix` to keep an older name). Announce
only events you've registered with `webhook_events`, or a `<kind>.created`
for in-process listeners.

Every recorded event is published in-process as `"event.cms"` with
`{action:, target:, particulars:}`. Every webhook event — `page.published`,
`page.updated`, `page.unpublished`, `page.deleted`, the same four for
`entry`, `global.updated`, and what plugins add with `webhook_events`
(Forms' `submission.created`, Commerce's `quote_request.created`,
`invoice.sent`, `invoice.paid`) — is published as `"<event>.cms"` with
`{event:, data:}` (`data` is the webhook payload). `page.created` and
`entry.created` are published the same way, with `record:` too. A
subscriber checks that its plugin is on:

    ActiveSupport::Notifications.subscribe("page.published.cms") do |event|
      next unless Cms::Plugins.enabled?(:hello)

      Hello::Greeting.record_publication
    end

## Testing

A bundled plugin's specs live with the core's
(`spec/requests/plugins/hello_spec.rb`); an installed one keeps its own in
its repository's `spec/`, written against the core's `rails_helper`, and they
run from the core checkout with the plugin in `plugins/`:
`bin/rspec plugins/forms/spec`. In either,
`switch_plugin :hello, on: true` turns one on for an example, and
`forget_plugin :key` removes a plugin a spec registered itself
(`spec/support/plugin_registry.rb`).
