// The CMS's schema as Zod and as TypeScript, held to the recorded contract:
// every record the CMS delivered passes; anything it didn't declare fails.
import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import ts from "typescript";
import { buildSchemas, asset, safeURL } from "../dist/schema/zod.js";
import { definitions, loaderTypes, moduleTypes } from "../dist/schema/typegen.js";
import { digestOf } from "../dist/schema/digest.js";
import { normalizeSchema } from "../dist/types.js";
import { contractIndex, fixture } from "./helpers.js";

const schema = fixture("schema");
const content = fixture("content-full");
const zod = buildSchemas(schema.data);

const issues = (result) => (result.success ? [] : result.error.issues.map((issue) => `${issue.path.join(".")}: ${issue.message}`));
const passes = (parser, value, label) => {
  const result = parser.safeParse(value);
  assert.ok(result.success, `${label}\n${issues(result).join("\n")}`);
  return result.data;
};
const fails = (parser, value, pattern, label) => {
  const found = issues(parser.safeParse(value));
  assert.ok(found.some((line) => pattern.test(line)), `${label}: expected an issue matching ${pattern}, got:\n${found.join("\n") || "(it passed)"}`);
};
const home = () => structuredClone(fixture("page-home").data);
const everyField = (page) => page.blocks.find((block) => block.type === "every_field");

test("every record in every recorded answer passes the schema the CMS published", () => {
  let checked = 0;
  for (const [name, entry] of Object.entries(contractIndex())) {
    if (entry.status !== 200) continue;
    const answer = fixture(name);
    const path = entry.request.path;
    const records = Array.isArray(answer.data) ? answer.data : [answer.data];
    if (name === "content-full") {
      for (const page of answer.data.pages) { passes(zod.page, page, `content page ${page.path}`); checked++; }
      for (const item of answer.data.entries) { passes(zod.entry(item.collection), item, `content entry ${item.collection}/${item.slug}`); checked++; }
      for (const global of answer.data.globals) { passes(zod.global, global, `content global ${global.slug}`); checked++; }
    } else if (path.startsWith("/api/v1/pages")) {
      for (const page of records) { passes(zod.page, page, `${name}: ${page.path}`); checked++; }
    } else if (/\/entries/.test(path)) {
      for (const item of records) { passes(zod.entry(item.collection), item, `${name}: ${item.slug}`); checked++; }
    } else if (path.startsWith("/api/v1/globals")) {
      for (const global of records) { passes(zod.global, global, `${name}: ${global.slug}`); checked++; }
    }
    for (const value of Object.values(answer.included?.assets ?? {})) { passes(asset, value, `${name}: asset ${value.id}`); checked++; }
  }
  assert.ok(checked >= 25, `checked ${checked} records`);
});

test("the home page has every field type, a collection list with its entries, and nested blocks — all checked", () => {
  const page = passes(zod.page, home(), "home");
  const block = everyField(page);
  for (const field of ["title", "summary", "body", "embed", "count", "featured", "tone", "website", "starts_at", "cta", "image", "post", "posts", "tags", "items", "contact", "inner"]) {
    assert.ok(field in block.data, `every_field.${field} is delivered`);
  }
  assert.equal(block.data.inner[0].type, "text");
  const list = page.blocks.find((b) => b.type === "collection_list");
  assert.ok(list.resolved.entries.length >= 2, "the collection list's entries");
  assert.equal(list.resolved.entries[0].collection, "posts");
  assert.equal(page.blocks.find((b) => b.type === "contact_info").resolved.contact.title, "Acme");
});

test("strict at every depth: a key the schema doesn't declare fails", () => {
  const cases = [
    ["the record", (p) => { p.surprise = true; }, /surprise/],
    ["block data", (p) => { everyField(p).data.not_a_field = 1; }, /^blocks\.\d+\.data.*not_a_field/],
    ["a block", (p) => { everyField(p).extra = 1; }, /^blocks\.\d+.*extra/],
    ["a group", (p) => { everyField(p).data.contact.stale = 1; }, /^blocks\.\d+\.data\.contact.*stale/],
    ["a link", (p) => { everyField(p).data.contact.link.stale = 1; }, /^blocks\.\d+\.data\.contact\.link.*stale/],
    ["a repeater item", (p) => { everyField(p).data.items[0].stale = 1; }, /^blocks\.\d+\.data\.items\.0.*stale/],
    ["a nested block", (p) => { everyField(p).data.inner[0].stale = 1; }, /inner\.0.*stale/],
    ["a nested block's data", (p) => { everyField(p).data.inner[0].data.stale = 1; }, /inner\.0\.data.*stale/],
    ["SEO", (p) => { p.seo.stale = 1; }, /^seo.*stale/],
    ["a page's frontmatter (no fields: {})", (p) => { p.frontmatter.stale = 1; }, /^frontmatter.*stale/],
    ["a listed entry", (p) => { p.blocks.find((b) => b.type === "collection_list").resolved.entries[0].stale = 1; }, /resolved\.entries\.0.*stale/],
    ["a listed entry's frontmatter", (p) => { p.blocks.find((b) => b.type === "collection_list").resolved.entries[0].frontmatter.stale = 1; }, /resolved\.entries\.0\.frontmatter.*stale/],
    ["what a collection list resolved", (p) => { p.blocks.find((b) => b.type === "collection_list").resolved.stale = 1; }, /resolved.*stale/],
  ];
  for (const [label, change, pattern] of cases) {
    const page = home();
    change(page);
    fails(zod.page, page, pattern, label);
  }

  const post = structuredClone(fixture("entry-post").data);
  post.frontmatter.stale = 1;
  fails(zod.entry("posts"), post, /^frontmatter.*stale/, "an entry's frontmatter");
  const footer = structuredClone(fixture("global-footer").data);
  footer.data.links[0].stale = 1;
  fails(zod.global, footer, /^data\.links\.0.*stale/, "a global's repeater item");
  const image = structuredClone(Object.values(fixture("page-home").included.assets)[0]);
  image.stale = 1;
  fails(asset, image, /stale/, "an asset");
});

test("the wrong type fails, as the CMS's validator would refuse it", () => {
  const cases = [
    ["a select outside its options", (d) => { d.tone = "neon"; }, /tone/],
    ["an integer as a string", (d) => { d.count = "3"; }, /count/],
    ["a whole number", (d) => { d.count = 3.5; }, /count/],
    ["a boolean as a string", (d) => { d.featured = "yes"; }, /featured/],
    ["a datetime that isn't one", (d) => { d.starts_at = "yesterday"; }, /starts_at/],
    ["an unsafe URL", (d) => { d.website = "javascript:alert(1)"; }, /website/],
    ["a link of an unknown kind", (d) => { d.cta = { kind: "file", value: "x" }; }, /cta/],
    ["an entry link without its collection", (d) => { d.cta = { kind: "entry", value: "hello-world" }; }, /cta\.collection/],
    ["an unsafe URL link", (d) => { d.contact.link = { kind: "url", value: "javascript:void 0" }; }, /contact\.link/],
    ["an asset id as a number", (d) => { d.image = 1; }, /image/],
    ["record refs that aren't strings", (d) => { d.posts = [1]; }, /posts/],
    ["a string list as a string", (d) => { d.tags = "a,b"; }, /tags/],
    ["a required field left empty", (d) => { d.title = ""; }, /title/],
    ["a required field missing", (d) => { delete d.title; }, /title/],
    ["a repeater item's required field missing", (d) => { delete d.items[1].label; }, /items\.1\.label/],
    ["a nested block of a type that doesn't exist", (d) => { d.inner.push({ type: "made_up", data: {} }); }, /inner\.1\.type: block type "made_up" isn't in the CMS's schema/],
    ["a nested block of a type the field doesn't allow", (d) => { d.inner.push({ type: "contact_info", data: {} }); }, /inner\.1\.type: block type "contact_info" isn't allowed here/],
    ["a nested block's data of the wrong type", (d) => { d.inner[0].data.body = 5; }, /inner\.0\.data\.body/],
  ];
  for (const [label, change, pattern] of cases) {
    const page = home();
    change(everyField(page).data);
    fails(zod.page, page, pattern, label);
  }
  const page = home();
  page.blocks.push({ id: "x", type: "gone", data: {} });
  fails(zod.page, page, /type: block type "gone" isn't in the CMS's schema/, "a block whose type isn't in the schema");

  const post = structuredClone(fixture("entry-post").data);
  post.frontmatter.category = "opinion";
  fails(zod.entry("posts"), post, /frontmatter\.category/, "an entry's select");
  delete post.frontmatter.category;
  delete post.frontmatter.summary;
  fails(zod.entry("posts"), post, /frontmatter\.summary/, "an entry's required field");
  const seo = home();
  seo.seo.og_type = "film";
  fails(zod.page, seo, /seo\.og_type/, "SEO's select (og_type)");
});

test("optional takes missing, null and \"\"; an empty datetime reads as null", () => {
  const page = home();
  const data = everyField(page).data;
  Object.assign(data, { summary: null, count: null, tone: "", starts_at: "", image: "" });
  delete data.website;
  const parsed = passes(zod.page, page, "optional values");
  assert.equal(everyField(parsed).data.starts_at, null);
  assert.equal(everyField(parsed).data.tone, null);
});

test("a collection the schema doesn't serve is a clear error", () => {
  assert.throws(() => zod.entry("nope"), /no collection "nope"/);
});

test("the Rails schema reads as one JSON Schema per part, titled", () => {
  const normalized = normalizeSchema(schema.data);
  assert.deepEqual(Object.keys(normalized.blocks).sort(), Object.keys(schema.data.block_types).sort());
  assert.equal(normalized.blocks.every_field.title, "Every field");
  assert.equal(normalized.blocks.every_field.additionalProperties, false);
  assert.equal(normalized.collections.posts.title, "Posts");
  assert.equal(normalized.globals.footer.properties.copyright["x-cms-type"], "string");
  assert.equal(safeURL("/about"), true);
  assert.equal(safeURL("mailto:a@b.test"), true);
  assert.equal(safeURL(" java\tscript:x"), false);
});

function compile(files) {
  const dir = mkdtempSync(join(tmpdir(), "lp-types-"));
  for (const [name, text] of Object.entries(files)) writeFileSync(join(dir, name), text);
  const program = ts.createProgram(Object.keys(files).map((name) => join(dir, name)), {
    strict: true, noEmit: true, target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ESNext, moduleResolution: ts.ModuleResolutionKind.Bundler, skipLibCheck: true, types: [],
  });
  return ts.getPreEmitDiagnostics(program).map((d) => `${d.file ? d.file.fileName.split("/").pop() : ""}: ${ts.flattenDiagnosticMessageText(d.messageText, "\n")}`);
}

test("the generated TypeScript compiles: the module, and each loader's Entry", () => {
  const digest = digestOf(schema.data);
  assert.deepEqual(compile({ "cms.d.ts": moduleTypes(schema.data, digest), "use.ts": 'import type { Page, Block, Entries, Globals, ListedEntry } from "libre-publish:types";\nexport type X = [Page, Block, Entries, Globals, ListedEntry];\n' }), []);
  for (const entry of ["Page", 'Entries["posts"]', 'Entries["projects"]', "Global", "Asset"]) {
    assert.deepEqual(compile({ "loader.ts": loaderTypes(schema.data, entry, digest) }), [], entry);
  }
});

test("BlockComponents needs a component for every block type, and only those; props are checked", () => {
  const types = Object.keys(schema.data.block_types);
  const literal = (keys) => `{ ${keys.map((key) => `${JSON.stringify(key)}: C`).join(", ")} }`;
  const header = `${definitions(schema.data)}\ndeclare const C: (props: any) => any;\n`;
  assert.deepEqual(compile({ "ok.ts": `${header}export const all: BlockComponents = ${literal(types)};\n` }), []);

  const missing = compile({ "missing.ts": `${header}export const some: BlockComponents = ${literal(types.filter((type) => type !== "every_field"))};\n` });
  assert.ok(missing.some((line) => /'every_field' is missing/.test(line)), missing.join("\n"));

  const extra = compile({ "extra.ts": `${header}export const more: BlockComponents = ${literal([...types, "not_a_block_type"])};\n` });
  assert.ok(extra.some((line) => /not_a_block_type/.test(line)), extra.join("\n"));

  const wrong = compile({ "wrong.ts": `${header}declare const Text: (props: { body: number }) => any;\nexport const typed: BlockComponents = { ...(${literal(types)}), text: Text };\n` });
  assert.ok(wrong.some((line) => /body/.test(line)), wrong.join("\n"));

  const listing = compile({ "list.ts": `${header}declare const List: (props: BlockProps<"collection_list">) => any;\nexport const ok: BlockComponents = { ...(${literal(types)}), collection_list: List };\nexport function first(p: BlockProps<"collection_list">) { const e = p.resolved?.entries[0]; return e && e.collection === "posts" ? e.frontmatter.summary : undefined; }\n` });
  assert.deepEqual(listing, [], "a collection list's entries are typed by their collection");
});

test("generated field types follow the same rules as the Zod", () => {
  const text = definitions(schema.data);
  assert.match(text, /export type EveryFieldBlock = \{[\s\S]*?"title": string;/);
  assert.match(text, /"tone"\?: "light" \| "dark" \| null;/);
  assert.match(text, /"image"\?: AssetId \| null;/);
  assert.match(text, /"cta"\?: Link \| null;/);
  assert.match(text, /"inner"\?: Block\[\] \| null;/);
  assert.match(text, /"count"\?: number \| null;/);
  assert.match(text, /export type PostsFields = \{[\s\S]*?"summary": string;/);
  assert.match(text, /"og_type"\?: "article" \| "product" \| "profile" \| "video.other" \| "website" \| null;/);
  assert.doesNotMatch(text, /\[key: string\]: unknown;/, "every object is closed");
});
