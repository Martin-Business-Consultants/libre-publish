# Local development

Working on a site's theme on your own machine, against the site's real
content, then shipping it. Three pieces, each one command:

| | |
| --- | --- |
| The CMS | this repository, running with `bin/dev` |
| The content | `bin/pull`: a copy of the live site's pages, entries, globals, forms, settings and images |
| The theme | its own repository, beside this one, linked in with `bin/theme` |

Data only ever flows **down**: a pull reads the live site and never writes
to it, and nothing local is pushed back over it. Content goes up the way it
always does: edited in the live site's admin, or proposed through its API
(by an agent, say), where Approvals holds it for a person.

## Set up

```sh
git clone https://github.com/Martin-Business-Consultants/libre-publish
cd libre-publish
mise install
bin/setup                      # gems, a database with sample content
```

## Pull the live site

```sh
bin/pull production            # a cms CLI profile: ~/.config/cms/production.env
bin/pull --url https://cms.example.com --token TOKEN
```

The token's role needs `tools:use` (an admin's does): the pull downloads the
site's backup (Tools › Backup), keeps it in `tmp/pulls/`, and puts it in
place of your local database and files. This machine's previous database is
kept beside it (`storage/development.sqlite3.before-import-…`). Pulling again
replaces the copy with a fresh one.

The copy is made safe to work on:

- **Nothing reaches the outside world**: webhooks are switched off, the
  deploy and GitHub settings are dropped, IndexNow is off. Email in
  development opens in the browser (letter_opener) instead of sending.
- **Addresses are local**: Settings › General's site URL is
  `http://localhost:3000`.
- **You can sign in** as `local@localhost` / `password1234`, an admin. The
  site's own accounts work too, with their passwords.
- **Secrets stay behind**: API keys and tokens stored encrypted on the live
  site can't be read here. Enter any you need locally.

`--without-people` leaves out everyone's accounts, form submissions and API
tokens, for a copy with no one's personal details in it: use it whenever
the content is all you need. `--file tmp/pulls/….tar.gz` imports a backup you
already have.

## Work on the theme

A theme lives in its own repository. Start one from the starter, or bring
the site's:

```sh
bin/theme new acme                      # ../acme-theme, from the starter, linked
bin/theme link ../healing-theme         # a theme you've cloned
bin/theme list
bin/theme unlink acme                   # back to what the install had
```

Linking puts the theme in `themes/` as a link to where it is, and switches
it on (and any other theme off) in your local database. Restart `bin/dev`
once to load it; after that, templates, helpers and CSS reload as you save.
Theme guide: [Themes](themes.md).

What to check before you ship:

- **Every page renders**: open the site, and the pages `/llms.txt` lists.
- **Preview and inline editing**: open a page in the admin's Preview tab
  and edit some text in place; the theme's markup decides what can be
  edited.
- **Customize**: change the design settings in Settings › Themes ›
  Customize and see the site follow.
- **SEO**: Tools › SEO audit, and the page source's `<head>`.
- **Its spec**: `bin/rspec themes/<name>/spec` runs the theme's own tests
  inside the CMS.

## Ship it

1. Bump `lib/<theme>/version.rb`, commit, tag `v<version>` and publish a
   GitHub release.
2. On the live site, Settings › Themes shows the new version after the
   daily update check (or at once: Settings › Updates › Check now). Press
   Update. The CMS installs that
   release and restarts; if it won't load, the previous one runs again.

A site whose theme came with its image (`CMS_THEME` at a Docker build)
updates the same way, from Settings › Themes.

## Working on the CMS itself

The same pull gives a plugin or a core change real data to run against.
`bin/ci` runs everything CI does. Plugins link in the same way themes do:
`ln -s ../../cms-forms plugins/forms`, then restart.
