# Style

How code in this repo is written. The model is 37signals' Fizzy (its
`STYLE.md` and `AGENTS.md`), adapted to a CMS with
a public API, plugins and RSpec. When in doubt, find similar code here and
copy its shape. Reference implementations:

- **Page** (`app/models/page.rb`, `app/models/page/*`, `app/controllers/api/pages*`,
  `app/views/api/pages/*`, `spec/models/page/*`): a rich model in concerns, verbs
  that record events, thin admin and API controllers, jbuilder JSON.
- **Collection and CollectionEntry** (`app/models/collection/*`,
  `app/models/collection_entry/*`, `app/controllers/api/collections/*`,
  `app/views/api/collection_entries/*`): the same, for an aggregate of two
  models, with bulk verbs (`CollectionEntry.trash_all`, `.change_status_of`)
  that record what they found.
- **Invoice, in a plugin** (the Commerce plugin's repository:
  `app/models/invoice.rb`, `app/models/invoice/*`,
  `app/jobs/invoice/delivery_job.rb`): a plugin's model in concerns
  (`Deliverable`: `deliver_later`/`deliver_now`), with a shallow job named for
  its record.
- **Redirect** (`app/models/redirect/*`, `app/controllers/tools/redirects*`):
  a small aggregate, a plain object (`Redirect::Import`), CSV resources.
- **BlockType, Global and Asset** (`app/models/block_type/*`,
  `app/models/global/*`, `app/models/asset/*`, `app/models/bulk_upload/*`):
  plain objects nested under their model (`BlockType::Validator`,
  `BlockType::Defaults`, `Asset::Resolver`); a job's work moved onto the model
  so the job only calls it (`BulkUpload::Unpackable`, `BulkUpload::UnpackJob`);
  and two event vocabularies kept side by side where the API has always used
  its own (`BlockType::Tracked`).
- **The operational areas** (`app/controllers/api/{service_tokens,webhooks,
  deploys,trash,api_tokens}/*`, `app/models/trash.rb`, `app/models/deploys.rb`,
  `app/models/manifest.rb`): decisions that record themselves
  (`ServiceToken#reveal`), module-level verbs for things with no single record
  (`Trash.restore`, `Deploys.trigger_later`), and the manifest as a plain
  object the view renders.
- Fizzy: `app/models/card.rb` and `app/models/card/*`, `app/controllers/cards/*`,
  `app/models/concerns/eventable.rb`, `app/views/cards/*.json.jbuilder`.

`spec/architecture/*` enforces the structural rules below, with no
exceptions: no `app/services` anywhere, no `member`/`collection` routes, and
no hand-built success JSON in API controllers. A new exception means changing
the rule here first.

## Models

Behaviour lives on models. A controller calls an intention-revealing method
(`page.trash`, `page.update_schema(fields)`, `Page.change_status_of(pages, to:)`)
rather than a service.

- Split a model by what it does into concerns under `app/models/<model>/`,
  named for the capability they add: `Page::Publishable`, `Page::Treeable`,
  `Page::Trashable`, `Redirect::Matchable`. Each concern holds its own
  associations, scopes, callbacks and methods. One `include` per line: they
  register in order.
- Keep in the model file what depends on order across concerns
  (validations, in the order their errors are reported) and the model's
  external contract (webhook payload).
- A collaborator that isn't a record is a plain Ruby object in `app/models`,
  namespaced under what it serves (`Page::BlockExpansion`, `Redirect::Import`).
- There is no `app/services`, in the core or in a plugin. An orchestrator
  with no record of its own (`Upgrade::Github`, `Deploys`) is a plain object
  in `app/models` like any other; an HTTP client is one too, as in Fizzy's
  `Webhook::Delivery`.
- A behaviour two records share, where neither owns it, is a concern in
  `app/models/concerns` named for what it adds (`Sitemapped` for pages and
  entries). A question asked of a whole table is a class method on a
  concern of that model (`CollectionEntry.trash_all`).
- Callbacks are for derived data and fan-out only: paths, search index,
  references, versions, webhooks. A business action is an explicit method
  someone calls.

## Events

Everything that happens goes out through `Event` (`app/models/event.rb`),
Fizzy's Event with two kinds, one per audience. A model reaches both through
`Eventable`:

```ruby
def trash
  track_event(:deleted, path: path, status: status)   # who did what
  discard!
end

announce("invoice.paid")                               # what changed, for subscribers
```

- **`track_event`** records something a person or token did. It writes the
  audit row (`"page.deleted"`: the model's `eventable_prefix`, then the
  action) attributed to `Current.actor` with the request's address and user
  agent, adds `via: "api"` on `/api` requests, and publishes `"event.cms"`
  in-process. Every write through the admin or the API records one.
  `Model.track_event` records an event about a set of records (a bulk
  change), naming the records it found, not the ones it was asked for.
  `Event.record("settings.brand_updated", …)` is for events about no
  record. Record before a destructive change, so the row names the record
  as it was; a verb records its own event (`invoice.void!`,
  `webhook.regenerate_secret!`), and for plain CRUD the controller calls
  `record.track_event` after the save.
- **`announce`** publishes a state change in the webhook vocabulary
  (`page.published`, `submission.created`): in-process as
  `"<event>.cms"`, to every webhook that wants it
  (`Webhook.deliver_later` → `Webhook::DeliveryJob` → `deliver_now`), to the
  record's own subscribers (`notify_subscribers`, a collection's emails) and
  to the deploy hook. Content models announce from `Announceable`, which
  works the transition out from what the save changed, so no path that
  saves a record can forget to.

The audit log and the webhooks are two vocabularies on purpose: one
editorial action can announce several transitions (a bulk publish), and an
announcement can have no person behind it (the scheduler, a visitor's form
submission).

Within the audit log there is **one vocabulary**: an act is recorded under
the same action and the same metadata whether the admin or the API did it,
and only `via: "api"` tells them apart. Name actions `<model>.<past-tense
verb>` (`block_type.deleted`, `asset_folder.renamed`,
`site_backup.exported`), and record through the model's verb so both routes
share it (`Deploys.configure`, `CollectionEntry#place_on_board`,
`ReviewRequest.summary_of`). Keep actions and metadata stable once
recorded: `/api/audit_log` shows them. When one must change, add the old
name to `AuditLog::FORMER_NAMES`, so filtering by the new name still finds
older rows and the admin shows them under it; old rows are never rewritten.
Webhook names and payloads are a contract with every receiver and never
change.

## Controllers

- CRUD only. A verb that isn't CRUD becomes a resource of its own:
  `resources :bulk_deletions` rather than `post :bulk_destroy`,
  `resource :schema` rather than `patch :update_schema`. The API keeps its
  URLs by routing an old path to the new controller
  (`post "pages/bulk_destroy", to: "pages/bulk_deletions#create"`).
- Thin: load, authorize, call the model, render. Plain Active Record calls
  are fine (`@page.update!(page_params)`).
- A controller nested under a record loads it through a `<Model>Scoped`
  concern (`PageScoped`; in the API, `Api::WebhookScoped`,
  `Api::ServiceTokenScoped`, `Api::TrashScoped`). A lookup that fails with a
  JSON body (an unknown trash kind, an unknown recipe) renders it in the
  concern's before_action.
- Every action declares its capability (`requires_capability "pages:write",
  only: …`); authorization fails closed.

## JSON and the API

- JSON is built in jbuilder views under `app/views/api/<resource>/`, with a
  partial per shape (`_page`, `_summary`). Controllers `render json:` only
  for error bodies (`{error: …}`), with `error:` on the render's first line.
- List keys in `json.extract!` in the order the old `as_json(only: [...])`
  listed them: that list set the order the API has always answered in.
- Jbuilder encodes like `render json:` (config/initializers/jbuilder.rb):
  "&", "<" and ">" come out as themselves, not `\u0026`. Without it any text
  with those characters changed bytes the moment its endpoint moved to a view.
- An error body the contract starts with another key (device login's
  `{status: "error", error: …}`) is a view too (`api/device_authorizations/error`).
- Don't name a partial's local `collection:` (or `as:`): jbuilder reads
  either as "render once per item". The collection partial takes `record:`.
- `/api` is its own namespace with a frozen contract: the Astro sites, the
  `cms` CLI, integrations and agents read it. Before changing anything an endpoint
  touches, snapshot its responses (status, body, the `X-Agent-Envelope: 1`
  variant, error cases, and the audit rows and jobs a write leaves) under
  frozen time, and diff after. They must come out byte-identical.
  `spec/contracts` and `spec/cli` must stay green unchanged.

## Jobs

Shallow jobs that call a model method, namespaced by model
(`app/jobs/<model>/`). A method that enqueues is `foo_later`; when the job
calls back into the same class, the synchronous method is `foo_now`.

## The app

- **Libre Publish lives under `/cms`; `/` is the website.** Always. Every
  admin route goes inside `scope path: Cms::PATH` in `config/routes.rb`, a
  plugin's inside the same scope in its engine, and links come from route
  helpers, never a written `"/pages"`. Only what sites, the CLI and
  integrations call sits at the root: `/api`, `/agent`, `/frontend`,
  `/sitemap.xml`, `/up`, and the website's own addresses (a theme's,
  docs/themes.md).
- **One install per site.** No tenancy. `Site.key` and `Site.host` come from
  the environment.
- **`Current`** holds the request's user, session, token, address and user
  agent; models read it (`Current.actor`), controllers set it.
- **Plugins** are engines (`docs/plugins.md`): `engines/hello`, the
  reference, ships with the core; the rest are installed into `plugins/` from
  their own repositories. The core never names a plugin: it offers
  registries (menu, slots, settings, permissions, events, …) and plugins
  register into them.
- **One gate: anything in front of visitors takes the publish capability.**
  Changing a live record (a published page or entry, or any global), or
  publishing or scheduling a draft, needs `<resource>:publish`; the record
  answers (`PublishGated#publishing_write?`, asked after the attributes are
  assigned). Without it the write is refused, not queued: the admin's
  `ContentEditing` adds an error and re-renders, the API's
  `Api::PublishCapability` answers 403. Any new write path that can change a
  live record, `status` or `publish_at` asks the same question.

## Views

ERB with Herb/ReActionView, Stimulus and Turbo, no build step.
`bundle exec herb lint app/views engines` must pass. Every partial declares
strict locals; no ERB output in attribute names; no inline styles.

### Styling: Runwell UI

The admin is drawn with **Runwell UI**, a no-build port of
[shadcn/ui](https://ui.shadcn.com) in plain CSS, copied as written from
Runwell (`app/assets/stylesheets/ui/{tokens,button,badge,card,forms,overlays,display,data-table,styleguide}.css`,
`app/javascript/controllers/ui/*`, `app/helpers/ui_helper.rb`,
`app/views/ui/_data_table*`). Served as written: no build, no framework.
The styleguide at `/cms/ui` (development) shows every component; open it
before drawing a screen. The look is shadcn's, not the admin's old one: build
new markup from the kit, and move markup you touch onto it.

Layers, in the order they win (`_global.css`): `reset` (reset.css), `base`
(element defaults: body type, native controls, focus rings), `components`
(the admin's own pieces the kit has nothing for: layout.css, the editors,
the file manager, Lexxy), `ui` (the kit, and the admin's chrome drawn with
it, `ui/app*.css`), `helpers` (helpers.css).

**The kit.** Components are `ui-` classes under shadcn's names and variants.
Reach for these before writing a class:

- `ui-button` (`--secondary`, `--outline`, `--ghost`, `--link`,
  `--destructive`; `--sm`, `--lg`, `--icon`, `--icon-sm`, `--icon-lg`,
  `--block`), `ui-button-group`; `ui-badge` (`--secondary`, `--outline`,
  `--destructive`, the status tones `--positive|warning|info|negative|neutral`,
  `--count`).
- `ui-card` (`__header`, `__title`, `__description`, `__action`,
  `__content`, `__footer`; `--flush` for a table edge to edge, `--sm`).
- Forms: `ui-field` (`--inline` for a checkbox, radio or switch beside its
  words, `--end`, `--card`), `ui-label`, `ui-input` (`--sm`), `ui-select`,
  `ui-textarea`, `ui-checkbox`, `ui-radio` in a `ui-radio-group`,
  `ui-switch` (a checkbox with `role="switch"`), `ui-field__description`,
  `ui-field__error`, `ui-fieldset`, `ui-field-row`, `ui-input-group`
  (`__addon`).
- Overlays, on native elements: `<dialog class="ui-dialog">` (`--sm`,
  `--lg`; `__header`, `__title`, `__description`, `__footer`, `__close`),
  `<dialog class="ui-sheet">` (`--left`), a `popover` `ui-menu`
  (`__item`, `__item--destructive`, `__label`, `__separator`, `__shortcut`)
  or `ui-popover` placed by the `ui--popover` controller, `ui-tooltip`,
  `ui-toaster`/`ui-toast`.
- Display: `ui-table` (`__numeric`, `__row-link`) in a
  `ui-table-container`, `ui-tabs` (links with `aria-current`, or state with
  `aria-pressed`; `--line`, `--icons`), `ui-alert` (`--destructive`,
  `--warning`, `--success`), `ui-avatar`, `ui-separator`, `ui-skeleton`,
  `ui-kbd`, `ui-progress`, `ui-breadcrumb`, `ui-empty`, `ui-item` in a
  `ui-item-group`.
- `UiHelper` spells the common ones: `ui_button`, `ui_link_button`,
  `ui_button_classes` (for `link_to`, `button_to`, `form.submit`),
  `ui_badge`, `ui_status_badge` (a status in its tone), `ui_kbd`,
  `ui_avatar`.
- Index tables are the **data table**: `render "ui/data_table", id:,
  columns:, rows:, row:, as:, pagination:, selectable:, actions:, empty:`,
  the columns described with `ui_column(key, label, align:, hideable:)`.
  The row partial renders `ui_select_cell` first when selectable, a
  `<td data-column="key">` per column, then `ui/row_actions` when actions.
  It brings the checkbox column for bulk actions, a Columns menu that hides
  columns (per browser) and the pages underneath.
- Native elements over JavaScript: `<dialog>`, the `popover` attribute,
  `<details>`, real checkboxes and radios. A component's CSS uses
  descendant or class selectors, not child ones: in development
  ReActionView wraps every ERB output in a `display: contents` span.

**The admin's own pieces.** What the kit has no component for is drawn in
`ui/app*.css` (the sidebar, the inset header, page headings, the settings
layout, the editors' boxes…) as shadcn would draw it, from the kit's
tokens, as a BEM block named for what it is: `ui/app.css` the shared ones
(`fact-list`, `bullet-list`, `secret-field`, `delete-link`, `table-pagination`,
`app-sheet--md|wide` for a sheet wider than the kit's), `ui/app-shell.css` the
frame, and `ui/app-lists|settings|editor|media|dashboard|public|tools.css` a
screen each. Layout is layout.css's:
`stack` (a column), `row` (a line that doesn't wrap), `cluster` (a line that
wraps), `grid` (`grid--2`), each spaced 16px or 8px
apart unless a step says otherwise (`2xs|xs|sm|md|base|lg|xl`: 2, 4, 8, 12,
16, 24, 32px; layout.css defines the steps in use), with `row--between|
baseline`, `cluster--top`, `stack--start`, `with-sidebar` (main column +
sidebar from 64rem), `measure--lg|xl`. Helpers
(helpers.css) adjust text inside a component that the component doesn't
decide: `text-muted|danger`, `text-small`, `text-medium`,
`text-semibold`, `text-mono`, `text-tabular`,
`truncate`, `nowrap`, `grow`, `push-end`, `visually-hidden`…

**Rules.**

- **A look that repeats is a component.** Use the kit's; when a screen
  needs something it doesn't have, add a class to `ui/app-<area>.css`,
  written in full from the kit's tokens. Don't stack helpers to draw it, and
  don't edit the kit's own files: they stay as Runwell has them.
- **No variant classes.** States and breakpoints live in the component's
  rule, not the markup.
- **Only classes that exist.** `spec/architecture/css_classes_spec.rb`
  fails on a class nothing defines, on a variant class, and on a rule
  nothing uses (unless something else puts the class in the DOM:
  `BUILT_ELSEWHERE`, or `BUILT_ELSEWHERE_PATTERNS` for a family). Class
  lists kept in a constant or variable are named `*_CLASSES`/`*_classes` so
  the spec reads them; `UiHelper::BUILT_CLASSES` lists the variants its
  builders write.
- **Everything is drawn from the kit's tokens**, which Settings › Branding
  reaches: shadcn's names (`ui/tokens.css`) — `--background`,
  `--foreground`, `--card`, `--popover`, `--primary`,
  `--primary-foreground`, `--secondary`, `--muted`, `--muted-foreground`,
  `--accent`, `--destructive`, `--success`, `--warning`, `--info`,
  `--border`, `--input`, `--ring`, `--sidebar*`, `--radius-sm|md|lg|xl`,
  `--shadow-xs|sm|md|lg`, `--ring-focus` — and the type steps
  `--text-x-small|normal|medium|large…`. They're built from the theming
  tokens in `ui/theme.css` (`--lch-*` OKLCH triples, `--radius-scale`,
  `--radius-control`, `--font-sans`), which `/branding.css`
  (`Branding#stylesheet`) sets and the dark theme re-points, so a rule
  written for the light theme reads in the dark one. No other color, no hex
  (except pure white or black on a photo). A tint is a `color-mix()` of a
  token (`color-mix(in oklch, var(--primary) 10%, transparent)`); against
  the card or the page mix in srgb, since their white has no hue and an
  oklch mix swings toward pink.
- **Don't give a display class to something a stylesheet shows and hides**:
  let the stylesheet set its display.
- **Hooks**: keep a BEM class only while a stylesheet, JavaScript or a spec
  reads it.
- **Plugins** use the same kit and ship their own stylesheet for what's
  theirs (docs/plugins.md). The admin's old classes (`btn`, `panel`,
  `field`, `data-table`…) are kept, drawn with the kit's tokens, only in
  `legacy.css`, for plugins written before the kit (its header lists them).
  Nothing in this repository may write them: the classes spec fails on one
  in `app/` or `engines/`, and doesn't ask that they be used.
- Mailers keep their own inline styles: email clients don't load the admin's.

Screens follow shadcn/ui's layouts, with WordPress's editing conventions:

- The frame is shadcn's sidebar layout (`layouts/application`): the sidebar
  (`layouts/shared/_sidebar`, NavigationHelper#admin_menu; plugins' items join it) and the
  page as an inset sheet under its header (`_inset_header`: the toggle, the
  breadcrumb from the menu item, `parent_page` and `@page_title`, search as a
  command dialog). A screen opens with `layouts/shared/page_header`.
- A list is the data table (`render "ui/data_table"`, pages/index the
  reference): filters (`_status_links`, `_quick_filter`) in a
  `list-filters` line, the toolbar (`_bulk_actions`: search on the left, bulk
  actions on the right) and the table inside one `select-all` controller,
  each row ending in `ui/row_actions`.
- Settings is shadcn's settings layout (`layouts/settings`): its sections down
  the left, the page's cards in the middle, the Save box beside them.
- One primary action per screen, a filled `ui-button`; everything else is
  `--outline` (or `--ghost` in a row or a toolbar). A title row's "Add New"
  is outlined.
- Editors (pages, entries, globals) put the title and permalink first and
  the content in the main column, with a sidebar of boxes
  (`content_form_helper#postbox`) led by the Publish box
  (`content_form/_publish_box`): Save Draft, Status/schedule lines with an
  Edit, Move to Trash, and the primary Publish / Update (none for a role
  that can't publish).
- A delete dialog inside another form takes `form:` and a
  `layouts/shared/delete_form` rendered after that form. Forms can't nest,
  and a nested form's `_method=delete` would join the outer one.

## Ruby

- Prefer expanded conditionals over guard clauses, except a guard at the top
  of a non-trivial method.
- Order methods: class methods, then public (`initialize` first), then
  private; within each, in the order they're called.
- `!` only for a method that has a counterpart without it
  (`update_schema` / `update_schema!`), never to flag something destructive.
- RuboCop (`bin/rubocop`) is the formatter's word: no blank line after
  `private`, and methods under it are not indented.

## Tests

RSpec with factory_bot. Model specs per concern (`spec/models/page/*_spec.rb`)
for verbs and events; request specs for controllers, HTML and JSON; contract
specs for the API. A structural rule gets an architecture spec.
