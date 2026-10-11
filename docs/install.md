# Installing and updating the CMS

One install serves one site: its own process, databases, uploaded files and
secrets, reached at its own hostname. Everything the install stores lives in
one data directory (`CMS_DATA_DIR`), so backing up that directory and the
install's secrets backs up the site.

There are two ways to run one: Kamal (Docker, the default) or a plain
checkout with `bin/install`.

## What an install is configured with

| Variable | What it is |
|---|---|
| `APP_HOST` | The address people and the API use (`acme.librepublish.com`). Links in email, the `cms` CLI and agent bootstraps are built from it. Optional: without it, the host of the site's URL (Settings › General), since Libre Publish lives on the site's host at `/cms`. |
| `SITE_KEY` | What the API calls the site — the `tenant` field of webhook envelopes, `/api/manifest` and device login, which integrations match on. Defaults to the first label of `APP_HOST`. Keep it when a site changes host. |
| `CMS_DATA_DIR` | Databases (`production.sqlite3`, `_cache`, `_queue`, `_cable`), Active Storage files, and `backups/`. Default `storage/` in the app. |
| `SECRET_KEY_BASE`, `AR_ENCRYPTION_PRIMARY_KEY`, `AR_ENCRYPTION_DETERMINISTIC_KEY`, `AR_ENCRYPTION_KEY_DERIVATION_SALT` | The install's secrets. Losing them loses the sessions and every encrypted value (API tokens, integration keys). Without the `AR_ENCRYPTION_*` keys, encryption keys derive from `SECRET_KEY_BASE`. Optional: an install without `SECRET_KEY_BASE` makes one on its first boot and keeps it in the data directory (`.secret_key_base`), so a host needn't know a Rails app wants one, and a backup of the data directory restores with it. Setting one always wins. |
| `CMS_PREVIOUS_SECRET_KEY_BASE` | Another install's `secret_key_base`, so values it encrypted stay readable here: a site moved from the old shared deployment, or an install whose `SECRET_KEY_BASE` changed. This install still writes with its own keys; `bin/rails cms:reencrypt` rewrites everything with them, after which this can go. |
| `SMTP_ADDRESS`, `SMTP_PORT`, `SMTP_USERNAME`, `SMTP_PASSWORD` | Outbound mail. The address, port and username default to Outsend's relay (`smtp.getoutsend.com`, 2587, `outsend`); the password is its API key. A site can use its own server instead, from the admin: Settings › Email delivery (with a test email), which then carries all its mail. |
| `MAIL_FROM_ADDRESS`, `MAIL_FROM_NAME` | The sender of the install's own mail (password resets, invitations), and the fallback for the site's. Default `noreply@<APP_HOST>`, `Libre Publish`. |
| `APP_PROTOCOL` | `https` (default) or `http`, for links. |
| `CMS_BACKUP_KEEP`, `CMS_BACKUP_DIR` | How many data backups to keep (5) and where (`$CMS_DATA_DIR/backups`). |
| `CMS_BACKUP_COMMAND` | Copies each nightly backup off the server: run with the archive's path as its last argument (`rclone copyto --s3-no-check-bucket`, `aws s3 cp … s3://bucket/`, `scp … host:dir/`). Unset, backups stay on the server. |
| `CMS_BACKUP_NIGHTLY` | `false` stops the nightly backup, for an install whose host snapshots the volume instead. |
| `CMS_VERSIONS_KEEP` | How many versions of each page and entry to keep (100); older ones are deleted nightly. |
| `ASSUME_SSL` | `true` behind a proxy that terminates TLS (Cloudflare, a load balancer). |
| `CMS_ALLOW_PRIVATE_WEBHOOKS` | `true` lets webhooks, build hooks and a site's purge URL point at private, loopback or link-local addresses — for an install whose receivers are on its own network. Off by default (on while developing). |
| `CMS_FORCE_SSL` | `false` to serve the admin over plain HTTP. Otherwise, when `APP_PROTOCOL` is `https`, HTTP redirects to HTTPS (except `/up` and localhost), with Strict-Transport-Security and Secure cookies. Behind a proxy that forwards plain HTTP, set `ASSUME_SSL=true` too, or the redirect loops. |
| `CMS_PLUGINS` | The install's plugins, for a Docker build (see Plugins below). |
| `CMS_RELEASES_REPO`, `CMS_RELEASES_TOKEN` | Where the daily update check looks (default `Martin-Business-Consultants/libre-publish`), and a token if that repo is private. |
| `CMS_UPDATE_CHECK` | `false` stops the daily check for a newer release. |
| `CMS_UPDATES` | How Settings › Updates updates: `local` (bin/update), `github` (the Deploy workflow), `in_place` (a Docker install updating itself), `manual` (shows the command), or a plugin's strategy (docs/plugins.md). Worked out from the install when unset. |
| `CMS_GITHUB_TOKEN`, `CMS_DEPLOY_DESTINATION`, `CMS_DEPLOY_WORKFLOW` | For a Docker install updating itself: a token that may start the Deploy workflow, the site's destination, and the workflow file (`deploy.yml`). |

## Kamal

`config/deploy.yml` is what every install shares and names no server,
hostname or secret; each site is a destination over it, and every Kamal
command names one (`require_destination`).

1. Copy `config/deploy.example-site.yml` to `config/deploy.<site>.yml` and set
   its `service` (`cms-<site>`), server, `APP_HOST`, `SITE_KEY`, `proxy.host`
   and volume (`cms_<site>_storage`). Several sites can share a server.
2. Copy `.kamal/secrets.example-site` to `.kamal/secrets.<site>` and point it
   at the site's secrets in your password manager. Neither file is
   committed.
3. `kamal setup -d <site>` once, then `kamal deploy -d <site>` for every
   release.

## Another deploy tool

A tool that runs Kamal for you can deploy the repository as it is: it reads
`config/deploy.yml` and `.kamal/secrets-common`, and writes each site's
destination from what you give it.

1. Name the app **for the site** (`cms-acme`). Kamal names the service, and
   so the data volume (`cms-acme_storage`), after the app; two environments
   of one app on the same server would share a volume, and with it every
   database.
2. Give it a destination's variables (`APP_HOST`, `SITE_KEY`,
   `MAIL_FROM_ADDRESS`, `ASSUME_SSL=true` behind a TLS-terminating proxy) and
   secrets (`SECRET_KEY_BASE`, the three `AR_ENCRYPTION_*` keys,
   `SMTP_PASSWORD`, and `CMS_PLUGINS` if it has plugins).
3. Settings › Updates then updates the install in place (Updating, below).
   A plugin can add an update strategy that goes through the tool instead
   (docs/plugins.md › Update strategies).

On boot the container backs up the data directory (`bin/rails cms:backup`),
then runs `db:prepare`: an empty volume gets the site's starter roles, block
types, settings and globals — never the demo seed — and an existing one is
migrated. Open `https://<host>/cms/sign_up` to create the owner, or
`kamal app exec -d <site> 'bin/rails cms:bootstrap[owner@acme.com]'`, which
prints the owner's password and the site's two machine tokens once.

## A plain install

From a checkout of a release (`git clone … && git checkout v1.0.0`):

    bin/install --host acme.example.com [--site-key acme] [--data-dir /var/lib/cms] [--port 3000]
                [--admin-email owner@acme.com --admin-name "Ann Owner"]

It installs the production gems, writes `.env` with fresh secrets (only if
there isn't one; mode 600), prepares the database and compiles assets. With
`--admin-email` it creates the owner and prints the password once; otherwise
the first visit to `/cms/sign_up` does. Run it with
`set -a; . ./.env; set +a; bin/thrust bin/rails server`, or as a service with
`config/cms.service`.

## Updating

A release is a `vX.Y.Z` tag. The install checks for a newer one daily, and
Settings › Updates shows it with its notes and an **Update** button. The
button works one of four ways, depending on how the install runs
(`CMS_UPDATES` forces one):

- **A Docker install** (Kamal or another deploy tool, with none of the
  others set up) updates itself in place, the way WordPress does. Each release carries
  a bundle for amd64 and arm64 (the Dockerfile's `bundle` stage: the app,
  its gems, compiled assets, the default plugins and the Ruby they run on),
  built by `.github/workflows/release.yml` in the minutes after it's
  published. The button downloads the one for this machine into
  `$CMS_DATA_DIR/releases/vX.Y.Z`, checks its checksum, points
  `releases/current` at it and restarts the container, which is unavailable
  for a few seconds. On boot `bin/docker-entrypoint` runs whichever is
  newer, the image or `releases/current`, backing up and migrating as
  usual; deploying a newer image takes over again. It relies on the
  container's restart policy (Kamal's `unless-stopped`). Only a release that needs other system packages or
  Debian (`CMS_BASE` in the Dockerfile) needs a new image: the update then
  deploys it through a strategy that can (GitHub's, or a plugin's) if the
  install has one, or says how.
  Plugins installed from Settings › Plugins live in the data volume and
  carry over; a plugin the image carries from `CMS_PLUGINS` that isn't a
  default one isn't in the bundle, so the update refuses rather than drop
  it (install it from Settings › Plugins instead). An install on an image
  older than 1.4.0 deploys once to get this. `kamal app exec` opens a shell
  in the image's copy (`/rails`), not the running release.

- **A plain install** (a checkout with a `.env`) runs `bin/update <tag>` in
  the background: back up the data directory, fetch and check out the
  release, bundle, migrate, compile assets, restart Puma. Its output goes to
  `$CMS_DATA_DIR/updates/<n>/update.log`.
- **A plugin's strategy** (a deploy tool's, say) updates the tool's way
  (docs/plugins.md › Update strategies).
- **A Kamal install** starts the repository's **Deploy** workflow
  (`.github/workflows/deploy.yml`), which runs `kamal deploy -d <site>` on
  GitHub. Set `CMS_GITHUB_TOKEN` (a fine-grained token on the repository:
  Contents read, Actions read and write) and `CMS_DEPLOY_DESTINATION`. On
  GitHub, make an environment named for the site holding
  `DEPLOY_DESTINATION_YML` (its `config/deploy.<site>.yml`),
  `SSH_PRIVATE_KEY` and the secrets its destination names.

The page follows the update and says when the install runs the new version,
or why it failed; until then the old version keeps running. Without any of
these, it shows the command. By hand:

    bin/update             # the code that's checked out (after your own git pull)
    bin/update v1.1.0      # fetch and check out that release first
    kamal deploy -d <site> # a Kamal install, from a checkout of the release

`bin/update` stops at the first step that fails (under systemd, restart with
`sudo systemctl restart cms`).

Migrations have to be safe on a live install and on an older version still
running beside a newer database: add columns and tables in one release, and
remove or rename them only in a later one, once nothing reads them.

### Without downtime

A Docker install runs Puma with two workers (`WEB_CONCURRENCY`, 2 by
default in production) from `releases/live` in the data volume, a symlink to
the code that runs. Restarts change the workers one at a time while the
other keeps serving, so visitors don't notice:

- **A plugin or theme** installed, updated or removed from Settings: its
  migrations run, then the workers restart onto it.
- **The CMS, updated in place** (Settings › Updates): the release is
  downloaded and checked, the data is backed up and migrated with the new
  code while the running one serves, `live` is pointed at it, and the
  workers move onto it. If they haven't come up on it five minutes later,
  `live` goes back and the update says why. This needs the release to run
  on the same Ruby and Puma as the running one; a release that changes
  either restarts the container as before (a few seconds to a minute).
- **A redeploy** (Kamal, hoster): Kamal's proxy starts the new container,
  waits for `/up`, then sends traffic to it.

Background jobs run beside the workers and restart with them; a job
waiting for a few seconds is the only sign.

Migrations only ever add (docs/compatibility.md), which is what lets the
running code keep serving while they run.

## Backups and restoring

`bin/rails cms:backup` writes `backups/cms-data-<time>.tar.gz` in the data
directory: every database (copied with SQLite's online backup, so it's
consistent while the app runs, and checked with `PRAGMA quick_check` before
it's archived) and every uploaded file, keeping the newest five. bin/update
and a container boot that will migrate take one, and a migration doesn't run
if it fails. One is also taken every night at 2am (`CMS_BACKUP_NIGHTLY=false`
turns that off), and handed to `CMS_BACKUP_COMMAND` to copy off the server
when one is set; a failed copy fails the job. Tools › Backup lists them for
anyone with `tools:use` to download. An install that made its own
`SECRET_KEY_BASE` keeps it in the data directory, so its backups carry it, and
whoever holds one can read its tokens: keep backups as private as the server.
One given `SECRET_KEY_BASE` keeps it out of them; keep it with the backups, as
a backup without it can't decrypt its tokens.

To restore: stop the app, move the data directory aside, unpack the archive
into an empty one (`tar -xzf cms-data-….tar.gz -C "$CMS_DATA_DIR"`), start the
app. Tools › Backup's download is a different thing: the primary database
and the uploaded files as one portable `.tar.gz`, with a manifest naming any
file that was missing.

## Releasing

Add notes under `## Unreleased` in `CHANGELOG.md` as you go, then from a clean
`main`:

    bin/release 1.1.0

It moves the Unreleased notes under `## 1.1.0`, writes `VERSION`, commits,
tags `v1.1.0` and pushes. `.github/workflows/release.yml` publishes the GitHub
release with that section as its notes, which is what every install's update
check reads.

## Plugins

The core bundles only the reference plugin (`engines/hello`). The rest —
Forms and Commerce among them — are git repositories, each switched on in
Settings › Plugins once it's in. Every install gets the default plugins
(`config/default_plugins.yml`: Forms and Media) at setup — `bin/install` and the Docker
build fetch them. A plain install adds them with
`bin/rails "plugins:install[url,ref]"` (docs/plugins.md). A Docker install
clones its repository fresh for every build, so it lists them instead, in the
`CMS_PLUGINS` builder secret, and the image build fetches them
(`bin/fetch-plugins`) before bundling:

    CMS_PLUGINS="https://github.com/org/cms-seo#v1.2.0 https://x-access-token:TOKEN@github.com/org/private-thing"

Each is a git URL with an optional `#tag` or branch, separated by spaces,
commas or newlines, on top of the defaults. `-forms` leaves a default out,
`none` installs nothing at all, and `default` means the defaults alone (for
a host that won't keep an empty secret). It is a secret so a
private plugin's URL can carry a token without it reaching the image. Set it
in `.kamal/secrets.<site>`, in your deploy tool's secrets, or as a GitHub environment
secret for the Deploy workflow, then deploy.

## Rebuilding the public site on publish

With Settings › Deploy set to GitHub, publishing sends the site repo a
`repository_dispatch` event of type `cms-publish`. The repo needs a workflow
that listens for it: copy `docs/cms-publish.yml` into the site's
`.github/workflows/`, set its `CMS_BASE_URL` and
`CMS_API_TOKEN` (the read-only Production site token) repository secrets, and
replace its placeholder deploy step with the host's (Cloudflare Pages,
Netlify and GitHub Pages are sketched in comments). The GitHub token in
Settings › GitHub needs `contents: write` on that repo to send the event.

The dispatch's `client_payload` is `{reason, site, changes}`: every content
change in the debounce window (at most 50, then `truncated: true`), each
`{event, kind, id, path, locale, tags}`. With Cloudflare, pick **Cloudflare
(Pages or Workers Builds deploy hook)** in Settings › Deploy and paste the
deploy hook URL instead.

### Static or on demand

The site's build tells the CMS how it renders (`POST /api/frontend/builds`
with `render`: `static`, `server` or `hybrid`, and `webhook_url`, the Astro
integration's `/_cms/webhook`). Publishing then:

- **static** (or not yet reported): rebuilds through the deploy provider.
- **server**: sends a cache purge instead of rebuilding. "Deploy now" still
  rebuilds, and purges everything.
- **hybrid**: rebuilds (for the prerendered routes) and purges.

The first report of `server` or `hybrid`, and any later change to how the
site renders or to its `webhook_url`, waits in Settings › Deploy › The site
for someone with `settings:write` to approve it (or `POST
/api/frontend/delivery_approval`): the site builds with a read-only token, and
that token shouldn't be able to stop rebuilds or send the signed purges
somewhere else. A static site needs nothing approved.

A purge is a `POST` to the webhook, signed like webhooks are:

    X-CMS-Event: cms.purge
    X-CMS-Signature: sha256=<HMAC-SHA256 of the body, with the purge secret>
    {"event": "cms.purge", "reason": "page.published", "site": "acme", "all": false,
     "tags": ["page:about", "pages", "sitemap"], "changes": [{...}], "sent_at": "..."}

The secret is in Settings › Deploy › The site (reveal, rotate); give it to
the site as `CMS_WEBHOOK_SECRET`. The cache tags are the CMS's one
vocabulary: `page:<path>` (`page:` is the home page), `entry:<collection>/<slug>`,
`collection:<slug>`, `global:<slug>`, `pages`, `sitemap`, `redirects`.

## Moving a site from the shared deployment

The old deployment kept one SQLite database per tenant
(`storage/production/<tenant>/main.sqlite3`), Active Storage keys prefixed
`<tenant>/`, and the files under `storage/<tenant>/`. One site moves into its
own, fresh install with

    bin/rails "cms:import_tenant[PATH]"

run on the new install (on Kamal, `kamal app exec -d <site> -i 'bin/rails …'`
with PATH on the volume). PATH is a directory holding copies of:

| | |
|---|---|
| `main.sqlite3` (and `-wal`, `-shm` if there are any) | The tenant's database. Required. |
| `global.sqlite3` | The old global database — where the owner's email comes from. Optional. |
| `files/` | The tenant's `storage/<tenant>/` directory (also found as `PATH/<tenant>/` or `PATH/storage/<tenant>/`). |

Or PATH is the old deployment's backup archive, which holds all three: the
database, every file, and (in its manifest) the tenant and its owner. Take it
from the old site's Tools › Backup, with `cms backup > site.tar.gz`, or, for a
site whose media is too big to pull through a request, on the old server with
`bin/rails "tenants:backup[<tenant>]"` (it prints where it wrote it). Then

    bin/rails "cms:import_tenant[cms-backup-<tenant>-<time>.tar.gz]"

A blob whose file the old deployment couldn't find is named in the archive's
manifest, and reported as missing by the import.

The task copies the database and checkpoints the copy (it never writes to
PATH), puts it in place of the install's database (the one it replaces stays
beside it as `production.sqlite3.before-import-<time>`), runs the migrations
it's behind on, strips the `<tenant>/` prefix from blob keys, copies each file
to where this install looks for it and checks its checksum, and gives the old
owner the Admin role. Then it reads every encrypted value and names the
columns it couldn't decrypt, and prints a summary: migrations run, blobs
copied or missing, the owner, and a count of each table.

| Variable | |
|---|---|
| `DRY_RUN=1` | Say what would happen and change nothing. |
| `FORCE=1` | Import into an install that already has users (replacing its database). Without it the task refuses. Re-running with it starts again from PATH, so it lands the same. |
| `TENANT` | The old subdomain, if it can't be told from the blob keys or the global database. |
| `SITE_KEY` | Defaults to the tenant. |
| `FILES` | The files directory, if it isn't in one of the places above. |

Before and after:

- Give the install `CMS_PREVIOUS_SECRET_KEY_BASE`: the old deployment's
  `secret_key_base` (in its Rails credentials: `bin/rails credentials:show`
  in its checkout), so the API tokens, service tokens and integration keys
  it encrypted stay readable here. The install keeps its own
  `SECRET_KEY_BASE` and keys and writes with them. The task warns about any
  value it can't read. Once the site runs here, `bin/rails cms:reencrypt`
  rewrites them all with this install's keys, and the variable can go. (A
  value nothing can read can only be re-entered, or the token rotated.)
- Set `SITE_KEY` to the old subdomain and keep `<sub>.librepublish.com` as
  `APP_HOST` (the task prints both), so existing tokens, CLI profiles,
  integrations and the Astro site keep working.
- Drain the old deployment's job queue before switching the hostname over.
