# Compatibility

A plugin, theme or API client written for Libre Publish 1.x keeps working
on every later 1.x. That is the promise this page spells out: what is
covered, how something is retired, and how the promise is checked.

## Versions

Releases follow [Semantic Versioning](https://semver.org): `MAJOR.MINOR.PATCH`.

- **Patch** (1.9.1): fixes. Nothing public changes.
- **Minor** (1.10.0): additions. Something public can be deprecated, but it
  keeps working.
- **Major** (2.0.0): the only release that removes or changes something
  public, and only what was deprecated during the previous major's life.

Data is never broken by any release: migrations only move forward, and an
update backs up the data directory before it migrates (docs/install.md).

## What is public

| Surface | Where it's described | Checked by |
| --- | --- | --- |
| The plugin API: `Cms::Plugins.register`, `menu`, `slot`, `permissions` and the other registrations | docs/plugins.md | `spec/contracts/public_api_spec.rb` |
| The theme API: `Website.register`, `Website.render`, and the `website_*` helpers | docs/themes.md | `spec/contracts/public_api_spec.rb` |
| `Cms.version`, `Cms.data_dir`, `Cms::PATH` | `lib/cms.rb` | `spec/contracts/public_api_spec.rb` |
| The REST API: every core route under `/api/` | docs/delivery-api.md, docs/agent-interface.md | `spec/contracts/public_api_spec.rb` (routes), request specs (payloads) |
| Webhooks: events, envelope, signature, payload keys | docs/webhooks.md | `spec/contracts/webhook_contract_spec.rb` |
| The delivery API's answers, headers and schema digest, and webhooks' and purges' signatures, as the Go core's contract has them (what @librepublish/astro holds a site to) | docs/delivery-api.md, `spec/fixtures/contracts/go` | `spec/contracts/delivery_contract_spec.rb` |
| Content events: `<event>.cms` notifications | docs/plugins.md | plugin specs |
| The admin's URLs under `/cms` | | redirects kept for moved ones (`/admin` → `/cms`) |

The full list of Ruby methods and routes is
`spec/fixtures/contracts/public_api.json`, generated from
`Cms::PublicApi`.

Anything not listed is internal, even if a plugin can reach it: models'
own methods, controllers, the admin's markup and CSS classes, and database
tables. A plugin that needs one asks for it to become public.

### What counts as a break

For a Ruby method, whatever turns a call that worked into one that fails:

- removing it;
- a new required argument or keyword;
- a keyword or positional argument it no longer takes.

An optional argument, an optional keyword, or a new method is an addition.

For the REST API: removing a route, removing a key from a response,
changing a key's type or meaning, or newly requiring a parameter. New
routes, new response keys and new optional parameters are additions, so a
client ignores keys it doesn't know.

## Retiring something

1. Deprecate it in a minor release. It keeps working, and each use warns
   through `Cms.deprecator`, naming what to use instead and the major
   version that removes it:

   ```ruby
   Cms.deprecator.warn("Cms::Plugins.old_thing is going in 2.0; use new_thing")
   ```

   Warnings are logged in development and printed in a test run, so a
   plugin's own suite shows them. The CHANGELOG lists every deprecation.
2. Remove it in the next major release, never sooner, and never less than
   six months after the deprecation shipped.

### The delivery API and the Go core's contract

The delivery API (`/api/v1`) answers the Go core's contract as well as its
own: what the contract has and this CMS didn't is added beside what it had,
never in its place. Where the two named the same key differently, both are
sent (`/sitemap`'s `loc` and `url`, an alternate's `hreflang`/`href` and
`locale`/`url`, SEO's `canonical_url` and `canonical`), and where they shaped
the same key differently, the old shape's keys stay inside the new one
(`/api/v1/schema`'s parts are JSON Schemas carrying the old `title`,
`enable_blocks`, `frontmatter` and `data` as annotations, beside the old
`block_types`). Those old keys are deprecated in 1.34 and go in 2.0
(docs/delivery-api.md lists them).

`spec/contracts/delivery_contract_spec.rb` checks it, against the copy of the
Go core's recorded answers in `spec/fixtures/contracts/go`: a key the
contract has that this CMS doesn't send fails, and so does a key this CMS
sends that the contract doesn't, unless the spec lists it as this CMS's own
(`RAILS_ONLY`) — @librepublish/astro refuses keys it doesn't know. When the Go
core's contract moves, `bin/contracts-sync ../librepublishgo` copies and pins
it, and the spec says what to follow.

Data isn't a key: the delivery API sends a record's frontmatter, block data,
global data and SEO with only what `/api/v1/schema` declares (as that schema
always said, `additionalProperties: false`), so a value stored under a
field since removed stops being delivered. It stays in the record and in
`/api`.

## Plugins and newer or older cores

- A plugin states the cores it works with: `requires: ">= 1.10"` in its
  `register`. Settings › Plugins won't switch on one whose requirement isn't
  met, and says why.
- A plugin made for a newer core that passes `register` a keyword this core
  doesn't know still loads: the keyword is left out and logged.
- A plugin that wants a newer feature without requiring the newer core
  checks for it: `Cms::Plugins.respond_to?(:tables_of)`, or
  `defined?(Cms::PATH)`.

## How it's checked

`spec/contracts/public_api_spec.rb` compares the public API with its
snapshot on every CI run:

- a break fails. Deprecate instead.
- an addition fails until it's written into the snapshot with
  `bin/rails cms:public_api`, so nothing becomes public by accident. The
  task refuses to write a breaking snapshot unless `BREAKING=1` is set, which
  only a major release does.
