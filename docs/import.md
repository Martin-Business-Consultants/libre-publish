# Importing a site

An import replaces the whole site in an install (pages, entries, files,
people, settings) with a backup's. It never merges: the database it replaces
is kept beside the new one, whole, so it can be put back.

    bin/rails "cms:import[PATH]"

tells which core the backup came from and imports it:

| Backup | |
| --- | --- |
| The Go core's (librepublishgo): Tools › Backup there, or `GET /api/tools/backup` | `manifest.json` (`"format": "librepublish-go"`), `cms.sqlite3`, `storage/<k0k1>/<k2k3>/<key>`, and `secret.key` when it was asked to include it. Also unpacked, or the Go install's data directory itself. See below. |
| This core's, from the old shared deployment | As `cms:import_tenant`: [Moving a site from the shared deployment](install.md#moving-a-site-from-the-shared-deployment). |

## Moving a site from the Go core

On the Go install, take a backup: Tools › Backup › Download (tick "include
the secret key" to carry the secrets without handing the key over
separately), or `curl -H "Authorization: Bearer $TOKEN" https://cms.example/api/tools/backup -o site.tar.gz`.
Then, on this install (on Kamal, `kamal app exec -d <site> -i 'bin/rails …'`
with the archive on the volume):

```sh
DRY_RUN=1 bin/rails "cms:import[site.tar.gz]"                 # what it would do; changes nothing
SECRET_KEY_FILE=old-data/secret.key bin/rails "cms:import[site.tar.gz]"
FORCE=1 SECRET_KEY_FILE=… bin/rails "cms:import[site.tar.gz]"   # …over a site that has people
```

| Variable | |
| --- | --- |
| `DRY_RUN=1` | Unpack, build and report, and change nothing. |
| `FORCE=1` | Replace a site that already has people. Without it the task refuses. |
| `SECRET_KEY_FILE` | The Go install's `DATA_DIR/secret.key`, to carry the secrets it sealed. Not needed when the backup includes it. |
| `GO_SECRET_KEY` | Or the `SECRET_KEY` the Go install ran with (a passphrase, or a key's 64 hex characters). |

A key given that opens none of the backup's secrets is refused before
anything changes.

### How it's done

1. **Unpacked** into `tmp/go_import/<time>/`. Only the entries a backup holds
   are written, each to a path built from what it is (the database, a file
   by its key), never one taken from the archive. An entry that's absolute,
   climbs out with `..`, or is a link or a device fails the whole import, as
   does an archive past the size limits (64 GiB unpacked in all, 32 GiB a
   file, two million entries: a gzip bomb stops there). Then the database is
   checked: `PRAGMA quick_check`, and the tables a site has.
2. **A new database is built** with this install's own schema (its plugins'
   tables and its migrations included), and every table the two cores share
   is copied in, ids kept, by the columns both have. The Go core keeps no
   migrations of its own (only `PRAGMA user_version`), so its file isn't
   adopted. A row this core's constraints refuse is named, not lost quietly.
3. **The content is brought onto this core's terms** (below), the forms
   converted, the secrets opened and kept as this core keeps them, and the
   files' blobs pointed at this install's storage. A dry run stops here and
   prints the report.
4. **Applied**: this install's database moves aside
   (`production.sqlite3.before-import-<time>`, its `-wal` and `-shm` with
   it) and the new one takes its place; each file is copied to this install's
   storage and checked against its size and checksum (missing and damaged
   ones are reported, not hidden); the search index is rebuilt;
   `site_backup.imported` goes in the audit log.

Stop the app first (or run it in a one-off container with the app stopped):
the app's processes keep the database they opened, and would go on using the
one moved aside. Start it again after.

### What carries over

Pages (with their blocks, fields, SEO and versions), collections and
entries, globals, block types and patterns, the media library and its files,
redirects, roles, people (with their passwords; two-factor settings as they were),
service and personal tokens (they keep signing in, by digest), webhooks and
their deliveries, settings, the audit log, content references.

- **Rich text.** The Go core's `richtext` fields become `text` fields, this
  core's rich text, and their values (the Go editor's Tiptap document) its
  HTML: headings, paragraphs and line breaks, bold, italic, strikethrough,
  code, links, lists, task lists (a checkbox before each item, as Markdown's
  are drawn), quotes, code blocks with their language, rules. Wherever they
  are: a page's or entry's blocks and fields, globals (in repeaters and
  groups too), versions, patterns, a block type's defaults. A link that isn't
  a web, email or phone address, or a path, keeps its words.
- **File addresses.** A link in the content to a Go-served file
  (`https://old-cms.example/files/<key>/photo.jpg`) points at the same file
  as this install serves it; a rendition (`/files/<key>/w640/…`) becomes the
  original.
- **Roles.** The Go core's system role, "Administrator", is this core's
  "Admin". Capabilities this install doesn't have (a Go plugin's, like
  `forms:read`) are dropped, and named.
- **Secrets.** The Go core seals token plaintexts, webhook signing secrets
  and settings' passwords with its key. Opened with it, a token's plaintext
  is encrypted with this install's keys (so it can be revealed), a webhook's
  secret and a setting's (the GitHub token, a deploy hook) are kept as this
  core keeps them, and Settings › Email's server becomes Settings › Email
  delivery, its password in the encrypted secrets. Without the key, each is
  **cleared**, never left looking like a value that works: a token still
  signs in but can't be revealed, a webhook gets a new secret (give it to the
  receiver), a setting loses that value.
- **Forms.** When this install has the Forms plugin's tables, the Go Forms
  plugin's forms become its forms (slug, name, fields, submit label,
  thank-you; open is published, closed a draft), its emails the
  notification and confirmation (merge tags written `{{form_title}}`,
  `{{submitted_at}}`, `{{name}}`), and its submissions theirs, with their
  status, address and browser. Without those tables, and for any other Go
  plugin, what the plugin kept is written beside the database as
  `go-plugins-<time>.json` and reported.
- **Everyone is signed out.** Sessions, device sign-ins, password-reset
  links and edit locks aren't carried.

### What doesn't round-trip

The report names each one it finds:

- changes waiting for review on the Go core (review them there first);
- unsaved edits (autosaves), admin preferences, webhook deliveries not yet
  made;
- a webhook's body map (an external webhook's shape: this core sends its own
  envelope) and its testing address; a personal token's label, and all but
  the most recently used personal token of a person (this core keeps one
  each);
- a form's redirect page, captcha and spam settings, hook, and cc/bcc;
  Settings › Email's sender (set who mail comes from here again);
- rich text the Go editor doesn't make (its words are kept), and a
  paragraph's alignment;
- tables and columns a newer Go core added.

To put the previous site back: stop the app, move the imported
`production.sqlite3` aside, and move `production.sqlite3.before-import-<time>`
(and its `-wal`, `-shm`) back in its place.

The Tools › Backup screen doesn't import yet: replacing the database under a
running app needs every process restarted onto it, so it's the command line's
job for now.
