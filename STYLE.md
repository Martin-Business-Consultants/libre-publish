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

### Styling: rune_ui

The admin is drawn with rune_ui, the UI kit Libre Publish shares with
Runwell and Botter (`vendor/rune_ui`, its README, copied in from
`../rune_ui` by `bin/sync-rune-ui`; never edit the copy). It brings the
shell (a sidebar on the page, the screen in an inset panel under a bar of
crumbs), components as helpers, plain CSS in the `rune` cascade layer and
Stimulus controllers named `rune-*`. The markup names what a thing *is*
(`card`, `btn btn--primary`, `field`, `table data-table`); the stylesheets
say how it looks.

The stylesheets, in the order `app_stylesheet_tags` loads them: rune_ui's
(all layered, so the app's always win), then the app's, unlayered:
`_global.css` (the palette and the branding contract), `_rune-theme.css`
(points rune's tokens at the palette), and `admin/*.css`: `base.css` (the
admin's additions to rune's vocabulary), `components.css` (its shared
pieces), `shell.css` (the shell's admin parts), `keyboard.css` (the row j / k
is on, the ? sheet, hint mode, page transitions), and one file per area of
screens (`editor.css`, `records.css`, `settings.css`, `media.css`…).

**The vocabulary.** Reach for these before writing a new class.

- *rune's helpers* (vendor/rune_ui/README.md): `button_link`,
  `action_button`, `icon_button`, `button_classes(variant:, size:)`
  (`:primary`, `:secondary`, `:ghost`, `:danger`; `:sm`), `card(title,
  hint:, actions:)`, `badge(text, label, tone:)`, `callout(text, tone:)`,
  `empty_state`, `menu { menu_link / menu_button / menu_label /
  menu_divider }`, `popover_menu` (in rows that scroll or clip), `tabs`,
  `settings_group` / `setting_row`, `switch`, `copy_button`, `avatar`. The
  admin's own: `icon_tag` (rune's icons, plus the admin's, registered in
  `config/initializers/rune_ui.rb`), `status_tag` (a badge toned by its
  word), `postbox`, `settings_field`, `settings_switch`, `secret_field`, and
  the partials in `layouts/shared` (page_header (actions: false on
  an index), list_toolbar (an index's one row: filters, search, New, and
  the bulk bar), row_actions (a row's last cell: edit, ⋯, delete, which
  fills in the page's one row_delete_dialog), delete_dialog, confirm_dialog,
  save_box, status_links, quick_filter, pagination, errors, editor_bar).
- *rune's classes*: `stack`, `grid-2`, `catalog`, `button-row`,
  `dot-list`, `dl.details`; `card` (`card__head`, `card__header`,
  `card__title`, `card__hint`, `card__content`, `card__footer`, `card--flush`,
  `card--muted`, `card--sm`); `btn` (always with a variant), `icon-button`,
  `pill`; `field` (`field__label`, `field__hint`, `field__error`),
  `field-row`, `checkbox`, `search`; bare inputs, selects and textareas
  need no class; `table` in a `table-wrap`; `badge`, `count`, `alert`,
  `empty`, `tabs`, `dialog` (`dialog__box`, `dialog__header`,
  `dialog__title`, `dialog__body`, `dialog__actions`), `sheet`, `menu`,
  `menu__items`, `menu__item`, `prose`; text: `muted`, `faint`, `small`,
  `nowrap`, `visually-hidden`.
- *The admin's* (admin/base.css, admin/components.css): `stack--xs|sm|md|lg`
  (4, 8, 12, 24px), `row` (a line that doesn't wrap; `row--between`,
  `row--top`), `grow`, `with-aside` (main column and a sidebar of
  boxes: `with-aside__main`, `with-aside__aside`), `measure`, `divided`,
  `bullet-list`, `code-block`, `mono`, `strong`, `tabular`, `truncate`,
  `contents`, `icon--xs|md|lg|xl`; list tables (`data-table` with
  `data-table__check|num|empty|actions`, `row-action`, `list-toolbar`,
  `pagination`), `postbox`, `save-box`, `editor-bar`, `switch-field`,
  `checkbox--top`, `secret-field`, `title-input`, `link-button--danger`.

**Rules.**

- **A look that repeats is a component.** When a screen needs something
  the vocabulary doesn't have, add a class for it (a BEM block named for
  what it is: `media-tile`, `media-tile__name`) to its area's stylesheet
  or, when it's general, to `admin/components.css`, and write it there in
  full. Don't stack utilities to draw it.
- **No variant classes.** States and breakpoints (`:hover`, `:focus-within`,
  `[open]`, `@media (max-width: 860px)`) live in the component's rule, not
  the markup.
- **Only classes that exist.** `spec/architecture/css_classes_spec.rb`
  fails on a class neither rune_ui nor the admin defines, on a variant
  class, and on an admin rule nothing uses (unless something else puts the
  class in the DOM: `BUILT_ELSEWHERE`, or `BUILT_ELSEWHERE_PATTERNS` for a
  family, like Lexxy's). Class lists kept in a constant or variable are
  named `*_CLASSES`/`*_classes` so the spec reads them. rune defines `panel`
  (the shell's panel) and a bare `btn` (no look without a variant), so the
  spec can't catch those used the old way: don't.
- **Space with `gap`, never sibling margins.** Herb can wrap output in
  `display: contents` elements, which `gap` sees through. No coloured edge
  stripes: states show as tints, weight, dots and badges.
- **Everything respects Settings › Branding and the dark theme.** Rules
  draw only with rune's tokens, which `_rune-theme.css` points at the
  palette that the branding sets (`Branding#stylesheet`) and the dark
  theme re-points: `--page`, `--panel`, `--layer-1..3`, `--text`,
  `--text-muted`, `--text-faint`, `--line`, `--line-strong`, `--hover`,
  `--accent` (`--accent-hover`, `--accent-ink`, `--accent-soft`),
  `--attention`, `--danger`, `--ok`; space `--s-1..6`; type `--text-xs`,
  `--text-meta`, `--text-ui`, `--text-read`, `--text-title`, `--weight`,
  `--weight-strong`, `--font-sans`, `--font-mono`; surface `--radius-*`
  (all multiples of `--radius-scale`, which the branding's corners set),
  `--radius-control`, `--radius-pill`, `--shadow-card` and
  `--shadow-popover` (which its shadow sets); sizes `--control-h`,
  `--control-h-sm`, `--row-h`. A palette step (`--gray-*`, `--red-*`,
  `--accent-*`…) only for a colour rune has no token for. No hex (except
  pure white or black on a photo).
- **Don't give a display class to something a stylesheet shows and hides**
  (a `stack` on an element a rule sets `display: none`): let the
  stylesheet set its display.
- **Keys are declared, not coded.** A control that has a key says so with
  `data-keys` (`"n"`, `"e"`, `"g p"`, `"mod+s"`; commas for alternatives),
  and the keyboard controller clicks it (or focuses it, with
  `data-keys-focus`); one inside the row j / k is on wins over the page's.
  A list row is `data-filter-target="item"`. A go-to chord belongs to its
  admin menu item (`NavigationHelper::ADMIN_MENU`'s `keys:`), and every key
  is listed in the ? sheet (`layouts/shared/_shortcut_list`). Esc goes up
  to the page `parent_page` names.
- **Hooks**: keep a BEM class only while a stylesheet, JavaScript or a spec
  reads it; the classes spec reports one nothing reads.
- **Plugins** use the same kit, and ship their own stylesheet for what's
  theirs (docs/plugins.md).
- Mailers keep their own inline styles: email clients don't load the admin's.

Screens follow WordPress's admin conventions:

- One primary action per screen, `btn btn--primary`; everything else is
  `btn btn--secondary` or `btn--ghost`. A title row's "Add New" is
  secondary. The page's title is in the panel bar (`layouts/shared/page_header`
  puts it there, after the page one level up that `parent_page` names).
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
