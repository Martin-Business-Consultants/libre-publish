# libre-publish for Astro

`@libre-publish/astro` is the Astro integration for libre-publish, kept in
the CMS's own repository so the two can't drift apart. It is held to the
delivery API's recorded contract: `contracts/` at the repository's root holds
every `/api/v1` answer a site builds from, recorded from a seeded install by
`spec/contracts/delivery_contract_spec.rb`. The CMS's spec fails when an
answer moves, and this package's tests, which run on the same files, fail
until the integration follows. One pull request changes both.

- **Content, held to the CMS's schema.** Content loaders whose schema is the
  CMS's own (`GET /api/v1/schema`, JSON Schema made into Zod), so a record the
  schema doesn't describe fails the build; types generated from the same
  schema; live collections for pages rendered on demand, checked the same way.
- **A schema lock.** `cms.lock.json` pins the schema the site was written
  against (its digest, `X-CMS-Schema-Digest`). When the CMS's schema moves,
  `astro build` and `astro check` stop and say what changed, until you run
  `npx libre-publish-astro sync`.
- **Rendering.** `<Blocks>` (a component for every block type, enforced),
  `<Image>` (the CMS's renditions as a srcset, with the focal point),
  `<RichText>` (the CMS's Markdown as safe HTML), `<Seo>`, `linkHref` and
  `recordPath`.
- **Site files.** `/sitemap.xml`, `/robots.txt` and Cloudflare `_redirects`,
  all from the CMS. Redirects live in the CMS and nowhere else.
- **Publishing.** A static site is rebuilt when content is published. A site
  rendered on demand gets a signed purge at `/_cms/webhook` instead, and every
  response carries a `Cache-Tag`.

It reads the delivery API (`/api/v1`, [docs/delivery-api.md](../../docs/delivery-api.md)),
which only serves live content, answers in one shape, gives absolute asset
URLs, and delivers only the keys the schema declares. It needs Astro 7.4+
and a libre-publish with the schema digest (`meta.schema_digest`). It's built
for Cloudflare Workers and runs on any adapter.

## Install

```sh
# From a checkout of the CMS (`prepare` builds it):
npm install /path/to/libre-publish/integrations/astro
# or with pnpm, from GitHub, pinned to a commit (npm can't install a subdirectory of a repository):
pnpm add "github:Martin-Business-Consultants/libre-publish#<commit>&path:/integrations/astro"
```

With pnpm, let it build (`allowBuilds` in `pnpm-workspace.yaml`): `prepare` compiles `dist/`.

`.env` (keep it out of git):

```sh
CMS_URL=https://cms.example.com
CMS_TOKEN=…                         # a service token on the "Production site" role
```

The CMS must serve the site over the API: Settings › General › How the site
is served, "API only" (or "Website + API" with the collections chosen).

`astro.config.mjs`:

```js
import { defineConfig } from "astro/config";
import cloudflare from "@astrojs/cloudflare";
import cms from "@libre-publish/astro";

export default defineConfig({
  adapter: cloudflare({ prerenderEnvironment: "node" }),
  integrations: [cms()],
});
```

`src/content.config.ts`. Don't add a `schema` of your own: each loader
brings the CMS's.

```ts
import { defineCollection } from "astro:content";
import { cmsAssets, cmsEntries, cmsGlobals, cmsPages } from "@libre-publish/astro/loaders";

export const collections = {
  pages: defineCollection({ loader: cmsPages() }),
  posts: defineCollection({ loader: cmsEntries("posts") }),   // one per collection the site shows
  globals: defineCollection({ loader: cmsGlobals() }),
  assets: defineCollection({ loader: cmsAssets() }),
};
```

Then pin the schema and check the site against it:

```sh
npx libre-publish-astro sync    # writes cms.lock.json
npx astro check                 # the generated types follow the schema
git add cms.lock.json
```

## The schema lock

`cms.lock.json` records the CMS schema the site is written against: its
digest (`sha256:` of the canonical JSON of `GET /api/v1/schema`'s `data`,
which the CMS computes the same way: `CanonicalJson`), a digest for each
block type, collection, global, page with fields and SEO (so a mismatch can
say what changed), the CMS's URL, API version and `cms_version`. Commit it.

| Command | Lock matches | Lock differs (or is missing) |
|---|---|---|
| `astro build` | builds | **fails**, listing `+ added`, `- removed`, `~ changed` parts (`block_types/hero`, `collections/posts`, …) |
| `astro check`, `astro sync` | checks | **fails**, the same way |
| `astro dev` | runs | warns, rewrites the lock and runs on the new schema |
| `npx libre-publish-astro sync` | refreshes the lock | rewrites the lock, prints what changed |
| `npx libre-publish-astro check` | exit 0 | exit 1, prints what changed |
| any, with `LIBREPUBLISH_ACCEPT_SCHEMA=1` | — | rewrites the lock and goes on |

When someone changes a block type, collection or global in the CMS: run
`npx libre-publish-astro sync`, then `astro check`. The types now follow the
new schema, so it names every component and page to change. Fix them and
commit the lock with the fixes.

## What's enforced

- **Every record matches the schema.** The CMS closes every object it
  describes (`additionalProperties: false`, at every depth: block data,
  nested blocks, groups, repeater items, links, frontmatter, global data,
  SEO) and delivers only the keys they declare. Each loader turns the locked
  schema into Zod, and Astro runs every record through it:
  - an unknown key fails, wherever it is;
  - a required field must hold a value (not null, `""` or `[]`, as the CMS's
    own validator has it); an optional one may be missing or null, and `""`
    reads as null for anything but text;
  - `x-cms-type` adds what JSON Schema can't say: a link's shape (an entry
    link needs its collection), safe URLs, RFC 3339 datetimes, and `blocks`
    fields as a union discriminated by block type, each with its own data
    schema (limited to the field's `x-cms-allowed-types`);
  - a collection list's resolved entries are held to their collection's
    fields;
  - the records around the fields (page, entry, global, asset, block) are
    strict too: a key the CMS starts sending that this package doesn't know
    fails rather than slip by.

  A failure names the record and the field.
- **The build runs on one schema.** Every `/api/v1` answer carries
  `X-CMS-Schema-Digest`; one that differs from the lock during a build stops it.
- **Every block type has a component.** `<Blocks components={…}>` is typed
  `BlockComponents`: a block type left out, or one the CMS doesn't have, is a
  type error, and each component's props are checked against its block's
  data. At build time, content using a block type with no component stops
  the build.
- **Type generation is fatal in a build.**
- **Redirects live in the CMS (Tools › Redirects), and only there.** After a
  build, `_redirects` holds the CMS's rules and nothing else. A site that
  defines its own stops the build.
- **Pages rendered on demand** compare the digest the CMS sends with the one
  they were built with; a mismatch is logged once and the response carries
  `X-CMS-Schema-Stale`. Live collections check each record against the
  schema as the CMS has it now, and answer an error instead of rendering one
  that doesn't fit.

## Pages

Serve each record where the CMS says it lives: `/` for the home page (path
`home`), `/fr/…` for French, `/<collection>/<slug>` for an entry.

```astro
---
import { getCollection } from "astro:content";
import Blocks from "@libre-publish/astro/components/Blocks.astro";
import Seo from "@libre-publish/astro/components/Seo.astro";
import { routeParam } from "@libre-publish/astro/client";
import { components } from "../components/blocks";

export async function getStaticPaths() {
  return (await getCollection("pages")).map(({ data: page }) => ({
    params: { path: routeParam(page, { site: import.meta.env.SITE }) },
    props: { page },
  }));
}
const { page } = Astro.props;                 // typed: Page, from the CMS's schema
const assets = Object.fromEntries((await getCollection("assets")).map((a) => [a.id, a.data]));
---
<html lang={page.locale}>
  <head><Seo record={page} assets={assets} siteName="Acme" /></head>
  <body><Blocks blocks={page.blocks} components={components} assets={assets} /></body>
</html>
```

```ts
// src/components/blocks/index.ts
import type { BlockComponents } from "libre-publish:types";
import Hero from "./Hero.astro";
// …
export const components = { hero: Hero, text: Text, /* every block type */ } satisfies BlockComponents;
```

```astro
---
// src/components/blocks/Hero.astro
import type { BlockProps } from "libre-publish:types";
type Props = BlockProps<"hero">;              // the hero's data, plus block, resolved, assets
const { heading, image_id, assets } = Astro.props;
---
```

- **Blocks.** Each component gets its block's `data` as props, plus `block`,
  `assets` and `resolved`, which is what the CMS filled in: a
  `collection_list` gets its entries (`ListedEntry`, frontmatter typed by
  collection), and `contact_info` gets the contact details. A `blocks` field
  holds blocks of the same shape: render them with another `<Blocks>`.
- **Images.** `<Image asset={assets[id]} sizes="…" />` serves the asset from
  the CMS with its renditions (`srcset`, else `variants`: 640, 1280 and 1920
  wide, which also become Astro's `image.breakpoints`), size, alt text and
  focal point. The CMS's file host (`/rails/active_storage/**`) is added to
  `image.remotePatterns`.
- **Types.** `import type { Page, Entries, Globals, Block, BlockProps, BlockComponents, ListedEntry, AssetId, Link } from "libre-publish:types"`,
  regenerated on every `astro dev`, `astro sync` and `astro build`. An
  optional field is `T | null`. Asset ids and record refs are branded strings
  (`AssetId`, `RecordRef`).
- **Field values.** `markdown` fields (and `body_markdown`) are Markdown:
  draw them with `<RichText value={…} />` or `renderRichText()`, which
  escape HTML and keep links safe. `string` and `text` fields are plain text.
  Link fields go through `linkHref(link)`.

## Pages rendered on demand

The build tells the CMS how the site renders (`POST /api/frontend/builds`). A
**static** site is rebuilt when content is published: point Settings ›
Deploy at a deploy hook. A site that **renders on demand** gets a signed
purge at `/_cms/webhook` instead, and a **hybrid** one gets both. A change of
rendering waits for approval in Settings › Deploy (docs/install.md, "Static
or on demand"). Set these as the Worker's secrets:

- `CMS_WEBHOOK_SECRET`, the purge secret from Settings › Deploy › The site;
- `CLOUDFLARE_ZONE_ID` and `CLOUDFLARE_API_TOKEN` (with Cache Purge), to purge
  Cloudflare's cache by tag.

`/_cms/webhook` checks `X-CMS-Signature` (`sha256=<HMAC-SHA256 of the body>`)
and takes the CMS's purge (`{"event": "cms.purge", "all": …, "tags": […]}`:
those tags, or everything when `all` is true) or a webhook's event: `page.*`
and `entry.*` purge what they name, and `global.updated` purges its global.

On an on-demand page, `Astro.locals.cms` is a client for the request, and
every answer it gets is added to the response's `Cache-Tag`. Live collections
(`@libre-publish/astro/live`) add theirs when you hand the result to
`cacheHint(Astro, result.cacheHint)`:

```ts
// src/live.config.ts
import { defineLiveCollection } from "astro:content";
import { cmsLivePages, cmsLiveEntries } from "@libre-publish/astro/live";
export const collections = {
  livePages: defineLiveCollection({ loader: cmsLivePages() }),
  livePosts: defineLiveCollection({ loader: cmsLiveEntries("posts") }),
};
```

On Cloudflare, prerender in Node (`prerenderEnvironment: "node"`): workerd
doesn't read `.env` at build time. At request time the server reads
`CMS_URL` and `CMS_TOKEN`
from its environment: on Cloudflare, the Worker's variables and secrets;
locally, `.dev.vars`.

## Options

| Option | Default | |
|---|---|---|
| `url`, `token` | `CMS_URL`; `CMS_TOKEN` | Where the CMS is, and the site's service token. |
| `i18n` | `true` | Sets up Astro's i18n from the CMS's locales. Every locale except the default gets a path prefix. |
| `sitemap` | `true` | Adds `/sitemap.xml`, and `/robots.txt` unless `public/robots.txt` exists. After a build, the sitemap keeps only the URLs the site serves. |
| `report` | `true` | Tells the CMS about each build: how the site renders, its webhook, and the content cursor it built from. |
| `localFiles` | `true` | Copies the CMS files the built pages link into the build (`cms-files/`) and points the links at the copies, so the live site serves its own images. Pages rendered on demand still link the CMS. |

## Entry points

| Import | |
|---|---|
| `@libre-publish/astro` | `cms()`, the integration. |
| `@libre-publish/astro/loaders` | `cmsPages`, `cmsEntries`, `cmsGlobals`, `cmsAssets`. |
| `@libre-publish/astro/live` | `cmsLivePages`, `cmsLiveEntries`, `cacheHint`. |
| `@libre-publish/astro/client` | `createClient`, `linkHref`, `recordPath`, `routeParam`, `CmsError`, and the API's types. |
| `@libre-publish/astro/rich-text` | `renderRichText`, `isSafeHref`. |
| `@libre-publish/astro/schema` | `buildSchemas`: the CMS's JSON Schema as Zod. |
| `@libre-publish/astro/components/*.astro` | `Blocks`, `Image`, `RichText`, `Seo`. |
| `libre-publish:types` | Generated from the CMS's schema. |
| `npx libre-publish-astro sync\|check` | The schema lock. |

## Develop

```sh
cd integrations/astro
npm install          # builds dist/ (prepare)
npm run typecheck
npm test             # builds, then runs test/*.test.js on ../../contracts
```

When the CMS's delivery API changes, rewrite the contract
(`RECORD_CONTRACTS=1 bin/rspec spec/contracts/delivery_contract_spec.rb`),
then make these tests pass on the new files in the same pull request.

Ported from `@librepublish/astro` 0.8.2 (the Go core's integration). Not
carried over: Forms (`<Form>`, `<StaticForm>`, form hooks), branding
(`<BrandStyles>`), Site health findings and the launch checklist, which
belong to the Go core's plugins and API.
