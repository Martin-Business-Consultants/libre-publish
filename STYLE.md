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

### Styling: the admin's own CSS

The admin is drawn with its own small CSS library, written for this CMS:
`app/assets/stylesheets`, served as written (no build, no framework). The
markup names what a thing *is* (`panel`, `btn btn--primary`, `field`,
`data-table`); the stylesheets say how it looks. The look is the admin's
classic one (Fizzy's): ink grays, a gray menu and admin bar, hairlines, 3px
corners, semibold controls, the accent in blue until the branding sets a
primary color.

Layers, in the order they win (`_global.css`): `reset` (reset.css), `base`
(element defaults, base.css: body type, native form controls, focus rings),
`components` (everything else), `helpers` (helpers.css).

**The vocabulary.** Reach for these before writing a new class; each file's
header comment has the details.

- *Layout* (layout.css): `stack` (a column), `row` (a line that doesn't
  wrap), `cluster` (a line that wraps), `grid` with `grid--2|3|4` (columns
  from a breakpoint) or `grid--tiles`. A stack and a grid space their
  children 16px apart, a row and a cluster 8px; a modifier picks another
  step of the scale (`2xs|xs|sm|md|base|lg|xl`: 2, 4, 8, 12, 16, 24, 32px).
  layout.css defines the steps in use (`stack--2xs|xs|sm|md|lg`,
  `row--2xs|xs|md|base`, `cluster--xs|sm|md|base`, `grid--sm|md`): add a
  step to its line when a screen needs one. Alignment:
  `row--between|end|top|baseline`, `cluster--between|end|top`,
  `stack--start`.
  `with-sidebar` (main column + 20rem sidebar from 64rem; its first child
  is the main column, its last the sidebar; `with-sidebar--sticky`),
  `measure--sm|md|lg|xl` (max width; `measure--centered`), `divided`
  (hairlines between children).
- *Type* (type.css): `page-title`, `title`, `heading` (`heading--lg`,
  `heading--sm`), `eyebrow` (small caps over a group), `link`,
  `title-link` (a record's name that opens it), `code` (inline),
  `code-block` (`code-block--wrap`), `prose`.
- *Buttons* (buttons.css): `btn` (outlined), `btn--primary`, `btn--danger`
  (outlined red), `btn--destructive` (filled red, confirms a delete),
  `btn--plain`, `btn--sm`, `btn--icon`, `btn--block`.
- *Boxes* (panels.css): `panel` (`panel--padded`, `panel--scroll`,
  `panel__header`, `panel__footer`; a `<details class="panel">` stands its
  summary off its contents), `well`, `empty-state`, `details` (a `<dl>` of
  labels and values; `details--wide`).
- *Status* (badges.css): `badge` and `notice`, toned `--success`,
  `--danger`, `--warning`, `--info` (a badge without a tone is neutral).
  `status_tag` picks a badge's tone from its words.
- *Tables* (tables.css): `data-table` styles its own `<th>` and `<td>`;
  `data-table__check`, `data-table__num`, `data-table__empty`,
  `row-actions`.
- *Forms* (forms.css): `fields` (a form's fields, 20px apart), `field`
  (label, control, help; a text control in it fills its width), `label`
  (`label__required`, `label__note`), `help`, `field-error`, `choice` (a
  checkbox and its words; `choice--top`), `form-actions`, a `<legend
  class="label">` (spaced off its fieldset's contents),
  `input-with-icon` (`input-with-icon__icon`), `title-input`,
  `switch-field`/`switch`, `secret-field`. `settings_field` and
  `settings_switch` write fields for you.
- *Menus and dialogs* (menus.css, dialog.css): `menu`, `menu__item`,
  `popup` in a `popup-anchor`; `dialog` (`dialog--action`, `dialog--sheet`, `dialog--sheet-half`,
  `dialog__header`, `dialog__actions`).
- *Icons* (icons.css): `icon_tag "name"`, 1em unless sized
  `icon--xs|sm|md|lg|xl` (12, 16, 20, 24, 40px).
- *Helpers* (helpers.css), for text inside a component that the component
  doesn't decide: `text-ink|body|muted|faint|accent|danger`,
  `text-small` (12px), `text-large` (16px), `text-medium`,
  `text-semibold`, `text-mono`, `text-center|end`, `text-tabular`,
  `truncate`, `nowrap`, `break-all`, `grow`, `no-shrink`, `push-end`,
  `full-width`, `visually-hidden`, `contents`, `wide-only`.

**Rules.**

- **A look that repeats is a component.** When a screen needs something
  the vocabulary doesn't have, add a class for it (a BEM block named for
  what it is: `media-tile`, `media-tile__name`) to the stylesheet for that
  screen or, when it's general, to the library's file for its kind, and
  write it there in full. Don't stack helpers to draw it: helpers adjust a
  component, they don't build one.
- **No variant classes.** States and breakpoints (`:hover`, `:focus-within`,
  `[open]`, `@media (width >= 40rem)`) live in the component's rule, not
  the markup.
- **Only classes that exist.** `spec/architecture/css_classes_spec.rb`
  fails on a class nothing defines, on a variant class, and on a rule
  nothing uses (unless something else puts the class in the DOM:
  `BUILT_ELSEWHERE`, or `BUILT_ELSEWHERE_PATTERNS` for a family, like
  `icon--*` and Lexxy's). Class lists kept in a constant or variable are named
  `*_CLASSES`/`*_classes` so the spec reads them.
- **Everything respects Settings › Branding's color, type and surface.**
  Rules draw only with the tokens (`_global.css`), which the branding sets
  (`Branding#stylesheet`) and the dark theme re-points, so a rule written
  for the light theme reads in the dark one:
  - *Color*: `--gray-50…900` is the neutral, mixed from `--neutral-tint`
    (the secondary color tints it, faintly); `--surface` is the canvas.
    `--accent-50…900` is the primary color (blue until one is set), for
    primary buttons, links, focus, selection and what's current; words on
    an accent fill are `--on-accent`. `--red-*`, `--green-*` and
    `--yellow-*` are for status. No other color, no hex (except pure white
    or black on a photo).
  - *Type*: `--font-sans` (the branding's font) and `--font-mono`; sizes
    `--text-xs…3xl` with `--leading-*`, weights `--weight-*`.
  - *Space*: `--space-*` (`--space-4` is 16px; `--space-1-5` 6px).
  - *Surface*: corners `--radius-sm|md|lg|xl` (which the branding's
    corners set): `md` for controls, `lg` for notices and wells, `xl` for
    panels, menus and dialogs, `sm` for badges, `--radius-full` only for
    true circles. Shadows `--shadow-surface` (panels) and
    `--shadow-overlay` (menus, dialogs, sheets, toasts).
- **Don't give a display class to something a stylesheet shows and hides**
  (a `stack` on an element a rule sets `display: none`): let the
  stylesheet set its display.
- **Hooks**: keep a BEM class only while a stylesheet, JavaScript or a spec
  reads it; the classes spec reports one nothing reads.
- **Plugins** use the same vocabulary, and ship their own stylesheet for
  what's theirs (docs/plugins.md).
- Mailers keep their own inline styles: email clients don't load the admin's.

Screens follow WordPress's admin conventions:

- One primary action per screen, `btn btn--primary`; everything else is a
  secondary, outlined `btn`. A title row's "Add New" is secondary.
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
