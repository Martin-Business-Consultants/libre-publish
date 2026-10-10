# Themes

A theme makes the CMS draw the public website itself, instead of handing its
content to a site built elsewhere (Astro, over the delivery API). It's a
Rails engine, like a plugin, in `themes/<name>`: a layout, a template per
page kind, a partial per block type, a stylesheet and a few scripts. Plain
ERB, plain CSS, an importmap: nothing is built.

Libre Publish always lives under `/cms` (`Cms::PATH`), and `/` is the
website's. With a theme, `/` and every address the CMS gives a page or entry
are the site; editors sign in at `/cms/sign_in`. Without one the CMS is
headless: the delivery API serves a site built elsewhere, and `/` goes to
`/cms`. The API (`/api`), the agent and frontend bootstraps, `/sitemap.xml`
and `/up` stay at the root, where sites and tools call them.

The reference is healingearthdesignbysarah.com's,
[healing-theme](https://github.com/Martin-Business-Consultants/healing-theme).

## Installing one

Like a plugin: Settings › Plugins › Add a plugin, and give the theme's
GitHub repository (`owner/name` or its URL). The CMS installs its latest
release into the data directory, where it outlasts updates, and restarts;
the site is on while the theme is switched on there. A theme registers as a
plugin (`Cms::Plugins.register`) as well as with `Website`, so that's all it
takes. A theme can also come with the install, in `themes/` (a checkout, or
a Docker build's `CMS_THEME` secret, bin/fetch-theme).

## What the core does

| Piece | What it does |
|---|---|
| `Website` (`app/models/website.rb`) | The theme registry: `Website.register :healing, name:, version:, views:, importmap:` from the theme's engine. `Website.enabled?` is whether there's a site to draw |
| `Website::Address` | What's at a path: `/` the home page, `/about` a page by its path, `/<collection>/<slug>` an entry. Live records only, unless an editor previews |
| `Website::PagesController` | Draws it: a page with the theme's `website/pages/show`, an entry with `website/entries/<collection>` (no template, no pages for that collection), anything else Tools › Redirects, then the theme's `website/not_found`. `/about/` is `/about` |
| `WebsiteHelper` | What templates read content through (below) |
| Routes | `/` (`config/routes.rb`) and a catch-all drawn after every plugin's routes (`config/initializers/website.rb`), so it never hides one; `/api`, `/rails` and `/assets` answer for themselves. An address the admin had before `/cms` (`/pages`) redirects there |

### Reading content: `WebsiteHelper`

| Helper | Gives |
|---|---|
| `website_blocks(record)` | A page's blocks, each drawn by `website/blocks/_<type>` with `data:` (a type without a partial is left out) |
| `website_global(:slug)` | A global's data |
| `website_fields(entry)` | An entry's frontmatter |
| `website_entries(:collection)` | A collection's published entries, by their `order` field, then title |
| `website_href(link)` | A link field as an href (`home` is `/`) |
| `website_path(record)` | A page's or entry's address |
| `website_image_tag(id, sizes:)` | An `<img>` with a `srcset` of resized copies, its width and height, its alt text and its focal point |
| `website_markdown`, `website_rich_text`, `website_plain_text` | Text fields, made safe |
| `website_seo_tags(record, …)` | The `<head>` its SEO panel describes |
| `website_scripts(:head)`, `website_scripts(:body)` | The "scripts" global |
| `website_form_field(form, :name)` | A form's field by name, for a form drawn by hand |
| `website_javascript_tags` | The theme's importmap, none of the admin's |

### Fields are held to their schemas

`data`, `website_global` and `website_fields` are `Website::Fields`: a
field the block type, collection or global declares reads as its value
(`data.heading`, `data.items.first.title`); one it doesn't raises
`Website::Fields::Unknown`, naming what it does have:

    home_hero has no field "subtitle" (it has eyebrow, heading, lede, image, …)

So a template written against a field that was renamed, or never existed,
fails in its spec instead of rendering an empty section. `website_form_field`
does the same for a form: a form drawn by hand names its fields through it,
so it can't post one the form doesn't declare (the Forms plugin would drop
it without a word).

## A theme

    themes/healing/
      healing.gemspec
      lib/healing.rb, lib/healing/engine.rb   Website.register, the importmap
      config/importmap.rb                     the site's scripts
      app/views/layouts/website.html.erb
      app/views/website/pages/show.html.erb   every page
      app/views/website/entries/<collection>.html.erb
      app/views/website/blocks/_<type>.html.erb
      app/views/website/not_found.html.erb
      app/views/website/emails/form.html.erb  form emails, in the site's design (optional)
      app/views/website/manifest.json.jbuilder  /site.webmanifest (optional)
      app/helpers/<theme>_helper.rb           its own vocabulary (icons, buttons)
      app/assets/stylesheets/<theme>/site.css
      app/assets/{fonts,images}/<theme>/
      app/javascript/<theme>/*.js
      lib/tasks/<theme>.rake                  <theme>:snapshot
      spec/fixtures/cms/snapshot.json, spec/requests/website_spec.rb

The CMS loads `themes/*/` as it does plugins (docs/plugins.md); an install has at most one.
Settings › Plugins updates a theme fetched from GitHub like any plugin.

Every template and partial declares its locals (`<%# locals: (data:) -%>`),
and Herb compiles them (ReActionView): a broken tag fails the render, and
an unused local fails the lint.

### Its spec, against the CMS it draws

`spec/fixtures/cms/snapshot.json` is the site's content model and content:
block types, collections, globals and forms with their fields, and every
page and entry. The theme's spec loads it and draws every page and entry,
checks the contact form against the form, and posts it. `bin/rails
<theme>:snapshot` refreshes it from the CMS (the `cms` CLI; `CMS_PROFILE`
picks which), so a change to the content model shows up as a failing spec
before it shows up as a broken page.

### CI

`bin/ci` lints themes at `--fail-level warning` (accessibility included),
runs Brakeman over them, and runs `bin/rspec themes/*/spec`. The core's own
specs run headless; one tagged `website: true` gets the installed theme.

### Form emails

With `website/emails/form` (locals: `email`, the Forms plugin's FormEmail),
the theme designs every form email: the plugin renders it from the email's
blocks each time it sends one, repeats the row marked
`data-cms-repeat="answers"` (holding `{{answer.label}}` and
`{{answer.value}}`) once per answer, and fills the `{{tokens}}`, escaped.
Forms › the form › Emails says "The website's theme designs it". Mail
clients need tables and inline styles, and `website_image_url` for images.
Without the template, emails go out in the CMS's own layout.

### Page to page

The stylesheet's `@view-transition { navigation: auto; }` turns on the
browser's own cross-document view transitions: the page crossfades, and an
element with the same `view-transition-name` on both pages (a case study's
card photo and its page's header photo) morphs from one to the other. A
name must be unique on a page, so a second card for the same record turns
its name off (`morph: false` in the reference theme).

## Serving it

A published page is `Cache-Control: public, max-age=60,
stale-while-revalidate=86400` with an ETag of the content
(`DeliveryVersion`) and the theme's version, and of nothing about the
visitor (no flash, no session, no cookie), so the browser, Thruster and
Cloudflare can all keep it; a `304` costs one query. Images are resized
copies proxied through the site (`/rails/active_storage/representations/proxy/…`),
cached like any file. An editor signed in to the admin can add `?preview` to
any address to see drafts, never cached.
