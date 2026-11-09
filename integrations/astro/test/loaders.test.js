// The content loaders: the CMS's /content once per build, every record
// checked against the locked schema, deltas applied.
import { test } from "node:test";
import assert from "node:assert/strict";
import { keepConnection, keepSchema, buildState } from "../dist/build-connection.js";
import { cmsAssets, cmsEntries, cmsGlobals, cmsPages } from "../dist/loaders.js";
import { fakeContext, fakeFetch, fixture } from "./helpers.js";

const schema = fixture("schema");
const digest = schema.meta.schema_digest;
const full = fixture("content-full");
full.meta.cursor = "cursor-1";

// What a read with ?since= gives after a publish (the CMS's shape: changed records, and what stopped being live).
const delta = {
  data: {
    pages: [{ ...structuredClone(full.data.pages.find((page) => page.path === "about")), title: "About us" }],
    entries: [],
    globals: [],
    removed: { pages: [{ id: 0, path: "company" }], entries: [{ id: 0, collection: "posts", slug: "second" }], globals: [] },
  },
  meta: { cursor: "cursor-2", full: false, since: "2026-01-01T00:00:00Z" },
};

function serve(content = full, headers = { "X-CMS-Schema-Digest": digest }) {
  const { fetcher, calls } = fakeFetch({
    "/api/v1/content": { body: content, headers },
    "/api/v1/content?since=cursor-1": { body: delta, headers },
  });
  globalThis.fetch = fetcher;
  return calls;
}

keepConnection({ url: "https://cms.test", token: "t" });
keepSchema(Promise.resolve({ schema: schema.data, digest }));

test("createSchema gives Astro the CMS's schema as Zod and the TypeScript of its entries", async () => {
  const { schema: zod, types } = await cmsPages().createSchema();
  assert.ok(zod.safeParse(full.data.pages[0]).success);
  assert.match(types, /export type Entry = Page;/);
  assert.match(types, new RegExp(`Schema digest: ${digest}`));
  const posts = await cmsEntries("posts").createSchema();
  assert.match(posts.types, /export type Entry = Entries\["posts"\];/);
  await assert.rejects(cmsEntries("nope").createSchema(), /no collection "nope"/);
});

test("loaders load everything, check each record, then apply a delta and drop what stopped being live", async () => {
  buildState().digests.clear();
  serve();
  const pages = fakeContext((await cmsPages().createSchema()).schema);
  await cmsPages().load(pages.context);
  assert.deepEqual([...pages.entries.keys()].sort(), full.data.pages.map((page) => page.path).sort());
  assert.equal(pages.meta.cursor, "cursor-1");

  const posts = fakeContext((await cmsEntries("posts").createSchema()).schema);
  await cmsEntries("posts").load(posts.context);
  assert.deepEqual([...posts.entries.keys()].sort(), full.data.entries.filter((e) => e.collection === "posts").map((e) => e.slug).sort());

  const globals = fakeContext((await cmsGlobals().createSchema()).schema);
  await cmsGlobals().load(globals.context);
  assert.deepEqual([...globals.entries.keys()], full.data.globals.map((g) => g.slug));

  const assets = fakeContext((await cmsAssets().createSchema()).schema);
  await cmsAssets().load(assets.context);
  assert.deepEqual([...assets.entries.keys()].sort(), Object.keys(full.included.assets).sort());

  await cmsPages().load(pages.context);
  assert.equal(pages.entries.get("about").data.title, "About us", "the delta was applied");
  assert.ok(!pages.entries.has("company"), "a page that stopped being live is dropped");
  assert.equal(pages.meta.cursor, "cursor-2");
  await cmsEntries("posts").load(posts.context);
  assert.ok(!posts.entries.has("second"));
  assert.ok(posts.entries.has("hello-world"));
});

test("a collection kept from a build against another schema is read whole again", async () => {
  const calls = serve();
  const pages = fakeContext((await cmsPages().createSchema()).schema, { cursor: "cursor-1", source: "https://cms.test sha256:older" });
  await cmsPages().load(pages.context);
  assert.ok(calls.every((call) => !call.url.includes("since=")), "no delta across schemas");
  assert.equal(pages.meta.source, `https://cms.test ${digest}`);
});

test("a record outside the schema fails the load, naming it", async () => {
  const bad = structuredClone(full);
  bad.data.pages.find((page) => page.path === "about").blocks[0].data.stale = 1;
  serve(bad);
  // A cursor the fake doesn't know is answered with the (bad) full snapshot, past the loaders' shared read of it.
  const pages = fakeContext((await cmsPages().createSchema()).schema, { cursor: "unknown-cursor", source: `https://cms.test ${digest}` });
  await assert.rejects(cmsPages().load(pages.context), /about: blocks\.0\.data.*stale/);
});

test("an answer from another schema during the build stops it", async () => {
  buildState().digests.clear();
  serve(full, { "X-CMS-Schema-Digest": "sha256:somethingelse" });
  const globals = fakeContext((await cmsGlobals().createSchema()).schema, {});
  await assert.rejects(cmsGlobals().load({ ...globals.context, meta: { get: (key) => (key === "source" ? `https://cms.test ${digest}` : "x-unknown"), set() {} } }), /schema changed during the build/);
  buildState().digests.clear();
});
