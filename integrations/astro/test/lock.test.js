// cms.lock.json: the schema a site was checked against, and what each
// command does when the CMS's has moved.
import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, readFile, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { accepted, decide, describeChanges, lockFrom, readLock, writeLock, LOCK_FILE } from "../dist/lock.js";
import { readLive } from "../dist/schema/live.js";
import { createClient } from "../dist/client.js";
import { main } from "../dist/cli.js";
import { contractIndex, envelope, fakeFetch, fixture } from "./helpers.js";

const live = (digest, parts = {}) => ({ cmsUrl: "https://cms.test", apiVersion: "v1", cmsVersion: "1.36.0", digest, parts });

test("same digest: every command goes on", () => {
  const lock = lockFrom(live("sha256:a"));
  for (const command of ["dev", "build", "sync", "preview"]) assert.deepEqual(decide(lock, live("sha256:a"), { command, accept: false }), { action: "ok" });
});

test("a moved schema fails build and sync (astro check), naming what was added, removed and changed", () => {
  const lock = lockFrom(live("sha256:aaaa", { "block_types/hero": "1", "block_types/old": "2", seo: "3" }));
  const now = live("sha256:bbbb", { "block_types/hero": "9", "block_types/promo": "4", seo: "3" });
  for (const command of ["build", "sync"]) {
    const decision = decide(lock, now, { command, accept: false });
    assert.equal(decision.action, "fail");
    assert.match(decision.message, /\+ block_types\/promo/);
    assert.match(decision.message, /- block_types\/old/);
    assert.match(decision.message, /~ block_types\/hero/);
    assert.doesNotMatch(decision.message, /seo/);
    assert.match(decision.message, /npx libre-publish-astro sync/);
  }
});

test("dev takes the new schema with a warning; LIBREPUBLISH_ACCEPT_SCHEMA=1 takes it anywhere", () => {
  const lock = lockFrom(live("sha256:aaaa"));
  const dev = decide(lock, live("sha256:bbbb"), { command: "dev", accept: false });
  assert.equal(dev.action, "write");
  assert.equal(dev.level, "warn");
  assert.equal(decide(lock, live("sha256:bbbb"), { command: "build", accept: true }).action, "write");
  assert.equal(accepted({ LIBREPUBLISH_ACCEPT_SCHEMA: "1" }), true);
  assert.equal(accepted({ LIBREPUBLISH_ACCEPT_SCHEMA: "0" }), false);
  assert.equal(accepted({}), false);
});

test("no lock: a build stops; dev and an accepted build write one", () => {
  assert.equal(decide(null, live("sha256:a"), { command: "build", accept: false }).action, "fail");
  assert.equal(decide(null, live("sha256:a"), { command: "sync", accept: false }).action, "fail");
  assert.equal(decide(null, live("sha256:a"), { command: "dev", accept: false }).action, "write");
  assert.equal(decide(null, live("sha256:a"), { command: "build", accept: true }).action, "write");
});

test("describeChanges lists added, removed and changed parts, sorted", () => {
  assert.deepEqual(describeChanges({ a: "1", b: "2", c: "3" }, { b: "2", c: "4", d: "5" }), ["- a", "~ c", "+ d"]);
});

test("the lock is read and written as committed JSON", async () => {
  const root = await mkdtemp(join(tmpdir(), "lp-lock-"));
  assert.equal(await readLock(root), null);
  await writeLock(root, lockFrom(live("sha256:a", { "block_types/x": "1" })));
  const text = await readFile(join(root, LOCK_FILE), "utf8");
  assert.ok(text.endsWith("}\n"));
  assert.equal((await readLock(root)).schema_digest, "sha256:a");
  await writeFile(join(root, LOCK_FILE), JSON.stringify({ lock_version: 9 }));
  await assert.rejects(readLock(root), /libre-publish-astro sync/);
});

function cms(schema = fixture("schema")) {
  const headers = contractIndex().schema.headers;
  return fakeFetch({
    "/api/v1/site": { body: fixture("site"), headers },
    "/api/v1/schema": { body: schema, headers },
  });
}

test("readLive takes the CMS's digest and version, and a digest per part", async () => {
  const schema = fixture("schema");
  const client = createClient({ url: "https://cms.test", token: "t", fetch: cms().fetcher });
  const read = await readLive(client, await client.site(), "https://cms.test");
  assert.equal(read.live.digest, schema.meta.schema_digest);
  assert.equal(read.live.cmsVersion, "1.36.0");
  assert.equal(read.live.apiVersion, "v1");
  assert.ok(read.live.parts["block_types/every_field"]);
  assert.ok(read.live.parts["collections/posts"]);
  assert.ok(read.live.parts["globals/footer"]);
  assert.ok(read.live.parts.seo);
  assert.equal(lockFrom(read.live).cms_version, "1.36.0");

  // A CMS that sends no digest is older than this package reads.
  const old = createClient({ url: "https://cms.test", token: "t", fetch: fakeFetch({ "/api/v1/schema": { body: envelope(schema.data) } }).fetcher });
  await assert.rejects(readLive(old, null, "https://cms.test"), /no schema digest/);
});

test("libre-publish-astro sync writes the lock; check exits 1 once the CMS moves, naming the part", async () => {
  const root = await mkdtemp(join(tmpdir(), "lp-cli-"));
  const lines = [];
  const out = (line) => lines.push(line);
  process.env.CMS_URL = "https://cms.test";
  process.env.CMS_TOKEN = "t";
  const saved = globalThis.fetch;
  try {
    globalThis.fetch = cms().fetcher;
    assert.equal(await main(["check", "--root", root], out), 1, "no lock yet");
    assert.equal(await main(["sync", "--root", root], out), 0);
    assert.equal((await readLock(root)).schema_digest, fixture("schema").meta.schema_digest);
    assert.equal(await main(["check", "--root", root], out), 0);

    const moved = fixture("schema");
    moved.data.block_types.promo = { title: "Promo", version: 1, deprecated: false, data: { type: "object", additionalProperties: false, properties: {}, required: [] } };
    delete moved.data.block_types.retired;
    moved.data.block_types.text.data.properties.body.title = "Text body";
    moved.meta.schema_digest = "sha256:moved";
    globalThis.fetch = cms(moved).fetcher;
    lines.length = 0;
    assert.equal(await main(["check", "--root", root], out), 1);
    const said = lines.join("\n");
    assert.match(said, /\+ block_types\/promo/);
    assert.match(said, /- block_types\/retired/);
    assert.match(said, /~ block_types\/text/);
  } finally {
    globalThis.fetch = saved;
    delete process.env.CMS_URL;
    delete process.env.CMS_TOKEN;
  }
});
