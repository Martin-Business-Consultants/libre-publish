// /_cms/webhook: the CMS's signed purges (Deploys::Purge) and webhooks
// (docs/webhooks.md), checked and turned into what to purge.
import { test } from "node:test";
import assert from "node:assert/strict";
import { createHmac } from "node:crypto";
import { TOLERANCE_SECONDS, verify, verifyRequest } from "../dist/runtime/signature.js";
import { plan } from "../dist/runtime/purge.js";
import { webhookContract } from "./helpers.js";

const contract = webhookContract();
const sign = (body, secret) => `sha256=${createHmac("sha256", secret).update(body).digest("hex")}`;

// As Deploys::Purge.body builds it.
const purge = (overrides = {}) => ({ event: "cms.purge", reason: "page.published", site: "acme", all: false,
  tags: ["page:about", "pages", "sitemap"], changes: [{ event: "page.published", tags: ["page:about", "pages", "sitemap"] }],
  sent_at: "2026-01-01T00:00:00Z", ...overrides });

test("the signature is the contract's: X-CMS-Signature, sha256=<hex HMAC-SHA256 of the raw body>", async () => {
  assert.equal(contract.signature_header, "X-CMS-Signature");
  assert.match(contract.signature_format, /^sha256=<hex HMAC-SHA256 of the raw request body>$/);
  const body = JSON.stringify(purge());
  const good = sign(body, "s3cret");
  assert.equal(await verify(body, good, "s3cret"), true);
  assert.equal(await verify(body, good, "other"), false);
  assert.equal(await verify(`${body} `, good, "s3cret"), false, "a changed body");
  assert.equal(await verify(body, good.replace("sha256=", ""), "s3cret"), false, "without its sha256= prefix");
  assert.equal(await verify(body, null, "s3cret"), false);
  assert.equal(await verifyRequest(body, new Headers({ "X-CMS-Signature": good, "X-CMS-Event": "cms.purge" }), "s3cret"), true, "as the CMS posts it");
  assert.equal(await verifyRequest(body, new Headers(), "s3cret"), false, "unsigned");
});

test("a sender that stamps its posts (X-CMS-Signature-V2 over \"<timestamp>.<body>\") is held to it: a replay is refused", async () => {
  const body = JSON.stringify(purge());
  const now = 1_800_000_000_000;
  const at = (seconds, secret = "s3cret") => new Headers({
    "X-CMS-Signature": sign(body, secret),
    "X-CMS-Timestamp": String(seconds),
    "X-CMS-Signature-V2": sign(`${seconds}.${body}`, secret),
  });
  assert.equal(await verifyRequest(body, at(now / 1000), "s3cret", now), true);
  assert.equal(await verifyRequest(body, at(now / 1000 - TOLERANCE_SECONDS - 1), "s3cret", now), false, "too old");
  assert.equal(await verifyRequest(body, at(now / 1000, "other"), "s3cret", now), false);
});

test("the CMS's purge: its tags; everything for Deploy now (all: true)", () => {
  assert.deepEqual(plan(purge()), { kind: "purge", all: false, tags: ["page:about", "pages", "sitemap"] });
  assert.deepEqual(plan(purge({ all: true, tags: [], reason: "manual" })), { kind: "purge", all: true, tags: [] });
  assert.deepEqual(plan(purge({ all: true })), { kind: "purge", all: true, tags: [] }, "all wins over its tags");
  assert.deepEqual(plan(purge({ all: false, tags: [] })), { kind: "purge", all: false, tags: [] }, "nothing named, all: false: nothing to purge");
  assert.deepEqual(plan({ tags: [] }), { kind: "purge", all: true, tags: [] }, "a bare purge that says nothing: everything");
});

test("webhook events purge what they name; others are ignored", () => {
  const page = { event: "page.published", tenant: "acme", delivered_at: "2026-01-01T00:00:00Z", data: Object.fromEntries(contract.page_data_keys.map((k) => [k, k === "path" ? "about" : "x"])) };
  assert.deepEqual(plan(page), { kind: "purge", all: false, tags: ["page:about", "pages", "sitemap"] });
  const entry = { event: "entry.deleted", tenant: "acme", delivered_at: "2026-01-01T00:00:00Z", data: Object.fromEntries(contract.entry_data_keys.map((k) => [k, k === "collection_slug" ? "posts" : k === "slug" ? "hi" : "x"])) };
  assert.deepEqual(plan(entry), { kind: "purge", all: false, tags: ["entry:posts/hi", "collection:posts", "sitemap"] });
  assert.deepEqual(plan({ event: "global.updated", data: { slug: "nav" } }), { kind: "purge", all: false, tags: ["global:nav"] });
  assert.deepEqual(plan({ event: "submission.created", data: {} }), { kind: "ignore", event: "submission.created" });
});
