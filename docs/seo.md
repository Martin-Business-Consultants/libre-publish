# Search and AI

What a Libre Publish website does for search engines (Google, Bing) and AI
answer engines (ChatGPT search, Perplexity, Claude, Gemini, Copilot) so
they find it, understand it and cite it. All of it comes from the content
and Settings, with nothing for a theme to add beyond calling
`website_seo_tags` in its `<head>`.

## Every page's `<head>` (`website_seo_tags`)

- **Title and description** from the SEO panel, else the page's title and
  the keywords the theme passes.
- **Canonical** address: the panel's, else the page's own.
- **Robots**: `index, follow, max-image-preview:large, max-snippet:-1` for a
  page search may show (the large preview and the full snippet are what
  Google Discover and AI overviews use), `noindex` when the panel hides it,
  `nofollow` when it asks.
- **hreflang** for each language a page is in, with `x-default`.
- **Open Graph and Twitter**, with the panel's overrides (title,
  description, type, card), the share image's size and alt text, and an
  entry's published and modified dates.
- **A Markdown alternate** (`<link rel="alternate" type="text/markdown">`).
- **Structured data** (schema.org JSON-LD, one `@graph`): the organization
  behind the site (Settings › General, Search and Branding: its name,
  contact details, address for a local business, logo and profiles
  elsewhere), the WebSite, the page itself — as the SEO panel's schema.org
  type, an Article for an entry, else a WebPage — and its breadcrumbs. A
  page with its own JSON-LD in the panel keeps it, with the organization,
  site and breadcrumbs beside it.

## Files for crawlers

- **`/sitemap.xml`**: every published page and entry not hidden from
  search, with its last change and its translations.
- **`/robots.txt`**: open to search engines except `/cms/` and `/api/`, and
  where the sitemap is. Settings › Search lets in or keeps out AI crawlers
  by what they do: *answer engines* that cite and link to the site
  (OAI-SearchBot, PerplexityBot, Claude-SearchBot…) and *training*
  crawlers (GPTBot, ClaudeBot, Google-Extended, CCBot…), separately.
  Blocking training doesn't take the site out of search or AI answers.
  The Sitemap screen's **robots.txt** adds extra rules to that, or replaces
  it with a file written by hand, and says what's likely wrong (no sitemap
  line, the whole site disallowed, lines crawlers won't read). A headless
  install's own host disallows everything: its site is elsewhere, and its
  frontend publishes the site's robots.txt from `/api/v1/robots`.
- **`/llms.txt`**: the site's name and description, then every page and
  each collection's entries, linking to their Markdown with their
  descriptions ([llmstxt.org](https://llmstxt.org)).
- **`/<page>.md`**: any page or entry as clean Markdown (`/index.md` for
  the home page): its title, description, body and blocks, in order,
  without the design. A page hidden from search has none.

## Telling search engines, and checking

- **IndexNow**: a published, changed or removed page or entry is announced
  to IndexNow's search engines (Bing, Yandex, Seznam, Naver…) the moment it
  happens, with the key the site serves at `/<key>.txt`. Only for a website
  on a public address (Settings › General's site URL); Settings › Search
  turns it off. Google doesn't take IndexNow; it reads the sitemap.
- **Feeds**: `/<collection>/feed.xml` for each collection the theme draws,
  linked from every page's `<head>`.
- **Tools › SEO audit** lists what to fix across the site, and each page's
  SEO tab its own: missing or poorly sized descriptions, long titles,
  duplicates, links to pages that don't exist, images without alt text,
  and the site-wide details.

## What makes the difference

The machinery is here; what search and AI reward is still the content:

- A meta description on every page that says what it answers.
- One clear title per page, and headings that outline it.
- Alt text on every image (Media › an image).
- Settings › General filled in (name, description, contact details, the
  site's address), and Settings › Search's profiles elsewhere, so
  everything said about the business ties back to it.
- Redirects (Tools › Redirects) for every address that changes.
