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
