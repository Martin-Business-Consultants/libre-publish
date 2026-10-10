---
title: "Working with an Astro site"
summary: "Connect a site in one line, load pages, entries and globals, and build it to pass Site health."
position: 2
---

The site is an Astro app in its own repo, deployed to Cloudflare. It reads
this CMS through the `@librepublish/astro` integration and renders what it
gets; nothing about the site's look lives here.

## Connect it

In the site's project (its root or its `src/`):

```sh
curl -fsSL {{cms_url}}/frontend/install.sh | sh
```

It installs `@librepublish/astro` — Forms and Media, this CMS's default
plugins, are part of it, and Commerce's quotes — gets the site a
**read-only service token of its own** (you approve it in your browser,
signed in here), and writes it to `.env` with the CMS's address.
Then add the integration to `astro.config.mjs`:

```js
import { defineConfig } from "astro/config";
import cloudflare from "@astrojs/cloudflare";
import cms from "@librepublish/astro";

export default defineConfig({
  adapter: cloudflare({ prerenderEnvironment: "node" }), // to render pages on demand
  integrations: [cms()],
});
```

Set the same variables where the site builds and runs:

```sh
CMS_BASE_URL={{cms_url}}
CMS_API_TOKEN=…   # the site's service token
```

From then on, every `astro dev` and `astro build` writes **`AGENTS.md`** into
the site's repo — how the site works with this CMS, and the Site health
checks it's held to, for an AI working there. Commit it. The integration's
source is at github.com/Martin-Business-Consultants/libre-cms-astro.

## Load content

Content comes in through content collections, in `src/content.config.ts`:

```ts
import { defineCollection } from "astro:content";
import { cmsPages, cmsEntries, cmsGlobals, cmsAssets } from "@librepublish/astro/loaders";

export const collections = {
  pages: defineCollection({ loader: cmsPages() }),
  posts: defineCollection({ loader: cmsEntries("posts") }),
  globals: defineCollection({ loader: cmsGlobals() }),
  assets: defineCollection({ loader: cmsAssets() }),
};
```

The loaders read the delivery API (`{{cms_url}}/api/v1`), only what's
published, and after the first build only what changed. Types for every
block type, collection and global are generated from this CMS's schema:
`import type { Block, Collections, Globals } from "librepublish:types"`.

Route every page by its **`url`** — where the CMS says it's served. The
home page's is `/`; anything in a language other than the default is under
its locale's prefix (`/fr/a-propos`).

```astro
---
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

## Render it

```astro
---
import Blocks from "@librepublish/astro/components/Blocks.astro";
import Seo from "@librepublish/astro/components/Seo.astro";
import Hero from "../components/blocks/Hero.astro";
import Prose from "../components/blocks/Prose.astro";
---
<head><Seo record={page} assets={assets} siteName="Acme" /></head>
<Blocks blocks={page.blocks} components={{ hero: Hero, prose: Prose }} assets={assets} />
```

- **Blocks** — each component gets its block's data as props. A type without
  a component is skipped, so editors can add a block type before it has one.
- **Images** — `<Image asset={assets[id]} />` serves an asset from here with
  its renditions, size and alt text.
- **Links** — `linkHref(link)` from `@librepublish/astro/client`.
- **Rich text** (`text`) is HTML: render it with `set:html`. **Markdown**
  fields are Markdown.

## Forms and quotes

- **Forms**, with the Forms plugin (on by default) — `<Form slug="contact" />`
  from `@librepublish/astro/components/Form.astro`. The browser posts
  straight here, with Cloudflare Turnstile when Settings › Forms has it, so Settings › General's
  site URL (and any other origins) must be right.
- **Form emails**, likewise — a route at
  `src/pages/emails/[form]/[kind].astro` (helpers from
  `@librepublish/astro/forms`) gives each form's emails the site's design,
  and `cms()` sends the templates here after each build. Until a build sends
  a template for an email's current blocks, it goes out in the CMS's own
  layout.
- **Quotes**, with Commerce — `<QuoteRequest items={[…]} />` from
  `@librepublish/astro/components/QuoteRequest.astro`.

## Builds

Each build writes `_redirects` (Tools › Redirects), `/sitemap.xml` and
`/robots.txt`, and tells this CMS it ran — Developers shows the last one —
and how the site renders:

- **Static** (the default): publishing here rebuilds the site (Settings ›
  Deploy: a Cloudflare deploy hook, a GitHub dispatch, or another build hook).
- **On demand**, with the Cloudflare adapter: publishing sends the site a
  signed purge naming what changed, at `/_cms/webhook`. Give the site the
  secret from Settings › Deploy as `CMS_WEBHOOK_SECRET`, and
  `CLOUDFLARE_ZONE_ID` and `CLOUDFLARE_API_TOKEN` to purge Cloudflare's cache.

## Site health

Every build checks the site against **Site health** (Docs › Site health) and
warns about each check that fails — `cms({ siteHealth: "error" })` makes it
stop. Build the site so all of them pass: a contact page with the address,
phone and a form; privacy and terms pages; `<Seo>` in every layout, so meta
descriptions and sharing images reach the page; alt text on every image the
site shows. The checks about running this CMS (backups, two-factor) aren't
the site's.
