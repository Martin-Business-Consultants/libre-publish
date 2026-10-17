# Libre Publish

A headless CMS built on Rails: an admin that edits like WordPress, a JSON API
that does everything the admin does, a `cms` CLI and MCP surface for AI
agents, and plugins. One install is one site, in one container, with SQLite
for everything. Sites render the content with any frontend, starting with
Astro: the `@librepublish/astro` integration
([libre-cms-astro](https://github.com/Martin-Business-Consultants/libre-cms-astro)) reads
the delivery API (`/api/v1`, docs/delivery-api.md). Or the CMS draws the site
itself, from a theme: plain ERB and CSS, no build (docs/themes.md).

```sh
mise install      # ruby 4.0.6
bin/setup         # gems, databases, seeds, then bin/dev
                  # http://localhost:3000, sign in as alice@site.test / password1234
bin/ci            # rubocop, herb lint, bundler-audit, brakeman, rspec, seeds
```

- `docs/install.md`: running your own, with Kamal (or a tool that runs it) or as a plain
  checkout, and updating it.
- `docs/plugins.md`: extending it. `engines/hello` is the reference plugin;
  Forms and Commerce are installed from their own repositories.
- `docs/vision.md`: what it is for and how it is put together.
- `docs/agent-interface.md`: the API, CLI and MCP surface agents use.
- `CHANGELOG.md`: every release.
- `go/`: the Go core, the same CMS as one file (API, admin, SQLite, WebAssembly
  plugins), checked against this core's contracts. See `go/README.md`.

Releases are `vX.Y.Z` tags at
https://github.com/Martin-Business-Consultants/libre-publish/releases; an install
offers each one in Settings › Updates.

Licensed under the Functional Source License (FSL-1.1-MIT, `LICENSE.md`): use
it, change it and run it for yourself or your clients, but not to offer a
competing product. Each release becomes MIT two years after it's published.
