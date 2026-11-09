import { test } from "node:test";
import assert from "node:assert/strict";
import { createClient, CmsError } from "../dist/client.js";
import { redirectRules, REDIRECTS_LIVE_IN_THE_CMS } from "../dist/redirects.js";
import { connectionFrom } from "../dist/build-connection.js";
import cms from "../dist/index.js";
import { contractIndex, envelope, fakeFetch, fixture } from "./helpers.js";

test("the client sends the token, collects cache tags and schema digests", async () => {
  const { fetcher, calls } = fakeFetch({
    "/api/v1/pages/about": { body: envelope({ path: "about" }), headers: { "Cache-Tag": "page:about,pages", "X-CMS-Schema-Digest": "sha256:abc" } },
  });
  const cms = createClient({ url: "https://cms.test/", token: "t0k", fetch: fetcher });
  const { data } = await cms.page("/about/");
  assert.equal(data.path, "about");
  assert.equal(calls[0].url, "https://cms.test/api/v1/pages/about");
  assert.equal(calls[0].init.headers.Authorization, "Bearer t0k");
  assert.deepEqual([...cms.tags], ["page:about", "pages"]);
  assert.deepEqual([...cms.digests], ["sha256:abc"]);
});

test("the client follows every page of a list and merges the assets", async () => {
  const { fetcher } = fakeFetch({
    "/api/v1/pages?per=100&page=1": { body: envelope([{ path: "a" }], { next_page: 2 }, { assets: { 1: { id: 1 } } }) },
    "/api/v1/pages?per=100&page=2": { body: envelope([{ path: "b" }], { next_page: null }, { assets: { 2: { id: 2 } } }) },
  });
  const cms = createClient({ url: "https://cms.test", token: "t", fetch: fetcher });
  const { data, included } = await cms.pages();
  assert.deepEqual(data.map((page) => page.path), ["a", "b"]);
  assert.deepEqual(Object.keys(included.assets), ["1", "2"]);
});

test("a refused token is a CmsError that says so; a 403 names the capability", async () => {
  const { fetcher } = fakeFetch({
    "/api/v1/site": { body: { error: "unauthorized", message: "…" }, status: 401 },
    "/api/v1/schema": { body: { error: "forbidden", capability: "block_types:read" }, status: 403 },
  });
  const cms = createClient({ url: "https://cms.test", token: "bad", fetch: fetcher });
  await assert.rejects(cms.site(), (error) => error instanceof CmsError && error.status === 401 && /refused/.test(error.message));
  await assert.rejects(cms.schema(), (error) => error.status === 403 && /block_types:read/.test(error.message));
});

test("the client posts the build report as POST /api/frontend/builds takes it", async () => {
  const { fetcher, calls } = fakeFetch({
    "/api/frontend/builds": { body: { build: { render: "hybrid" }, pending_delivery: { render: "hybrid" } }, status: 200 },
  });
  const cms = createClient({ url: "https://cms.test", token: "t", fetch: fetcher });
  const answer = await cms.reportBuild({ render: "hybrid", content_cursor: "c1", webhook_url: "https://acme.test/_cms/webhook" });
  assert.deepEqual(answer.pending_delivery, { render: "hybrid" });
  assert.equal(calls[0].init.method, "POST");
  assert.deepEqual(JSON.parse(calls[0].init.body), { render: "hybrid", content_cursor: "c1", webhook_url: "https://acme.test/_cms/webhook" });
});

test("a 404 is a CmsError carrying the CMS's message", async () => {
  const missing = fixture("page-missing");
  const { fetcher } = fakeFetch({ "/api/v1/pages/nowhere": { body: missing, status: contractIndex()["page-missing"].status } });
  const cms = createClient({ url: "https://cms.test", token: "t", fetch: fetcher });
  await assert.rejects(cms.page("nowhere"), (error) => error instanceof CmsError && error.status === 404 && error.message.includes(missing.message));
});

test("the connection: CMS_BASE_URL or CMS_URL, CMS_API_TOKEN or PRODUCTION_TOKEN, a trailing /api dropped", () => {
  const from = (env) => connectionFrom((name) => env[name]);
  assert.deepEqual(from({ CMS_BASE_URL: "https://a.test/", CMS_API_TOKEN: "t" }), { url: "https://a.test", token: "t" });
  assert.deepEqual(from({ CMS_URL: "https://b.test/api/v1", PRODUCTION_TOKEN: "p" }), { url: "https://b.test", token: "p" });
  assert.deepEqual(from({ CMS_BASE_URL: "https://a.test", CMS_URL: "https://b.test", CMS_API_TOKEN: "t", PRODUCTION_TOKEN: "p" }), { url: "https://a.test", token: "t" }, "the integration's own names first");
  assert.equal(from({ CMS_URL: "https://b.test" }), null);
  assert.equal(from({ CMS_URL: "https://b.test", PRODUCTION_TOKEN: " " }), null);
  assert.deepEqual(connectionFrom(() => undefined, { url: "https://o.test", token: "o" }), { url: "https://o.test", token: "o" });
});

test("linkHref turns a CMS link into an href, home at the root", async () => {
  const { linkHref } = await import("../dist/client.js");
  assert.equal(linkHref({ kind: "url", value: "https://x.test" }), "https://x.test");
  assert.equal(linkHref({ kind: "page", value: "home" }), "/");
  assert.equal(linkHref({ kind: "page", value: "about/team" }), "/about/team");
  assert.equal(linkHref({ kind: "page", value: "home" }, { locale: "fr", defaultLocale: "en" }), "/fr");
  assert.equal(linkHref({ kind: "entry", value: "hello", collection: "posts" }), "/posts/hello");
  assert.equal(linkHref(null), undefined);
});

test("recordPath routes by url, and by the record's own path when a canonical points elsewhere", async () => {
  const { recordPath, routeParam } = await import("../dist/client.js");
  const { pages, entries } = fixture("content-full").data;
  const site = fixture("site").data.url;
  const home = pages.find((page) => page.path === "home");
  assert.equal(recordPath(home, { site }), "/");
  for (const page of pages.filter((p) => p.path !== "home")) assert.equal(recordPath(page, { site }), `/${page.path}`, page.path);
  assert.equal(recordPath(pages.find((page) => page.path === "company/team"), { site }), "/company/team");
  for (const entry of entries) assert.equal(recordPath(entry, { site }), `/${entry.collection}/${entry.slug}`);
  assert.equal(recordPath({ url: "/fr/a-propos", path: "a-propos", locale: "fr" }), "/fr/a-propos");
  assert.equal(recordPath({ url: "https://acme.test/landing", path: "about", locale: "en" }, { site: "https://acme.test" }), "/landing");
  assert.equal(recordPath({ url: "https://partner.test/x", path: "about", locale: "en" }, { site: "https://acme.test" }), "/about");
  assert.equal(recordPath({ url: "https://partner.test/x", path: "home", locale: "fr" }, { site: "https://acme.test", defaultLocale: "en" }), "/fr");
  assert.equal(routeParam({ url: "/", path: "home", locale: "en" }), undefined);
  assert.equal(routeParam({ url: "/posts/hi", collection: "posts", slug: "hi", locale: "en" }), "posts/hi");
});

test("the version reported to the CMS is package.json's", async () => {
  const { VERSION, NAME } = await import("../dist/index.js");
  const { readFile } = await import("node:fs/promises");
  const pkg = JSON.parse(await readFile(new URL("../package.json", import.meta.url), "utf8"));
  assert.equal(VERSION, pkg.version);
  assert.equal(NAME, "libre-publish");
});

test("the integration's entry loads in plain Node: nothing it imports needs Astro's virtual modules", async () => {
  const { readFile } = await import("node:fs/promises");
  const seen = new Set();
  async function walk(file) {
    if (seen.has(file)) return;
    seen.add(file);
    const source = await readFile(new URL(file, import.meta.url), "utf8");
    assert.doesNotMatch(source, /^(import|export)[^;]*from "astro:/m, `${file} imports an astro: module`);
    for (const [, spec] of source.matchAll(/^(?:import|export)[^;]*from "(\.{1,2}\/[^"]+)"/gm)) await walk(new URL(spec, new URL(file, import.meta.url)).href);
  }
  await walk("../dist/index.js");
  assert.ok(seen.size > 5);
});

test("sitemap.xml keeps only what the site serves: built pages and on-demand routes", async () => {
  const { servedSitemap } = await import("../dist/sitemap-filter.js");
  const url = (loc) => `  <url>\n    <loc>${loc}</loc>\n  </url>\n`;
  const xml = `<?xml version="1.0"?>\n<urlset>\n${url("https://acme.test/")}${url("https://acme.test/about")}${url("https://acme.test/categories/appetizer")}${url("https://acme.test/live/x")}${url("https://acme.test/posts/a&amp;b")}</urlset>\n`;
  const { xml: kept, removed } = servedSitemap(xml, ["", "about/", "posts/a&b"], [/^\/live(?:\/(.*?))?\/?$/]);
  assert.deepEqual(removed, ["/categories/appetizer"]);
  assert.match(kept, /acme\.test\/about/);
  assert.match(kept, /acme\.test\/live\/x/);
  assert.match(kept, /a&amp;b/);
  assert.doesNotMatch(kept, /appetizer/);
});

test("the webhook URL the build reports matches the route under the site's trailingSlash", async () => {
  const { webhookPath } = await import("../dist/index.js");
  assert.equal(webhookPath("always"), "/_cms/webhook/");
  assert.equal(webhookPath("never"), "/_cms/webhook");
  assert.equal(webhookPath("ignore"), "/_cms/webhook");
  assert.equal(webhookPath(undefined), "/_cms/webhook");
});

test("sitemap URLs take the site's trailingSlash form", async () => {
  const { slashed } = await import("../dist/sitemap-filter.js");
  const site = "https://acme.test";
  assert.equal(slashed("https://acme.test/about", "always", site), "https://acme.test/about/");
  assert.equal(slashed("https://acme.test/about/", "always", site), "https://acme.test/about/");
  assert.equal(slashed("https://acme.test/fr/a-propos?x=1#y", "always", site), "https://acme.test/fr/a-propos/?x=1#y");
  assert.equal(slashed("https://acme.test/about/", "never", site), "https://acme.test/about");
  assert.equal(slashed("https://acme.test/about", "ignore", site), "https://acme.test/about");
  assert.equal(slashed("https://acme.test/about", undefined, site), "https://acme.test/about");
  assert.equal(slashed("https://acme.test/", "never", site), "https://acme.test/");
  assert.equal(slashed("https://acme.test", "always", site), "https://acme.test");
  assert.equal(slashed("https://acme.test/feed.xml", "always", site), "https://acme.test/feed.xml");
  assert.equal(slashed("https://elsewhere.test/about", "always", site), "https://elsewhere.test/about");
  assert.equal(slashed("/posts/hello", "always"), "/posts/hello/");
});

test("the delivery fixtures have the shapes the runtime routes read", () => {
  const sitemap = fixture("sitemap");
  assert.ok(sitemap.data.length > 0);
  for (const url of sitemap.data) {
    assert.deepEqual(Object.keys(url).sort(), ["alternates", "changefreq", "lastmod", "locale", "path", "priority", "url"]);
    for (const alternate of url.alternates) assert.deepEqual(Object.keys(alternate).sort(), ["locale", "url"]);
  }
  const robots = fixture("robots").data;
  assert.equal(typeof robots.text, "string");
  assert.ok(["generated", "custom"].includes(robots.mode));
  const site = fixture("site");
  assert.equal(typeof site.meta.cms_url, "string");
  assert.equal(site.meta.api_version, "v1");
  assert.equal(typeof site.meta.cms_version, "string");
  assert.deepEqual(Object.keys(site.data).sort(), ["contact", "default_locale", "description", "locales", "name", "plugin_config", "plugins", "url"]);
  for (const redirect of fixture("redirects").data) assert.deepEqual(Object.keys(redirect).sort(), ["destination", "source", "status", "wildcard"]);
  // Asset URLs are Active Storage's, on the CMS's host: what localFiles and image.remotePatterns match.
  for (const value of Object.values(fixture("page-home").included.assets)) assert.match(value.url, /\/rails\/active_storage\//);
});

test("redirects live in the CMS: a site's own rules are found, comments aren't", () => {
  assert.deepEqual(redirectRules(""), []);
  assert.deepEqual(redirectRules("# a comment\n\n   \n# From the CMS (Tools › Redirects)\n"), []);
  assert.deepEqual(redirectRules("/old /new 301\n# note\n  /a/* /b/:splat 302  \n"), ["/old /new 301", "/a/* /b/:splat 302"]);
});

test("redirects live in the CMS: cms({ redirects }) is refused", () => {
  assert.throws(() => cms({ redirects: false }), (e) => e.message.includes(REDIRECTS_LIVE_IN_THE_CMS));
  assert.throws(() => cms({ redirects: true }), /is gone/);
  assert.doesNotThrow(() => cms({}));
});

test("redirects live in the CMS: astro.config's redirects stop the build", async () => {
  const hook = cms({}).hooks["astro:config:setup"];
  const args = (redirects) => ({
    config: { root: new URL("file:///tmp/site/"), trailingSlash: "ignore", redirects },
    command: "build", updateConfig() {}, injectRoute() {}, addMiddleware() {}, addWatchFile() {},
    logger: { info() {}, warn() {}, error() {} },
  });
  await assert.rejects(hook(args({ "/old": "/new" })), (e) => e.message.includes(REDIRECTS_LIVE_IN_THE_CMS) && e.message.includes("/old"));
});
