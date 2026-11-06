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

This section of AGENTS.md is written by the CMS's installer
(`curl -fsSL __CMS_URL__/frontend/install.sh | sh`), between its markers;
running it again refreshes it. Edit outside them; inside, your changes are
replaced.

## The integration

`@librepublish/astro` (github.com/Martin-Business-Consultants/librepublish-astro)
is the whole integration: `cms()` in `astro.config`; content loaders
(`/loaders`) and live loaders (`/live`); a typed client, `linkHref` and
`routeParam` (`/client`); `renderRichText` (`/rich-text`); and the components
`<Blocks>`, `<Image>`, `<RichText>`, `<BrandStyles>`, `<Seo>`, `<Form>` and
`<StaticForm>` (`/components/*.astro`). Its README is the reference: read it
before reaching for anything else.

Env: `CMS_BASE_URL` (the CMS's origin) and `CMS_API_TOKEN` (the site's
read-only *service token*, Settings › Service tokens). Never commit either.
A site rendered on demand also needs `CMS_WEBHOOK_SECRET` (Settings ›
Deploy), and, to purge Cloudflare's cache, `CLOUDFLARE_ZONE_ID` and
`CLOUDFLARE_API_TOKEN`.

## What's enforced

The integration holds the site to the CMS, and a build fails rather than
ship something that doesn't fit. Work with it, never around it:

- **The schema lock.** `cms.lock.json` pins the CMS schema the site was
  written against (`/api/v1/schema`'s `meta.schema_digest`). When someone
  changes a block type, collection, global or a page's fields in the CMS,
  `astro build` and `astro check` stop and list what changed. Then:
  `npx librepublish-astro sync`, `npx astro check`, fix what it names, and
  commit the lock with the fixes. Never hand-edit the lock, and don't set
  `LIBREPUBLISH_ACCEPT_SCHEMA=1` to get a build through: that's for CI that
  opens a pull request with the new lock (subscribe it to the CMS's
  `schema.changed` webhook).
- **Every record matches the schema.** The loaders bring the CMS's schema as
  Zod: frontmatter, block data, global data and SEO take only the fields the
  CMS declares, a required field must hold a value, and the records around
  them are strict too. A failure names the record and the field. The fix is
  in the CMS (the content, or its fields), or in the site's code after a
  sync — never a `schema` of the site's own on a CMS collection.
- **The build runs on one schema.** Every `/api/v1` answer carries
  `X-CMS-Schema-Digest`; one that differs from the lock mid-build stops it.
  Build again.
- **Every block type has a component.** The components map is
  `satisfies BlockComponents` (from `librepublish:types`): leaving a block
  type out, or keeping one the CMS dropped, is a type error, and content
  using a type with no component stops the build. Synced patterns arrive
  expanded, so there's nothing to write for them.
- **Redirects live in the CMS** (Tools › Redirects, or `cms redirect add`),
  and only there: `_redirects` is written from it, and a `redirects` map in
  `astro.config` or rules in `public/_redirects` stop the build.
- **Forms can't go stale.** `<Form slug>` draws a form from its live
  definition and renders on demand only: on a prerendered page it stops the
  build. A static site uses `<StaticForm>` (a client island) instead.
- **Site health and the launch checklist.** Each build reads the CMS's Site
  health checks and its own (no secrets in the build, only the routes meant
  to render on demand do, the site serves its own images, sitemap,
  robots.txt and a 404 page, redirects from the CMS, forms), warns about
  each that fails, and reports them with the build to the CMS (Settings ›
  Deploy shows them). `cms({ siteHealth: "error" })` makes a failing check
  fatal.

## Content: the loaders

Read content through content collections, in `src/content.config.ts` — with
no `schema` of your own: each loader brings the CMS's.

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

The content model is typed from the same schema: `import type { Page,
Entries, Globals, Block, BlockProps, BlockComponents, AssetId, Link } from
"librepublish:types"`, regenerated on every `astro dev`, `astro sync` and
`astro build`. Read the generated `.astro/integrations/librepublish/cms.d.ts`
before writing a component for CMS data; don't guess a field name.

## Pages, entries, globals

**A page** has `path`, `title`, `locale`, `url`, `blocks`, `frontmatter` (its
own fields), `seo`, `category`, `tags` and `translations`. **An entry** has the
same plus `collection`, `body_markdown` and `blocks` (when its collection has
them). **A global** has `slug`, `name` and `data` (navigation, footer…).

**`url` is where a record is served.** Route by it with `routeParam`, never
by `path`: the home page's `url` is `/`, an entry's is `/<collection>/<slug>`,
anything in a locale other than the default is under that locale's prefix
(`/fr/…`), and an SEO canonical can be absolute.

```astro
---
// src/pages/[...path].astro
import { getCollection } from "astro:content";
import { routeParam } from "@librepublish/astro/client";
export async function getStaticPaths() {
  return (await getCollection("pages")).map(({ data: page }) => ({
    params: { path: routeParam(page, { site: import.meta.env.SITE }) },
    props: { page },
  }));
}
---
```

## Rendering

- **Blocks** — `<Blocks blocks={page.blocks} components={components} assets={assets} />`,
  with `components` in one file, `satisfies BlockComponents`. Each component
  is typed `BlockProps<"hero">`: the block's data as props, plus `block`,
  `assets` and `resolved` (a `collection_list`'s entries, `contact_info`'s
  contact details).
- **Images** — `<Image asset={assets[id]} sizes="…" />`: the CMS's renditions
  as a srcset, its size, alt text and focal point. Asset fields hold an id;
  look it up in the `assets` collection. The build copies the CMS's files
  into the site (`cms-files/`), so the live site serves its own.
- **Rich text** — `markdown` fields and an entry's `body_markdown` are the
  CMS's Markdown: draw them with `<RichText value={…} />`, which escapes HTML
  and keeps links safe. Never `set:html` CMS content. `string` and `text`
  fields are plain text.
- **SEO** — `<Seo record={page} assets={assets} siteName="…" />` in `<head>`.
- **Branding** — `<BrandStyles site={site} />` puts Settings › Branding into
  `--brand-*` custom properties; style with them rather than hard-coding the
  brand's colors and font.
- **Links** — link fields are `{ kind: "url" | "page" | "entry", value }`;
  `linkHref(link)` makes the href.

## What the integration does for the site

- `/sitemap.xml` (every URL, with lastmod and hreflang) and `/robots.txt`,
  from the CMS.
- `_redirects` for Cloudflare, from the CMS's redirect rules.
- The site's URL (`site`), its locales (Astro i18n, the default unprefixed)
  and the CMS's files as remote images at the CMS's widths.
- **Static or on demand.** Builds are static by default: publishing in the
  CMS rebuilds the site. With an adapter, pages can render on demand
  (`export const prerender = false`); name the routes meant to in
  `cms({ onDemand: [...] })`. The integration adds `/_cms/webhook`, where the
  CMS sends signed cache purges, and tags each response with what it read.
  Each build tells the CMS which way the site renders.

## Site health

The CMS checks the site against Site health (Docs › Site health): the
business's details, the pages a site needs (contact, privacy, terms…), meta
descriptions, a sharing image, structured data, alt text, spam protection on
forms. **Build the site so every one of those checks passes** — `astro
build` warns about each that fails. Where a check needs content (a privacy
page, a meta description), the content goes in the CMS; where it needs the
site (a contact page that shows the address and a form, `<Seo>` in every
layout), it goes here.

## Changing the CMS itself

Content, fields, collections, block types and settings are changed in the CMS
(its admin, or the `cms` CLI: `curl -fsSL __CMS_URL__/agent/install.sh | sh`),
not from this repo. After a change to fields or block types: `npx
librepublish-astro sync`, `npx astro check`, and commit `cms.lock.json` with
the site's fixes. The only things this repo writes to the CMS are build
reports.
