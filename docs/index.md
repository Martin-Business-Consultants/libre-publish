# Libre Publish

A small, fast CMS for websites, from a one-page business site to a
publication: an admin that edits like WordPress, a theme system with no
build step, plugins with a compatibility promise, and an API, CLI and MCP
surface that AI agents use as well as people do.

- **One install is one site**, in one container, with SQLite for
  everything. Back it up by copying a folder.
- **The CMS draws the site** from a theme (plain ERB and CSS, no build), or
  stays headless and serves any frontend through its delivery API.
- **Search and AI built in**: structured data, `llms.txt`, a Markdown copy
  of every page, IndexNow, an SEO audit.
- **A small core, extended by plugins**: Forms, WordPress Import and the
  rest install from Settings › Plugins, reviewed in a signed directory.
- **Updates in place**, from Settings › Updates, with a backup first.

## Start here

| If you want to… | Read |
| --- | --- |
| Run your own | [Install](install.md) |
| Build a website's design | [Themes](themes.md) |
| Be found by search engines and AI | [Search and AI](seo.md) |
| Add a feature | [Plugins](plugins.md) |
| Know what stays stable | [Compatibility](compatibility.md) |
| Build a site elsewhere (Astro, Next…) | [Delivery API](delivery-api.md) |
| React to changes | [Webhooks](webhooks.md) |
| Let an AI agent work on a site | [Agents: API, CLI and MCP](agent-interface.md) |
| Know why it's built this way | [Vision](vision.md) |

## Try it

```sh
git clone https://github.com/Martin-Business-Consultants/libre-publish
cd libre-publish
mise install      # Ruby
bin/setup         # gems, databases, sample content, then the server
                  # http://localhost:3000/cms, sign in as alice@site.test / password1234
```

Coming from WordPress? Install the WordPress Import plugin and bring the
site over from its export file: pages, posts, images, SEO and redirects.

Every release is in the [changelog](changelog.md).
