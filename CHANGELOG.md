# Changelog

Every release of the CMS, newest first. The version lives in `VERSION`;
releases are git tags (`v1.0.0`) with a GitHub release whose notes are the
section below. An install is brought to one with `bin/update v1.0.0`, or a
Kamal site with `kamal deploy -d <site>`. Settings shows when a newer one is
out.

## 1.20.4

### Fixed
- **Media's grid view** drew its pagination inside the grid, squeezed into
  a tile's cell beside the last image. It's a row of its own under the grid
  now, as under a table.

## 1.20.3

### Fixed
- **The Scripts global took the website down.** Adding any script (an
  analytics tag, a chat widget) to Globals › Scripts made every page of a
  theme's website answer with an error, because the scripts were read for an
  "enabled" field the global doesn't have. They're read as stored now: each
  one's Head goes at the end of `<head>`, its Body just before `</body>`,
  and one set `"enabled": false` over the API is left out.

## 1.20.2

### Changed
- **A proposal that couldn't be applied is refused when it's made.** With
  Approvals (or any plugin that holds API writes) on, a token's write is
  now checked the way a direct one is before it's held: one the record
  wouldn't take (no title, a bad slug…) answers 422 with the errors, so the
  agent fixes it at once instead of a person finding out at Approve.

## 1.20.1

### Added
- **Clear failed updates**: a button beside Settings › Updates' Past updates
  and Settings › Plugins' Recent changes, when any failed, that takes the
  failed ones out of the list (after asking). What succeeded, and anything
  running, stays. Admins only.

## 1.20.0

### Fixed
- **The logo in emails**: it was a link to the image on the CMS, which many
  mail clients don't load (Outlook, Apple Mail and Gmail settings that block
  remote images), so it showed broken. Emails now carry Settings ›
  Branding's logo inside the message (an inline attachment), so it shows
  everywhere. A WebP or very large logo goes as a PNG of it; an SVG, which
  few mail clients draw, is left out.

### Added
- **A logo on every email**: password resets and email verification have
  the logo on top too, not only collection notifications. The Forms plugin
  (1.3.0) uses the same logo, and a theme's email design marks where it goes
  with `data-cms-logo`.

## 1.19.0

### Changed
- **Updates without downtime** (docs/install.md, Without downtime). A Docker
  install runs Puma itself (`bin/web`) with two workers, restarted one at a
  time:
  - **plugins and themes** go live without a pause: their migrations run,
    then the workers restart onto them one by one while the other serves;
  - **the CMS, updated in place**, is backed up and migrated with the new
    release while the running one serves, then the workers move onto it.
    A release whose workers don't come up within five minutes is switched
    back. One that needs another Ruby or Puma restarts the container as
    before.
  Tested under load in production mode: 11,205 requests during a switch,
  none failed.
- **Background jobs** run beside the workers (when `SOLID_QUEUE_IN_PUMA`)
  and restart onto new code with them.
- The image's command is now `./bin/thrust ./bin/web`. An image built
  before this keeps restarting the container to update.

## 1.18.6

### Added
- **Search in a modal**: the admin bar's search (or ⌘K / Ctrl+K) opens a
  box over the page, half the window each way. Results come as you type,
  from the first letter: titles match fuzzily ("hmpg" finds "Home page",
  the matched letters marked), then records whose text holds the term. The
  arrow keys and Enter open one; "All results" goes to the Search screen.
- **Update progress**: while a CMS update or a plugin or theme install,
  update or removal runs, every admin page shows a modal with a spinner and
  a progress bar for each, through the restart. When it's done, a Settings
  page reloads and any other closes it; one that fails says why.

## 1.18.5

### Added
- **A dark top bar** (Settings › Branding › Color › Top bar): the bar
  along the top of the admin stays dark in light mode too, for a logo drawn
  for a dark ground.

### Fixed
- **The agent installer on a Mac** (`curl …/agent/install.sh | sh`) failed
  without a recent Ruby. A Mac's own Ruby is 2.6, too old for the `cms` CLI,
  and a mise, rbenv or asdf shim can be on PATH with no Ruby behind it. The
  installer now runs each Ruby it finds before using it, and when none is
  3.4 or newer it fetches a self-contained one into `~/.local/share/cms`
  (Homebrew's portable Ruby, checked against its checksum; no Homebrew or
  admin rights needed). The `cms` command runs with that Ruby whatever PATH
  holds later, and the installer puts `~/.local/bin` on PATH in your shell's
  startup file (`CMS_NO_MODIFY_PATH=1` skips that).
- **The `cms` CLI with no locale set** (a bare shell, an MCP client) failed
  reading its own profile. It reads UTF-8 always.

## 1.18.4

### Changed
- **The file picker** (an image field's Choose…) opens on every file,
  newest first. Choosing a folder narrows it to that folder, and search looks
  in the folder chosen. More files load as you scroll.

### Fixed
- **Choosing a folder or uploading in the file picker** closed it.

## 1.18.3

### Fixed
- **Saving from the preview** keeps you on the Preview tab, with the page
  drawn as saved, to keep editing. It used to come back on the Edit tab.
- **A link to an editor's `#preview`** opens with the preview drawn. It used
  to show an empty frame.

## 1.18.2

### Fixed
- **Saving from the preview** looked stuck on "Saving…": the save went
  through, but the page came back with the preview as it was. Now the
  preview is drawn again with what was saved and says "Saved ✓"; a save that
  can't go through (a required field left empty) says so and opens the Edit
  tab to show why.
- **One address for the website.** A visit to www.example.com when
  Settings › General says example.com (or the other way round) is
  redirected there (301), so search engines see one copy of the site.
- **AI readers get the words, not the settings.** A page's Markdown copy
  (`/about.md`, llms.txt's links) leaves out its blocks' settings (layouts,
  image positions, choices, internal labels), and an entry's carries its own
  fields, labelled.
- **An article's structured data** names it by its title, not its SEO title
  for results.
- **The media API** takes an asset's changes under `asset:`, as the pages and
  entries APIs take theirs, as well as at the top level. Before, `asset:` was
  answered 200 and ignored.

## 1.18.1

### Fixed
- **Collapsing the menu.** Folded to icons, the menu left its full-width gray
  column behind, covering the left of the page; the column now folds with it.

## 1.18.0

### Added
- **Local development against real content** (docs/local-development.md).
  - **`bin/pull`** copies a live site onto your machine: its backup,
    through the API with a cms CLI profile (or `--url`/`--token`), in place
    of the local database and files. The copy is made safe: webhooks,
    deploys and IndexNow off, the site's address local, and
    `local@localhost` / `password1234` to sign in. `--without-people` leaves
    out everyone's accounts, form submissions and tokens. The live site is
    only read.
  - **`bin/theme`** works on a theme from its own repository: `new` starts
    one from the
    [theme starter](https://github.com/Martin-Business-Consultants/libre-publish-theme-starter)
    (every core block type, design settings, no build), `link` loads one from
    where it is and switches it on, `unlink` puts things back. Templates and
    CSS reload as you save.
- **A Save button in the preview.** Editing text in place surfaces a Save
  button over the page, with how many changes wait; ⌘S / Ctrl+S saves too.

### Changed
- **Which theme draws the site**, when an install has two: the one
  registered last, unless it's switched off and another isn't.
- **Settings › Updates › Check now** checks the plugins and themes too.

### Fixed
- **Importing a site into an install that loads the reference plugin**
  (development) no longer fails on its table, which a production database
  already has.

## 1.17.1

### Changed
- **The logo leads the admin bar.** With a logo in Settings › Branding, the
  admin bar shows it in place of the home icon and the site's name, as tall
  as the bar and as wide as that makes it. The menu no longer repeats it at
  its top. Without a logo, the icon and name stay.

## 1.17.0

### Added
- **Edit in place in the preview.** In a page's or entry's Preview tab,
  click the title or a block's short text (headings, labels, short lines)
  where the website draws it and type; the change goes into the form, and
  Save saves it. Markdown and rich text are still edited in the form.
- **A documentation site**, from `docs/` (`bin/docs`), published to GitHub
  Pages on every change: the guides down the side, each page's headings
  beside it, and search.

### Fixed
- **The admin menu always scrolls to its end.** On a short window, the
  bottom of the menu could be out of reach; now it scrolls whenever it's
  taller than the window.

## 1.16.0

### Added
- **IndexNow.** When a page or entry is published, changed or taken down,
  the CMS tells IndexNow's search engines at once (Bing, which ChatGPT
  search draws on, Yandex and others), with a key it serves itself. Only
  for a website on a public address; Settings › Search turns it off.
- **RSS feeds.** Every collection the theme draws has `/<collection>/feed.xml`
  with its newest entries, linked from each page's `<head>`.
- **Tools › SEO audit.** Pages and entries without a meta description or
  with one too short or long, titles cut off in results, the same title
  or description twice, links to pages that don't exist, images without
  alt text, and the site-wide details search engines and AI tie everything
  to. Each one links to where it's fixed.
- **SEO checks in the editor.** A page's or entry's SEO tab lists its own
  issues above the fields.

## 1.15.0

### Added
- **Search and AI fundamentals** (docs/seo.md).
  - **Structured data from the content**: every page carries schema.org
    JSON-LD for the organization behind the site, the site, the page (its
    SEO panel's type, an Article for an entry, else a WebPage) and its
    breadcrumbs. The SEO panel's schema.org type now takes effect.
  - **Settings › Search**: let in or keep out AI answer engines and AI
    training crawlers separately, say whether the site is an organization,
    a local business or a person, and list its profiles elsewhere.
  - **`/robots.txt`** made by the CMS: the admin and API kept out, the
    sitemap named, AI crawlers as Settings › Search says, and a headless
    install's host closed entirely.
  - **`/llms.txt`** and **a Markdown copy of every page** (`/about.md`), for
    AI readers, linked from each page's `<head>`.
  - **hreflang** in each page's `<head>` and in `/sitemap.xml`.

### Changed
- **A page's `<head>` is complete.** The SEO panel's Open Graph title,
  description and type and its Twitter card are used. The share image
  carries its size and alt text, an entry its dates. `nofollow` works on
  its own. An indexable page allows the large image preview and full
  snippet.

## 1.14.0

### Added
- **Live preview.** A page's or entry's editor has a Preview tab: the
  website as the theme draws it, with what's in the form now, saved or not.
  Nothing is saved until you save. "Open in a new tab" shows it full size.
- **Theme design settings (Customize).** A theme can declare the colors,
  fonts and choices an editor may change (`design:` on `Website.register`).
  Settings › Themes › Customize changes them, and the website picks them up
  at once through `website_design(:name)` and `website_design_tags` (CSS
  custom properties, `--design-<name>`). docs/themes.md.
- **Patterns.** Content › Patterns keeps sets of blocks to use again, edited
  in the block editor. The block picker offers them: an unsynced pattern is
  added as a copy, and a synced one as a "Synced pattern" block that always
  shows the pattern as it is now, on the website and in the API.
- **Search and replace.** Tools › Search and replace finds a phrase across
  every page, entry and global (titles, blocks, fields, bodies, SEO) and
  replaces it everywhere, saving each record with its history and the
  audit log. Replacing needs the publish permissions.

## 1.13.0

### Added
- **The plugin directory.** Settings › Plugins and Settings › Themes list
  the plugins and themes Libre Publish has reviewed
  ([libre-publish-plugins](https://github.com/Martin-Business-Consultants/libre-publish-plugins)),
  each with a Verified badge and Install. The list is signed (Ed25519) and
  checked against the public key the CMS ships with, and installing or
  updating from it downloads the exact commit that was reviewed, so a
  tampered list or a retagged release can't put other code on a site. It's
  fetched daily with the update check, and a listed plugin's updates follow
  the directory. Installing any other plugin by its repository still works,
  marked as unreviewed. A self-hosted directory: `CMS_PLUGIN_DIRECTORY_URL`
  and `CMS_PLUGIN_DIRECTORY_KEY`.

### Fixed
- **A plugin's tables stay out of `schema.rb`** when it comes with the
  image (`plugins/`, `themes/`), as they always did for one installed from
  Settings › Plugins. Only the reference plugin's are kept.

## 1.12.1

### Fixed
- **The menu's fly-outs can't be hidden.** An open fly-out now shows in
  the browser's top layer (the Popover API), above everything on the page
  and clipped by nothing, so no page's stacking or scrolling, and no
  browser's handling of a scrolling menu, can cover it.

## 1.12.0

### Added
- **Settings › Themes**, under Plugins in the menu. It lists the themes
  apart from the plugins: which one draws the site, its version and source,
  a newer release when there is one, and Switch on/off and Update. A theme
  can be added there by its GitHub repository. Settings › Plugins no longer
  lists themes.

### Changed
- **Media is part of the core.** The media library (`/cms/media`, the
  picker asset fields open, `/api/assets`, `/api/asset_folders`,
  `/api/bulk_uploads`) ships with the CMS instead of as the cms-media
  plugin, since every site has images. Nothing changes for an install: the
  same tables, routes, capabilities and switch in Settings › Plugins (now
  marked bundled). An install that still has the cms-media plugin, from
  `CMS_PLUGINS` or the data directory, boots without it, and Settings ›
  Plugins says it can be removed. Another plugin can still provide the
  media library in its place (`provide :media`).
- **`GET /api/bulk_uploads/:id` needs `assets:read`**, like the rest of the
  media API. Before, any signed-in caller could read an upload's progress.

## 1.11.0

### Added
- **A compatibility promise, and a check that keeps it.**
  docs/compatibility.md says what's public (the plugin API, the theme API,
  the REST API under `/api`, webhooks) and how it changes. Within a major
  version nothing public is removed or made to refuse a call that worked;
  something on its way out is deprecated first and kept until the next major
  version. `spec/contracts/public_api_spec.rb` checks every public method's
  parameters and every API route against a snapshot
  (`spec/fixtures/contracts/public_api.json`, `bin/rails cms:public_api`).
- **Hooks: filters and actions.** `Cms::Plugins.filter` changes a value the
  core is about to use (`website.seo`, `website.block`, `website.markdown`,
  `website.head`, `website.body`, `sitemap.entries`), and `Cms::Plugins.on`
  runs on an event (`page.published`, `entry.created`,
  `submission.created`, …). Either runs only while its plugin is on, and one
  that raises is reported and skipped. Plugins can add their own hooks with
  `Cms::Hooks.apply` and `Cms::Hooks.run`. docs/plugins.md, Hooks.
- **`Cms.deprecator`.** Deprecation warnings for the core's public API,
  logged in development and printed in test runs, a plugin's included.

### Changed
- **A plugin made for a newer core still loads.** `Cms::Plugins.register`
  leaves out a keyword it doesn't know, with a warning, rather than failing
  the boot.

## 1.10.0

### Added
- **Plugin and theme updates.** A daily check (with the CMS's own) finds
  each plugin's and theme's newest GitHub release. Settings › Plugins shows
  "0.3.0 available" beside one that has a newer release, and the admin bar
  counts them. Update works for every plugin that says where it came from,
  the default ones (Forms, Media) and a `CMS_THEME` theme included: the
  release goes in the data directory and runs in place of the image's copy.
  If it won't load, the image's copy runs again.
- **Remove a plugin with its data.** Removing an installed plugin can now
  also drop its tables (those named for its key, plus any its manifest
  declares with `tables:`), its migrations' records and its settings, so a
  reinstall starts clean. A plugin's page lists the tables it owns.

### Changed
- **One plugin loader.** Plugins and themes are no longer gems in the
  Gemfile. The CMS loads each at boot from the data directory, the image's
  `plugins/` and `themes/`, or `engines/` (development and test). Where a
  plugin is in more than one, the newest version runs, and on a tie the data
  directory's. The Docker build no longer re-locks the bundle, and a plugin
  may depend only on gems the core bundles (all of ours do).
- **Plugins carry where they came from.** `bin/fetch-plugins` and
  `bin/fetch-theme` write `.cms-plugin.json` (repository, ref, version) beside
  each plugin, as Settings › Plugins always has.
- **Updating in place keeps the image's plugins and theme.** One the image
  carries but the release's bundle doesn't (from `CMS_PLUGINS` or
  `CMS_THEME`) is copied into the data directory first. Before, an update
  refused for a `CMS_PLUGINS` plugin, and would have left a theme behind.
- **Forms 1.1.1** by default: the forms API takes a field's
  `options_collection`, as the builder does.

## 1.9.1

### Fixed
- **The menu's fly-outs stay on top.** Nothing on a page can draw over the
  admin menu's fly-outs or the admin bar any more: the page area is its own
  stacking layer. A fly-out also no longer opens partly under the admin bar
  when its item has scrolled up there.

## 1.9.0

### Changed
- **The admin's classic look is back.** The admin is drawn as it was before
  1.0's Litewind restyle (Fizzy's look): cool ink grays, a gray menu and
  admin bar, 3px corners, semibold buttons and labels, bold page titles,
  uppercase status badges, and a blue accent (primary buttons, links,
  focus) until Settings › Branding sets a primary color. Layout, markup and
  behaviour are unchanged, and the branding's color, type, corners and
  shadow still reach every screen.
- **The admin's CSS is all ours.** Litewind is gone: the utility classes the
  admin uses (307 of them, Tailwind's definitions, MIT) live in
  `lib/assets/stylesheets/utilities.css`, 45KB in place of 1.2MB, served as
  written with no build. A plugin's views keep using the same class names;
  one that needs a class the admin doesn't add it to its own stylesheet
  (STYLE.md).

## 1.8.2

### Changed
- **No Rails secrets to set.** An install with no `SECRET_KEY_BASE` makes
  one on its first boot and keeps it in its data directory
  (`.secret_key_base`, beside the database it protects), so a deploy tool
  that has never heard of Rails starts it, every later deploy and update
  finds the same key, and a backup of the data directory restores with it.
  One that's set always wins, so installs that have one keep it.
- **APP_HOST is optional.** Without it, links in mail, asset URLs and the
  API's `cms_url` use the host of the site's URL (Settings › General):
  Libre Publish lives on the site's own host, at `/cms`. One that's set
  still wins.

## 1.8.1

### Added
- **Stop an update.** Settings › Updates has a "Stop this update" button
  while one runs, for an update that's gone quiet when nobody can reach the
  server to see why: the version running keeps running, nothing changes, and
  the update can be started again. An in-place update stopped while it
  downloads leaves the install as it is rather than restart it on the new
  version. Admins only, as starting one is; the audit log records it
  (`upgrade.stopped`).

## 1.8.0

### Changed
- **Libre Publish lives under `/cms`, and `/` is the website.** Every admin
  page, sign-in included, moved from the root to `/cms` (`/cms/pages`,
  `/cms/sign_in`), plugins' with them: Forms and Media 1.1.0 draw theirs
  there. With a theme, `/` is the site; a headless install sends `/` to
  `/cms`. The API, `/agent` and `/frontend`,
  `/sitemap.xml` and `/up` stay at the root, so sites, the CLI and the Astro
  integration need no change. An old admin address redirects to its `/cms`
  one, so bookmarks and links in emails keep working. A plugin draws its
  admin pages inside `scope path: Cms::PATH` (docs/plugins.md).

## 1.7.0

### Added
- **The CMS can draw the website itself, from a theme** (docs/themes.md). A
  theme is a Rails engine in `themes/<name>`: plain ERB, plain CSS and an
  importmap, nothing built. With one, `/` and every page's and entry's
  address are the site's, editors still work at `/pages`, and an editor
  signed in can add `?preview` to see drafts. Templates read content
  through `WebsiteHelper`, held to their schemas: a field the block type,
  collection or global doesn't declare raises (`Website::Fields`), so a
  template can't silently drift from the content model. A theme can design
  the form emails too, and serve `/site.webmanifest`. A Docker build gets it
  from the `CMS_THEME` builder secret (`bin/fetch-theme`); without one the
  CMS is headless, as before.

### Changed
- **The CMS is called Libre Publish,** and lives at
  github.com/Martin-Business-Consultants/libre-publish, which the update
  check now reads. Mail and authenticator apps show the new name.

### Fixed
- **The admin menu's fly-outs show in Safari.** Safari clipped them to the
  menu, which scrolls on its own, so hovering an item showed nothing. The
  menu only scrolls now when it's taller than the window.

## 1.6.1

### Fixed
- **Email logos and admin links point at the CMS.** Form emails and
  collection event emails built the Branding logo's URL, and the "open in
  the editor" link, on Settings › General's site URL: the public website,
  which serves neither the CMS's files nor its admin, so the logo never
  showed and the link was a 404. Both are built on the CMS's own address
  (`APP_HOST`) now. An install whose `APP_HOST` isn't its public address
  should set it. Forms is pinned at the commit with its half of the fix.

## 1.6.0

### Security
- **The API refuses what doesn't say who may call it.** Every core API
  action now declares a capability or opens itself on purpose; one that
  says neither answers 403 instead of serving any token. Search
  (`POST /api/search`), references (`GET /api/references`), the sitemap, the
  manifest and the redirect table's reads, imports and exports had no gate.
  Plugins' API controllers keep the old default until they opt in.
- **Search and references show a read-only token only live content.** They
  listed drafts' titles, slugs, status and matched text to any token; now
  pages and entries are only the live ones unless the token can write them,
  and only the kinds it reads. `/api/v1/content` sends entries and globals
  only to a token that reads them.
- **A build's report can't change how publishing reaches the site.** The
  site's read-only token could report `render: "server"` and any
  `webhook_url`, which stopped rebuilds and sent the signed purges there. A
  report now only keeps a site rebuilt on publish; anything else waits for
  approval in Settings › Deploy (or `POST /api/frontend/delivery_approval`).
- **Webhooks, build hooks and purges can't be pointed into the CMS's own
  network.** A URL that resolves to a loopback, private, link-local (cloud
  metadata), carrier-grade NAT, multicast or IPv6 local address — written
  plainly or as IPv4-in-IPv6 — is refused when a webhook is saved and
  again when anything is sent, and each request goes to the address that
  was checked, so a name can't resolve somewhere else in between. An
  install whose receivers are on its own network sets
  `CMS_ALLOW_PRIVATE_WEBHOOKS=true`.
- **A webhook delivery no longer keeps what the receiver answered**, only
  its status, timing and error. The bodies already stored are removed.
- **Sign-in sessions end.** A session lasts 30 days from sign-in and ends
  after 14 days unused; an ended one signs no one in, and a daily job
  deletes it. Its cookie is HttpOnly, SameSite=Lax, Secure over HTTPS, and
  expires with the session, where it used to last 20 years.
- **The admin is HTTPS-only by default.** When `APP_PROTOCOL` is `https`
  (the default), HTTP redirects to HTTPS, with Strict-Transport-Security
  and Secure cookies; `/up` and localhost are never redirected.
  `CMS_FORCE_SSL=false` turns it off. `ASSUME_SSL=true`, documented for
  installs behind Cloudflare or a load balancer, now does what it says
  (it was ignored). **Behind a proxy that forwards plain HTTP, set
  `ASSUME_SSL=true` before updating**, or the redirect loops.
- **A production install checks its configuration as it boots.** A missing
  `SECRET_KEY_BASE`, or a value the app would misread (`APP_PROTOCOL`,
  `APP_HOST` with a scheme, a true/false or number that isn't one,
  `CMS_UPDATES`, `MAIL_FROM_ADDRESS`) stops the
  boot naming each problem. A missing `APP_HOST` or `SMTP_PASSWORD`, a short
  `SECRET_KEY_BASE` or some but not all `AR_ENCRYPTION_*` keys are logged.
- **Builds get the code that was tested.** The default plugins are pinned to
  a commit in `config/default_plugins.yml` (`bin/fetch-plugins`,
  `plugins:install_defaults` and `CMS_PLUGINS` take a commit as the ref), CI
  runs their specs, and every gem in the Gemfile is held to its tested major
  version. `bin/rake` with no task checks style and runs the specs, where it
  used to rewrite files with RuboCop's corrections.
- **A bulk upload can't exhaust the server's memory.** Media (now pinned at
  09d97f7) streams each image out of the zip, refusing one past 50 MB
  unpacked or 100 megapixels, and stops an archive at 2 GB unpacked or
  2,000 images; it used to read every image into memory first.

### Added
- **A plugin can add a way to update the install** from Settings › Updates
  (`Cms::Plugins.update_strategy`, docs/plugins.md › Update strategies): a
  deploy tool's, say. `CMS_UPDATES` names it like the core's own, and an
  in-place update that needs a new image goes through one that can deploy
  it. The core keeps `local`, `github` and `in_place`.
- **Saving over someone else's change is refused, in the admin and the
  API.** Pages, entries and globals have a `lock_version`. The admin's forms
  send the one they opened and say so instead of overwriting; the API
  answers reads and writes with `X-Lock-Version` and refuses a write that
  sends an older `lock_version` with 409 (docs/agent-interface.md). A write
  that sends none is applied as before.
- **A backup every night, and a way to copy it off the server.** The whole
  data directory is archived at 2am, kept with the update backups
  (`CMS_BACKUP_KEEP`), and handed to `CMS_BACKUP_COMMAND` when one is set
  (`rclone`, `aws s3 cp`, `scp`: it gets the archive's path). A failed copy
  fails the job. `CMS_BACKUP_NIGHTLY=false` turns it off.
- **Versions are kept to the newest 100 per page and entry** (`CMS_VERSIONS_KEEP`);
  older ones are deleted nightly.
- **The delivery API answers an unchanged read with 304, caches `/content`,
  and limits each token.** `/content`'s `ETag` stands for the content it was
  built from (not its bytes, which carry a fresh cursor), so a build that
  sends it back gets `304`; its `data` is cached until a page, entry,
  global, collection, tag, translation or setting changes, with assets
  resolved fresh. Each token gets 1,200 requests a minute across `/api/v1`
  (`CMS_DELIVERY_RATE_LIMIT`, `0` for none), then `429` with `Retry-After`.

### Changed
- **New API tokens start `lp_`, and service tokens `lps_`.** Tokens are
  found by their digest, so `mbc_` and `mbcs_` tokens keep working. Outgoing
  requests say `librepublish-deploy/1` and `librepublish-webhooks/1`, and new
  two-factor enrolments name LibrePublish.
- **Webhooks are documented for any receiver** (docs/webhooks.md), with the
  contract a receiver can rely on pinned in
  `spec/fixtures/contracts/webhook_contract.json`. The development demo is a
  fictional lender.

### Fixed
- **Installing, updating or removing a plugin from Settings › Plugins works
  on a Docker install.** The restart after it started without the image's
  `BUNDLE_PATH`, `BUNDLE_DEPLOYMENT` and `BUNDLE_WITHOUT`, so it found none
  of the install's gems (`Bundler::GemNotFound`) and the change failed. It,
  bin/update's run from Settings › Updates and `plugins:install` now start on
  the environment the install started with.
- **API search finds entries.** It answered 500 for any query, since the
  shared search index takes no loading scope.
- **One page or entry that can't be published no longer holds up every
  schedule.** The scheduler flips each record on its own: one that fails
  validation has its schedule cleared and the failure recorded in the audit
  log (`page.schedule_failed`, `entry.schedule_failed`, with why), one that
  hits a passing error (the database busy) is left for the next minute, and
  the rest go out either way; pages failing no longer stops entries. The run
  fails afterwards, naming what was left, so Solid Queue keeps it. Two runs
  at once flip and announce a record once.
- **A deploy that fails keeps its changes for the next one.** A build or
  purge used to clear the list of what changed before firing, so a failure
  lost it; now it's cleared once every attempt succeeded, and only of what
  went out. A deploy job run twice fires once, and a change scheduled while
  one fires is no longer dropped.
- **Settings written at the same moment no longer overwrite each other.**
  `Setting.set` and `Setting.set_secret` read and write their row in one
  transaction; `Setting.set` takes a block for a value worked out from the
  current one (the deploy log, pending changes, a counter).
- **Jobs retry when the database was busy** (SQLite's "database is locked",
  a full connection pool), up to five times, and drop a job whose record was
  deleted before it ran.
- **Clearing a value this install's keys can't read is recorded.** Replacing
  such a token or secret now writes `<model>.unreadable_value_cleared` to the
  audit log with the ciphertext, so the right keys can still recover it if
  the keys were only misconfigured, and logs an error.
- **Backups are checked before anything trusts them.** Each database in a
  data backup is checked (`PRAGMA quick_check`) and a copy that stops short
  fails the backup, so an update never migrates on the strength of one that
  wouldn't restore. Before, a copy that hit a lock was archived as it was.
- **Tools › Backup's download is a consistent snapshot**, taken with SQLite's
  online backup instead of reading the live file, and fails rather than
  shipping without its database. It's built on disk and streamed, not held
  in memory, and its manifest names any uploaded file that was missing
  instead of leaving it out without a word.
- **A person who ever edited a page or entry can be deleted.** Their
  versions keep their content and lose their author; before, the delete
  failed. Likewise a category entry other entries use can be purged from the
  trash (they become uncategorized), and a collection another one draws its
  categories or tags from can be deleted.
- **The nightly trash purge keeps going past a record it can't delete**,
  reporting it, instead of stopping there every night; a purge is recorded
  only once the record is gone, and deleting several collections is all or
  nothing.
- **A redirect import reads its CSV a row at a time** and refuses one over
  5 MB (`413` from `/api/redirects/import`).
- **Every `/api` error is JSON in one shape**, `{"error", "message"}`: a
  missing parameter or a body that isn't JSON is a `400`, a format the
  endpoint doesn't serve a `406`, a lost race a `409`, an `/api` path no
  route matches a JSON `404`, and anything unexpected a `500` that's
  reported and never shows a backtrace. Before, these came back in Rails'
  `{"status", "error"}` shape, or as an HTML page. The bodies the API
  already answered (`not_found`, `invalid`, `forbidden` with its
  `capability`) are unchanged.

## 1.5.4

### Fixed
- **A token or secret encrypted with another install's key can be replaced.**
  Rotating an API token or a service token, re-entering a setting's secret,
  and `cms login` (which rotates a token it can't show) all failed on one,
  because saving read the old value first; it's cleared before the new one
  is written. `cms login` and the agent installer answered 500 on a site
  moved from the old shared deployment.

## 1.5.3

### Fixed
- **A plugin's install, update or removal no longer waits 15 minutes when
  the restart after it fails.** The migrate and restart that follow it now
  write to the install's log (the container's, in Docker) and to the data
  directory (`plugin_changes/<n>/`), and Settings › Plugins fails the change
  at once with the end of what they said; an update goes back to the
  release before. Before, a migration that broke there left the change
  "running" with its output in a file inside the app.

## 1.5.2

### Changed
- **A plugin's stylesheet loads only where the plugin shows something**: its
  own pages, the pages rendering one of its slots (Media's picker in the
  page and entry editors), and every page when it's in the admin bar.
  Turbo adds and drops them as pages change.

### Fixed
- **A plugin's stylesheet that hasn't been compiled no longer fails every
  admin page** (a 500 on /pages, from a plugin's stylesheet):
  the admin renders without that plugin's styles and reports it, and a
  failure compiling an installed plugin's assets at boot is logged with
  what went wrong.

## 1.5.1

### Fixed
- **1.5.0 wouldn't start on a site whose roles hold a plugin's capabilities
  that plugin isn't here for** (Commerce's `quotes:read` on a site moved
  from the old shared deployment): setting up Forms and Media as it booted
  saved those roles whole, their validation refused the stranger, and the
  container stopped. Granting a plugin's defaults now leaves a role's other
  capabilities be, and a plugin whose setup fails is logged and tried again
  at the next boot rather than stopping it.
- **A release an install updated itself to that won't start sends it back
  to its image** (`bin/docker-entrypoint`) instead of a container that never
  comes up, and Settings › Updates says the update failed, with why.
- **A backup leaves out what can be fetched again**: the releases an install
  updated itself to (`releases/`) and the archives a site was imported from
  (`site_imports/`). The backup a container takes as it boots with
  migrations to run copied them all, gigabytes after a few updates, and the
  site answered 502 until it finished.

## 1.5.0

### Fixed
- **A plugin that starts on, installed into a running site, is set up.** Forms
  or Media installed after the roles existed (`plugins:install`, Settings ›
  Plugins, `CMS_PLUGINS`, an upgrade) never gave them its defaults, so the
  site's Production site token got 403 reading its forms. `bin/rails
  plugins:settle`, run after every `db:migrate` and `db:prepare`, sets such a
  plugin up once, granting its defaults only to built-in roles holding none of
  its capabilities.
- **No drafts on the site through a collection list.** A `collection_list`
  set to show any status listed draft entries in `/api/v1`; the delivery API
  now lists only published ones. Each listed entry carries its `url` and
  `collection`, and `contact_info` gives the business's details only.
- **Publishing an entry purges the pages listing it** on a site rendered on
  demand: a page's `Cache-Tag` names the collections its lists show.
- **Changing the site's name, URL or contact details** in Settings › General
  rebuilds or purges the site, like a publish.

### Changed
- **The Astro integration is one package from its own repository**,
  [libre-cms-astro](https://github.com/Martin-Business-Consultants/libre-cms-astro),
  with Forms, Media and Commerce in it. `/frontend/install.sh` installs it
  from there and no longer adds `@librepublish/astro-forms` or `-commerce`.
- `/api/v1/site`'s `meta.cms_url` gives the CMS's own address, which asset
  URLs start with.

## 1.4.2

### Added
- **`CMS_PREVIOUS_SECRET_KEY_BASE`** keeps values another install encrypted
  readable here: a site moved from the old shared deployment sets it to that
  deployment's `secret_key_base`, and its API tokens, service tokens and
  integration keys can be shown and used again, while the install keeps its
  own keys and writes with them. `bin/rails cms:reencrypt` then rewrites
  every encrypted value with this install's keys, so the variable can go.

## 1.4.1

### Fixed
- **Settings › API token, Service tokens and settings secrets no longer fail
  on values encrypted with another install's key** (a site moved here
  without that install's keys). A token it can't read still works, and its
  page says to rotate it to get one that can be shown; a setting's secret it
  can't read counts as not set.

### Changed
- **An install carries only the default plugins, Forms and Media.** The
  reference plugin (Hello, `engines/hello`) is for working on the core: it's
  in the development and test bundle only, so it's no longer listed in
  Settings › Plugins or in an update's bundle.

### Added
- **Slugs fill in from the title as it's typed** (the slug Stimulus
  controller): a new page's, entry's, collection's, global's or block
  type's, as the server would make it (`our-cafe-bar`; `site_settings` for
  globals and block types). Typing your own takes it over; a saved record's
  slug never follows its title, since that would move its address.

## 1.4.0

### Added
- **A Docker install updates itself from Settings › Updates**, as
  WordPress does, with nothing to set up: Update downloads the release's
  bundle for this machine (the app, its gems, the default plugins and its
  Ruby, attached to every release from now on) into the data volume, checks
  it, and restarts the container on it (`Upgrade::InPlace`). Deploying a
  newer image takes over again. A release that needs a new system base
  redeploys through another update strategy when the install has one, or says
  how, and one that would leave a `CMS_PLUGINS` plugin behind refuses. Docker
  installs with no other strategy set up now update this way instead of by
  hand. An install deploys 1.4.0
  once to get it.

## 1.3.0

### Added
- **Search everything from the admin bar.** The search icon at its top
  right finds pages, entries, collections, globals, block types, redirects,
  users and roles that hold a term, whatever the person's role can read,
  with where each matched, a page at a time (`/search`, `GlobalSearch`).
- **Numbered pagination on every index table**: 25 rows a page, and under
  the table which rows these are and « Previous, the page numbers and
  Next », keeping the list's filters and search. Lists that loaded more as
  you scrolled, and those that showed everything (pages, trash, the
  sitemap…), all page this way. Plugins' tables get it as they are.

### Changed
- **Search runs on ActiveSearch** (`rails-active_search`): one index of
  every page, entry, collection, global, block type, redirect, user, role
  and audit entry, in this install's database, kept in step as they're
  saved. A list's search box searches it, finding any part of a word (two
  characters or fewer still match by LIKE), and so do `POST /api/search`
  and `cms search`. It replaces `pages_fts` and `collection_entries_fts`;
  the migration indexes what's already there, and `bin/rails
  search:reindex` replaces `fts:rebuild`.
- **The admin's layout**: a page's actions (its New button) sit across from
  its title at the right, and there's no line under the title. The admin
  menu stays put while the page scrolls, a fly-out stays open as the
  pointer travels to it, and the site's logo heads the menu. Screen options
  is in the admin bar, beside the theme toggle, and choosing Light keeps
  checkboxes and the browser's other controls light.

## 1.2.1

### Changed
- **Releases come from `Martin-Business-Consultants/cmsv2`**, now public:
  the daily update check reads them there (`CMS_RELEASES_REPO` still points
  it elsewhere). An install on 1.2.0 checks the old repository until it
  updates, or until it sets `CMS_RELEASES_REPO=Martin-Business-Consultants/cmsv2`.

## 1.2.0

### Added
- **Install a plugin from Settings › Plugins**: an admin
  gives its GitHub repository (`owner/name`) and the CMS installs its latest
  release on the server (`CMS_DATA_DIR/plugins`), where it stays through
  deploys and updates, and restarts. Installed plugins get Update and Remove
  buttons, an update that won't load puts the previous release back, and
  Recent changes says how each went (`PluginChange`). A plugin may depend
  only on gems the core bundles. `CMS_INSTALLED_PLUGINS=off` boots without
  them.

## 1.1.0

### Added
- **Import a site from the old deployment's backup archive.**
  `bin/rails "cms:import_tenant[PATH]"` takes the `.tar.gz` the old
  deployment's Tools › Backup or `cms backup` writes as PATH, as well as a
  directory, with the tenant and its owner from the archive's manifest. The
  LibrePublish Import plugin (`cms-site-import`) is the button for it.
- **`CMS_PLUGINS=default`** installs the default plugins alone, for a host
  that won't keep an empty secret.

### Fixed
- **Docker builds fetch the default plugins.** The image copies
  `config/default_plugins.yml` before `bin/fetch-plugins` runs, so it knows
  what they are.

## 1.0.0

### Added
- **Open source**, under the Functional Source License (FSL-1.1-MIT,
  `LICENSE.md`).
- **Releases are cut with `bin/release X.Y.Z`**, which moves these notes under
  the version, tags and pushes; GitHub publishes the release with them
  (`.github/workflows/release.yml`). CI runs `bin/ci` on every push and pull
  request.
- **Docker installs keep their plugins.** The `CMS_PLUGINS` builder secret
  lists git URLs (with an optional `#tag`), and the image build fetches them
  before bundling (`bin/fetch-plugins`).
- **Settings › Updates**: the newest release and its notes, Check now, and
  an Update button (admins only). A plain install runs `bin/update <tag>` in
  the background; a Docker install starts the Deploy workflow
  (`CMS_GITHUB_TOKEN`, `CMS_DEPLOY_DESTINATION`). `CMS_UPDATES` forces
  github, local or manual. The page follows a running update until the
  install boots on the new version, or says why it failed. `GET /api/updates`,
  `POST /api/updates/check` and `cms updates [check]` read and check, but
  can't start one. `CMS_UPDATE_CHECK=false` turns off the daily check.
- **A tool that runs Kamal can deploy the CMS** from the repository as it
  is (docs/install.md): one app per site.

### Changed
- **A new look for the admin, styled with Litewind.** The screens are drawn
  with Tailwind's utility classes from Litewind 2.0.1 (Tailwind compiled
  ahead of time, vendored, still no build step), after Payload's admin:
  neutral and flat, a gray sidebar, compact controls. Every screen follows
  Settings › Branding's color, type and surface, in both themes: the primary
  color is the accent (primary buttons, links, focus, the current menu item;
  black until one is set), the secondary color tints the grays, and the
  font, corners and shadow — until now the public site's only — apply to the
  whole admin.
  Fizzy's CSS and its utility classes (`btn`, `txt-small`, `flex-column`…)
  are gone: a plugin whose views used them should move to Tailwind classes
  and the core's `ui(...)` recipes (STYLE.md, docs/plugins.md).
- **`config/deploy.yml` names no server, hostname or secret.** It is what
  every install shares; a site's destination and secrets
  (`config/deploy.<site>.yml`, `.kamal/secrets.<site>`) are no longer
  committed. The proxy now reaches Thruster (port 80), and `asset_path` is
  set.
- **No Rails credentials.** `config/credentials.yml.enc` and the master key
  are gone; everything comes from the install's environment. Mail takes
  `SMTP_PASSWORD` (no credentials fallback) and `MAIL_FROM_ADDRESS` /
  `MAIL_FROM_NAME` (default `noreply@<APP_HOST>`, `LibrePublish`), and
  Active Record encryption takes `AR_ENCRYPTION_*` or derives from
  `SECRET_KEY_BASE`. A site moved from the old shared install sets
  `SECRET_KEY_BASE` to that install's.
- The daily update check reads the CMS's releases from GitHub
  (`CMS_RELEASES_REPO`).
- **The admin is laid out like WordPress's.** A dark admin menu down the left
  (top-level items with icons, in groups, the current one open with its
  submenu, the others flying out on hover and keyboard focus; folds to icons;
  a drawer on narrow screens) and a thin admin bar across the top (the site
  and View site, "+ New", the update notice, plugins' items, the "/" filter,
  the theme and the person's menu). Screens share WordPress's conventions:
  the title with its primary action beside it, notices as toasts at the
  bottom right (a notice fades after a few seconds, an alert stays until it's
  dismissed),
  and list tables with status links ("All (12) | Published (8)"), a "Bulk
  actions" select and Apply, a search box, a tick-all box, and row actions
  under the title. The header nav, its Menu popup and the settings pages'
  section list are gone; Settings' sections are its submenu.
- **Plugins add to the admin menu** with `Cms::Plugins.menu` (a top-level
  item), `submenu` (a link under any item) and `new_item` ("+ New"), in place
  of `nav`.
- **The CMS says it's headless.** Every page, entry and global editor has a
  **JSON** tab: the record exactly as the API hands it to the site, with its
  endpoint and how to fetch it. A **Developers** screen explains how
  frontends work with the CMS, lists the API, walks through connecting an
  Astro site, and shows the frontend it serves and its last build; the
  dashboard says the same in a line.
- **The CLI, MCP and API come first.** Developers leads with the three
  surfaces and their one-line setups; every admin screen with a `cms`
  command names it under its title; the dashboard lists the tokens working
  through the API this week. New commands cover what the admin gained:
  `cms frontend`, `cms asset <id> [set …]`, `cms email … set`,
  `cms webhook create|update`.
- **Docs** (Help › Docs): guides on how the CMS works, working with an Astro
  site and working with AI agents (Markdown in `app/guides`, filled in for
  the install). The same at `/api/docs` and `cms docs [slug]`.
- **Site health** (Help › Docs › Site health, `/api/site_health`,
  `cms site-health`): whether the site is in good order, always — the business's name, address, phone and hours, and
  one phone number everywhere in its pages and globals; Turnstile or reCAPTCHA with both keys, form notifications and a
  sender on the site's domain; meta descriptions, a sharing image,
  structured data, nothing hidden from search by mistake; a contact page,
  privacy policy and terms; alt text and broken links; HTTPS, rebuilds,
  webhooks, a recent backup and two-factor. Forms, when it's installed,
  provides `:spam_protection`.
- **Connecting an Astro site is one line**:
  `curl -fsSL <cms>/frontend/install.sh | sh` in the site's project installs
  the Astro packages (with the Forms and Commerce add-ons when those plugins
  are on) and gets the site its own read-only service token through a browser
  approval (the device login, now with a `site` purpose).
- **The Astro integration is npm packages**: `@librepublish/astro`,
  `@librepublish/astro-forms` and `@librepublish/astro-commerce`, in their own
  repository (github.com/Martin-Business-Consultants/cms-astro), in place of
  files copied into each site from `integrations/astro`. Content loaders read
  the delivery API incrementally; types come from `/api/v1/schema`; `<Blocks>`,
  `<Image>`, `<Seo>`, `<Form>` and `<QuoteRequest>` render it. Each build
  writes `_redirects`, `sitemap.xml` and `robots.txt`, holds the site to Site
  health's site-facing checks (also written into its AGENTS.md), and reports
  how the site renders; a site rendered on demand on Cloudflare gets signed
  cache purges at `/_cms/webhook`. The GitHub publish workflow for a site repo
  is `docs/cms-publish.yml`.
### Removed
- **The core is content and publishing, and little else.** Gone, with their
  screens, API endpoints and `cms` commands: review requests, Approvals,
  pending changes (revisions), findings (`/api/recommendations`), Tools ›
  Schedules (recurring tasks), the go-live checklist and the dashboard's
  getting-started checklist; and the Agents, AI, Local Marketing, Consent &
  Scripts and Importers plugins. Site Health stays. A migration drops their
  tables and settings, and takes their capabilities off saved roles. The
  webhook contract (version 2) no longer has the findings endpoint.
- **No review queue: anything in front of visitors takes the publish
  capability.** Changing a published page or entry, or any global, and
  publishing or scheduling a draft, need `<resource>:publish`. Without it the
  admin refuses the save with an error (a role that can't publish gets Save
  Draft and no Publish button) and the API answers 403. Version history and
  "Restore this version" stay.
- **Inertia, React, shadcn, Vite, TypeScript and Tailwind.** `app/frontend`,
  the `inertia_rails`, `vite_rails` and `typelizer` gems, `package.json`
  and the pnpm lockfile, the SSR Dockerfile and the Vite dev process are
  gone. The CMS needs no Node: not to develop, not to build its image, not
  in CI (the npm lint, format, type-check and audit steps are gone too).
- **The CMS's own page renderer** (`/site/:slug`, `SiteController`, the
  `site/blocks` partials). Pages are only rendered by the published site.
  `/api/preview_drafts` stays for the Astro site's `/_preview`; the
  `preview_url` it returns now points there, like `public_preview_url`
  (nil until Settings › General has the site's base URL).
- **Relationships** (`/relationships`, "Where is this used?"). The reference
  index it read (`ContentReference`, `/api/references`) stays: the asset
  usage audit and the API use it.
- **`app/services` in the core.** Its last four objects are plain objects in
  `app/models` (`Sitemap`, `Preview`, `OnboardingChecklist`,
  `Recommendation::QueueState`); an architecture spec keeps it gone.
- **`app/services` in the plugins**, and with it every exception the
  architecture specs allowed. Agents, AI, Forms and Importers keep
  their classes, now in `app/models`; the plugins' APIs render jbuilder
  views; Forms' `POST /api/submissions/bulk_destroy` is a resource at the
  same URL; the AI plugin's LLM tool becomes `Ai::Tool`, so only AI
  names RubyLLM. The specs now forbid all four patterns outright.
- **Plugin job names.** `AgentRunJob`, `AgentSchedulerJob`, `ReapAgentRunsJob`,
  `NotifyFormSubmissionJob`, `NotifyQuoteRequestJob`, `SendInvoiceJob`,
  `AstroImportJob`, `DirectusImportJob` and `WordpressImportJob` become
  `AgentRun::ExecutionJob`, `Agent::ScheduleJob`, `AgentRun::ReapJob`,
  `FormSubmission::NotificationJob`, `QuoteRequest::NotificationJob`,
  `Invoice::DeliveryJob` and `Importers::{Astro,Directus,Wordpress}Job`,
  each calling a `*_now` verb on its record or adapter. The old names stay
  one release as subclasses, for jobs already queued.
- **`Trash::PurgeJob`**, which nothing scheduled. `TrashPurgeJob` now runs
  every night (config/recurring.yml) and deletes what has been in the trash
  longer than 30 days.

### Content editor
- **The page, entry and global forms are Hotwire**, and with them the block
  editor: blocks and repeater items reorder by dragging or with the arrows,
  blocks are added from a filterable picker and can be duplicated (with a
  new id), rich text is Lexxy writing HTML, assets are chosen (or uploaded)
  in a picker over the file manager, and references and links are selects.
  A form saved without edits writes back exactly what it read; an edit
  changes only what it touched.
- **JSON-LD is validated**: `seo.json_ld` must be one node or a list of
  nodes with an `@type` (or an `@graph`), on pages and entries alike, and
  the SEO panel has a JSON-LD box.
- **The visual editor (the live preview iframe) is gone.**
- A new entry's slug is made from its name when left blank, as a new
  page's already was.

### Plugins
- **Local Marketing is a plugin** (`engines/local_marketing`), off by
  default and adopted by an install with reports or reporting settings:
  DataForSEO reports, the site audit, the Marketer's Report, its guided
  setup, Settings › Reporting and `/api/reports`. It runs without the AI
  plugin; the written summaries are left out without one. `/api/reports`
  answers exactly as before while it's on, and 404s while it's off.
- **Reports and the Marketer's Report are text for now**: each report says
  what it measured, when, its headline figures against the run before, and
  its rows as tables. Charts, the rank map and sparklines are gone until
  reporting is redesigned. Running a report, the baseline, handing work to
  an agent and rewriting the summary are resources at the same URLs.
- A wildcard token's capabilities come in the role editor's order again,
  with each plugin's where its group sits.
- **AI and Agents are plugins** (`engines/ai`, `engines/agents`), off by
  default; Agents depends on AI. AI holds OpenCode Zen, RubyLLM and
  Settings › AI; Agents holds agents, swarms, templates, the run log and the
  worker protocol. An install with agents, runs or swarms — or a saved AI
  setting — adopts them on upgrade. `/api/agents` and every
  `/api/agent_runs` step the `cms` CLI uses answer exactly as before while
  they're on, and 404 while they're off. Findings stay in the core; the
  finding still names the agent that filed it.
- The agents, runs, live view and swarms render in ERB; the charts are
  words for now. Queue, upgrade, cancel, seeding and installing templates
  are their own resources at the same or nearby URLs (`/agents/:id/run`,
  `/agents/:id/upgrade`, `/agent_runs/:id/cancellation`,
  `/agent_templates/seeding`, `/agent_templates/:id/installation`, and the
  same for swarm templates).
- Plugins can run work every N minutes (`minutely`) and set a site up on
  install or first switch-on (`bootstrap`). The agent scheduler and reaper
  moved from `config/recurring.yml` into the Agents plugin, run by
  `PluginsMinutelyJob`.
- Adopting a plugin adopts the plugins it depends on.
- **Importers is a plugin** (`engines/importers`), off by default: Tools ›
  Import with a tab per source (WordPress, Directus, Astro), and the wipe
  before a fresh import. Each source is an `Importers::Adapter`, so another
  plugin can add one. `/api/tools/import`, `/api/tools/import/<source>` and
  `/api/tools/import/wipe` answer exactly as before while it's on, and 404
  while it's off.
- Forms owns `submission.created` and its per-form webhook filter
  (`webhook_event_filter`); the event list and its order are unchanged.
- Switching a plugin on for the first time gives the built-in roles its
  standard permissions (audited as `plugin.permissions_granted`).
- Settings › Forms stores the Turnstile and reCAPTCHA secret keys encrypted
  and never shows them again; a migration moves saved ones across.
- `after: :start` puts a plugin's addition first.

### Admin
- The file manager renders in ERB: a folder tree, cards or a table, search
  across folders, uploads straight to storage with progress, zip unpacking
  with a page that follows it, bulk move and delete, and a page per file with
  its alt text, folder and where the site uses it.
- Tools › Schedules and Tools › Backup render in ERB; Backup also lists the
  data-directory archives `bin/update` keeps, for download.
- **Commerce is a plugin** (`engines/commerce`), off by default and switched
  on for any install that already has quote requests or invoices. Its admin —
  the quote inbox, invoices, Settings › Commerce — renders in ERB; sending,
  paying and voiding are resources (`/invoices/:id/delivery`, `…/payment`,
  `…/voiding`). `/api/quotes`, `/api/invoices`, `/api/quote_requests` and the
  hosted `/i/:token` page answer exactly as before while it's on, and 404
  while it's off. Settings › Commerce now needs `invoices:read` to open and
  `invoices:write` to save.
- Plugins can add webhook events (`webhook_events`), place a new Menu group
  (`group_after:`), and name another plugin's item — or a list of choices —
  in `after:`.
- An invoice's payment link must be an http(s) URL as a whole, not just start
  like one; a quote request's page and item links only become links when
  they're http(s).

### Moved
- **Forms and Commerce are installed plugins**, each in its own repository,
  rather than bundled in `engines/`. Install them with
  `bin/rails "plugins:install[<git url>]"`, or list them in `CMS_PLUGINS` for a
  Docker install; their data and tables are unchanged. Only `engines/hello`,
  the reference plugin, still ships with the core.

## 1.0.0

The first versioned release: the CMS becomes something you install, one
customer per install, rather than a shared multi-tenant service.

### Installs, versions and updates
- **One install per site.** Multi-tenancy is gone (activerecord-tenanted, the
  global database, subdomain routing, root-domain signup and provisioning).
  An install is configured by its environment: `APP_HOST`, `SITE_KEY` (sent
  as `tenant` in webhooks, the manifest and device login, unchanged for
  integrations) and `CMS_DATA_DIR`, which holds every database and uploaded file.
- `bin/install --host …` sets up a plain install; `bin/update [vX.Y.Z]` backs
  up the data directory, checks out a release, migrates and restarts.
  `config/deploy.yml` is one install per Kamal destination
  (`config/deploy.example-site.yml`); the container backs up its data before
  every migrate. See docs/install.md.
- The first account created at `/sign_up` is the owner; the CMS is
  invitation-only after that. A fresh install gets the site's starter
  content, never the demo seed.
- A daily check of the CMS's GitHub releases; Settings says when a newer
  version is available.

### Plugins
- A plugin system: Rails engines in `engines/`
  (bundled) and `plugins/` (installed with `bin/rails "plugins:install[url]"`),
  switched on in Settings › Plugins. Extension points: menu links, view
  slots, settings pages, capabilities, stylesheets, nightly tasks, API
  endpoints (listed in `/api/manifest`), agent tools, reports, importers,
  script presets, block type packs, schema field types, deploy providers and
  in-process content events. `engines/hello` is the reference plugin;
  docs/plugins.md the guide.
- Deploys go through a provider: the existing build hook, or GitHub
  (`repository_dispatch` on the site's repo). Installs with a hook URL keep
  using it.

### The admin moves to Hotwire
- Inertia/React/shadcn give way to server-rendered ERB (Herb/ReActionView),
  Stimulus and Turbo, with Fizzy's CSS, served through importmap and
  Propshaft with no build step. Every admin screen is ported.
- Custom actions become resources (approvals, rejections, restorations, bulk
  deletions, rotations…). `/api` URLs and response shapes are unchanged;
  `/api/manifest` gains `version` and `plugins`.
- Backups (Tools › Backup) now include uploaded files.
