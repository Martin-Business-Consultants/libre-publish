// The integration's half of the contract (contracts/ at the repository's
// root). spec/contracts/delivery_contract_spec.rb holds the CMS to those
// files; this holds the integration to the same ones: its canonical JSON
// reproduces the CMS's schema digest, it reads every recorded answer, and its
// purge webhook understands what the CMS sends.
import { test } from "node:test";
import assert from "node:assert/strict";
import { existsSync } from "node:fs";
import { canonicalJson, digestOf, partDigests } from "../dist/schema/digest.js";
import { SCHEMA_DIGEST_HEADER } from "../dist/client.js";
import { plan } from "../dist/runtime/purge.js";
import { contractIndex, contracts, fixture, fixturePath, webhookContract } from "./helpers.js";

const index = contractIndex();
const schema = fixture("schema");

test("every answer the index names is recorded, and parses", () => {
  const names = Object.keys(index);
  assert.ok(names.length >= 15, "the contract records the delivery API's answers");
  for (const name of names) {
    assert.ok(existsSync(fixturePath(name)), `contracts/delivery/${name}.json`);
    assert.equal(index[name].request.method, "GET", name);
    assert.match(index[name].request.path, /^\/api\/v1\//, name);
  }
  assert.equal(index["page-home"].request.path, "/api/v1/pages/home", "the home page's path is home");
});

test("the integration's canonical JSON reproduces the CMS's schema digest", () => {
  const digest = digestOf(schema.data);
  assert.match(digest, /^sha256:[0-9a-f]{64}$/);
  assert.equal(digest, schema.meta.schema_digest, "meta.schema_digest");

  // Every successful /api/v1 answer carries the same digest.
  const ok = Object.entries(index).filter(([, entry]) => entry.status === 200);
  assert.ok(ok.length >= 15);
  for (const [name, { headers }] of ok) assert.equal(headers[SCHEMA_DIGEST_HEADER], digest, `${name}: ${SCHEMA_DIGEST_HEADER}`);
});

test("the digest is of the canonical form, not the bytes: key order doesn't matter", () => {
  const reversed = JSON.parse(JSON.stringify(schema.data, (_key, value) =>
    value && typeof value === "object" && !Array.isArray(value) ? Object.fromEntries(Object.entries(value).reverse()) : value));
  assert.equal(digestOf(reversed), schema.meta.schema_digest);
  const changed = structuredClone(schema.data);
  changed.block_types.text.title = "Text!";
  assert.notEqual(digestOf(changed), schema.meta.schema_digest);
});

test("canonical JSON is the CMS's CanonicalJson", () => {
  assert.equal(canonicalJson({ b: [1, "<&>"], a: { d: true, c: null } }), '{"a":{"c":null,"d":true},"b":[1,"\\u003c\\u0026\\u003e"]}');
  assert.equal(canonicalJson("é \n\b\f\u0001\u007f"), '"é\\u2028\\n\\b\\f\\u0001\u007f"');
  assert.equal(canonicalJson({ f: 0.5, n: 3 }), '{"f":0.5,"n":3}');
  assert.equal(canonicalJson({ "é": 1, "z": 2, "￿": 3, "\u{1f600}": 4 }), '{"z":2,"é":1,"￿":3,"\u{1f600}":4}', "keys by UTF-8 bytes");
});

test("a part digest per block type, collection, global, page with fields, and SEO", () => {
  const parts = partDigests(schema.data);
  for (const slug of Object.keys(schema.data.block_types)) assert.ok(parts[`block_types/${slug}`], `block_types/${slug}`);
  for (const slug of Object.keys(schema.data.collections)) assert.ok(parts[`collections/${slug}`], `collections/${slug}`);
  for (const slug of Object.keys(schema.data.globals)) assert.ok(parts[`globals/${slug}`], `globals/${slug}`);
  assert.ok(parts.seo);
  assert.deepEqual(Object.keys(parts), Object.keys(parts).slice().sort(), "sorted");
});

test("a missing or draft record is a 404 in the API's one error shape", () => {
  for (const name of ["page-missing", "page-draft"]) {
    assert.equal(index[name].status, 404, name);
    const body = fixture(name);
    assert.deepEqual(Object.keys(body).sort(), ["error", "message"], name);
    assert.equal(body.error, "not_found", name);
    assert.equal(typeof body.message, "string", name);
    assert.doesNotMatch(body.message, /WHERE|SELECT/i, `${name}: says what, not how it was looked for`);
  }
});

test("the answers have the envelope and the paging the client reads", () => {
  for (const [name, entry] of Object.entries(index)) {
    if (entry.status !== 200) continue;
    const body = fixture(name);
    assert.ok("data" in body, `${name}: data`);
    assert.ok("meta" in body, `${name}: meta`);
  }
  for (const name of ["pages", "entries-posts", "entries-projects"]) {
    assert.deepEqual(Object.keys(fixture(name).meta).sort(), ["next_page", "page", "per", "total"], name);
  }
  const content = fixture("content-full");
  assert.deepEqual(Object.keys(content.meta).sort(), ["cursor", "full", "since"]);
  assert.deepEqual(Object.keys(content.data.removed).sort(), ["entries", "globals", "pages"]);
  const site = fixture("site");
  assert.deepEqual(Object.keys(site.meta).sort(), ["api_version", "cms_url", "cms_version"]);
});

test("every content event of the webhook contract asks /_cms/webhook to purge what it names", () => {
  const contract = webhookContract();
  assert.equal(contract.signature_header, "X-CMS-Signature");
  assert.deepEqual(contract.envelope_keys, ["event", "tenant", "delivered_at", "data"]);
  for (const event of contract.content_events) {
    const keys = event.startsWith("page.") ? contract.page_data_keys : contract.entry_data_keys;
    const data = Object.fromEntries(keys.map((key) => [key, key === "path" ? "company/team" : key === "collection_slug" ? "posts" : key === "slug" ? "hello-world" : "x"]));
    const todo = plan({ event, tenant: "acme", delivered_at: "2026-01-01T00:00:00Z", data });
    const tags = event.startsWith("page.") ? ["page:company/team", "pages", "sitemap"] : ["entry:posts/hello-world", "collection:posts", "sitemap"];
    assert.deepEqual(todo, { kind: "purge", all: false, tags }, event);
  }
  assert.deepEqual(plan({ event: "global.updated", data: { slug: "footer" } }), { kind: "purge", all: false, tags: ["global:footer"] });
  for (const event of contract.events.filter((event) => !event.startsWith("page.") && !event.startsWith("entry.") && event !== "global.updated")) {
    assert.deepEqual(plan({ event, data: {} }), { kind: "ignore", event }, event);
  }
  assert.ok(contracts instanceof URL);
});
