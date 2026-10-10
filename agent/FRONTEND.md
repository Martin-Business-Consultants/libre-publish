# This site is the frontend of a headless CMS

The content of this site — its pages, collections, navigation, footer, forms,
redirects — lives in the __SITE__ CMS at __CMS_URL__. The CMS never
renders HTML for visitors. It stores content and serves it as JSON; **this
repo reads that JSON and renders it**, through the `@librepublish/astro`
integration. Keep that split:

- **Content changes happen in the CMS**, not here. Don't hardcode copy, nav
  items, prices, contact details or anything else an editor would expect to
  change. If a template needs text, it reads it from a global or a field.
- **Structure and presentation happen here**: layouts, components, styling,
  routing, build config.

This section of AGENTS.md is written by the integration (`cms()` in
`astro.config`) on every `astro dev` and `astro build`, between its markers.
Edit outside them; inside, your changes are replaced.

## The integration

| Package | What it gives the site |
|---|---|
| `@librepublish/astro` | The `cms()` integration; content loaders (`/loaders`); live loaders and `cacheHint` (`/live`); a typed client, `linkHref`, `routeParam` and the types (`/client`); forms — `getForm`/`getForms` and the form email helpers (`/forms`); quotes — `commerceEnabled` (`/commerce`); `<Blocks>`, `<Image>`, `<Seo>`, `<Form>`, `<QuoteRequest>` (`/components/*.astro`). Forms and Media, the CMS's default plugins, are part of it, and Commerce for a site that sells by quote. Source: github.com/Martin-Business-Consultants/libre-cms-astro. |

Env: `CMS_BASE_URL` (the CMS's origin) and `CMS_API_TOKEN` (the site's
read-only *service token*, Settings › Service tokens). Never commit either.
A site rendered on demand also needs `CMS_WEBHOOK_SECRET` (Settings ›
Deploy), and, to purge Cloudflare's cache, `CLOUDFLARE_ZONE_ID` and
`CLOUDFLARE_API_TOKEN`.

## Content: the loaders

Read content through content collections, in `src/content.config.ts`:

```ts
import { defineCollection } from "astro:content";
import { cmsPages, cmsEntries, cmsGlobals, cmsAssets } from "@librepublish/astro/loaders";

export const collections = {
  pages: defineCollection({ loader: cmsPages() }),
  posts: defineCollection({ loader: cmsEntries("posts") }),   // one per collection the site shows
  globals: defineCollection({ loader: cmsGlobals() }),
  assets: defineCollection({ loader: cmsAssets() }),
};
```

They read the CMS's delivery API (`GET __CMS_URL__/api/v1/content`), and
only what changed since the last build. Ids: a page's path, an entry's slug,
a global's slug, an asset's id. Only published content ever reaches the site.

The content model is typed: `import type { Block, Collections, Globals } from
"librepublish:types"` — generated from the CMS's schema on every build. Read
the generated `.astro/integrations/librepublish/cms.d.ts` before writing a
component for CMS data; don't guess a field name.

## Pages, entries, globals

**A page** has `path`, `title`, `locale`, `url`, `blocks`, `frontmatter` (its
own fields), `seo`, `category`, `tags` and `translations`. **An entry** has the
same plus `collection` and `body_markdown`. **A global** has `slug`, `name` and
`data` (navigation, footer, contact details).

**`url` is where a record is served.** Route by it, never by `path`: the home
page's `url` is `/`, an entry's is `/<collection>/<slug>`, and anything in a
locale other than the default is under that locale's prefix (`/fr/…`).

```astro
---
// src/pages/[...path].astro
import { getCollection } from "astro:content";
import { routeParam } from "@librepublish/astro/client";
export async function getStaticPaths() {
  return (await getCollection("pages")).map(({ data }) => ({
    // routeParam (@librepublish/astro/client): the url as a [...path] param,
    // and an absolute SEO canonical back to the path it's served at.
    params: { path: routeParam(data, { site: import.meta.env.SITE }) },
    props: { page: data },
  }));
}
---
```

## Rendering

- **Blocks** — `<Blocks blocks={page.blocks} components={{ hero: Hero, text: Text }} assets={assets} />`.
  Each component gets the block's data as props, plus `block` and `assets`.
  A type without a component is skipped (editors can add a block type before
  the site has one); add a component for every type the CMS uses.
- **Images** — `<Image asset={assets[id]} sizes="…" />`: served from the CMS,
  with its renditions as a srcset, its size and alt text. Asset fields hold an
  id; look it up in the `assets` collection.
- **SEO** — `<Seo record={page} assets={assets} siteName="…" />` in `<head>`:
  title, description, canonical, robots, Open Graph and Twitter cards, hreflang
  links to its translations, JSON-LD.
- **Links** — link fields are `{ kind: "url" | "page" | "entry", value }`;
  `linkHref(link)` from `@librepublish/astro/client` makes the href.
- **Field values** — `text` fields are HTML (`set:html`), `markdown` fields
  Markdown, and an entry's `body_markdown` is HTML when written in the
  rich-text editor (a Markdown renderer passes HTML through).

## What the integration does for the site

- `/sitemap.xml` (every URL, with lastmod and hreflang) and `/robots.txt`.
- `_redirects` for Cloudflare, from the CMS's redirect rules.
- The site's URL (`site`), its locales (Astro i18n, the default unprefixed)
  and the CMS's images as remote images, from the CMS.
- **Static or on demand.** Builds are static by default: fetch in
  `getStaticPaths` and frontmatter, not in the browser; publishing in the CMS
  rebuilds the site. With the Cloudflare adapter —
  `cloudflare({ prerenderEnvironment: "node" })` — pages can render on demand
  (`export const prerender = false`), reading through `Astro.locals.cms` or
  the live loaders (`@librepublish/astro/live`); the integration adds
  `/_cms/webhook`, where the CMS sends signed cache purges, and tags each
  response with what it read. Each build tells the CMS which way the site
  renders.

## Forms and quotes

- **Forms** (the Forms plugin, on by default) — `<Form slug="contact" />`
  (`@librepublish/astro/components/Form.astro`) renders a
  form's fields, a honeypot and Cloudflare Turnstile (when the CMS has it set
  up), and the browser posts straight to the CMS. Never proxy submissions
  through the site.
- **Form emails** — a route at `src/pages/emails/[form]/[kind].astro`
  (helpers from `@librepublish/astro/forms`: `emailTemplatePaths`,
  `digestMeta`, `answersRow`) gives each form's emails the site's design;
  `cms()` sends the templates here after each build, and the CMS sends the
  emails.
- **Quotes** (with the Commerce plugin) — `<QuoteRequest items={[…]} />` on
  a product page posts a quote request straight to the CMS.

## Site health

The CMS checks the site against Site health (Docs › Site health): the
business's details, the pages a site needs (contact, privacy, terms…), meta
descriptions, a sharing image, structured data, alt text, spam protection on
forms. **Build the site so every one of those checks passes** — the
checklist below is the current state, and `astro build` warns about each
that fails. Where a check needs content (a privacy page, a meta
description), the content goes in the CMS; where it needs the site (a
contact page that shows the address and a form, `<Seo>` in every layout),
it goes here.

## Changing the CMS itself

Content, fields, collections, block types and settings are changed in the CMS
(its admin, or the `cms` CLI: `curl -fsSL __CMS_URL__/agent/install.sh | sh`),
not from this repo. The only things this repo writes to the CMS are what its
build produced: form email templates and a build report.
