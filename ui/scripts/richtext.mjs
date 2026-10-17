#!/usr/bin/env node
// Moves a site's prose onto rich text: every `text` and `markdown` field
// (in block types, collections and globals, nested ones too) becomes a
// `richtext` field, and its values the editor's own document, Tiptap JSON,
// made by Tiptap itself (generateJSON, its Markdown parser) with the
// editor's extensions (src/lib/richtext-extensions.js) — so the result is
// what the editor would have saved. Through the CMS's API, so it runs the
// same against any install; idempotent, so it runs again safely.
//
//   CMS_BASE_URL=http://localhost:8080 CMS_ADMIN_TOKEN=… node scripts/richtext.mjs [--dry-run]
//     [--keep hours_location.address --keep …]   fields that stay plain text (owner.field.path)
//     [--code scripts.items.head --code …]       fields that hold markup on purpose: become `code`
//     [--drop-url-caches]                        drop every image_url field and key (the image is its
//                                                asset field), and other <x>_url caches beside an <x>_id
//                                                asset field; refused if one holds the only copy of an image
//     [--seo-aliases]                            seo_title → meta_title and kin, on pages and entries
//
// A repeater whose only field is prose (paragraphs of text) becomes one
// rich text field, `body` ("Text"), its items its paragraphs. An entry's
// body_markdown stays Markdown (it's the entry's body column), but HTML in
// it is turned into the Markdown the editor writes. At the end everything is
// scanned again: HTML left in a text field, or a URL cache left, fails it.
import { parseArgs } from "node:util";
import { generateJSON } from "@tiptap/html/server";
import { MarkdownManager } from "@tiptap/markdown";
import { richTextExtensions } from "../src/lib/richtext-extensions.js";

const { values: args } = parseArgs({
  options: {
    "dry-run": { type: "boolean", default: false },
    keep: { type: "string", multiple: true, default: [] },
    code: { type: "string", multiple: true, default: [] },
    "drop-url-caches": { type: "boolean", default: false },
    "seo-aliases": { type: "boolean", default: false },
  },
});
const DRY = args["dry-run"];
const KEEP = new Set(args.keep);
const CODE = new Set(args.code);
const BASE = (process.env.CMS_BASE_URL || "").replace(/\/+$/, "");
const TOKEN = process.env.CMS_ADMIN_TOKEN;
if (!BASE || !TOKEN) {
  console.error("CMS_BASE_URL and CMS_ADMIN_TOKEN (an Admin-role token) must be set");
  process.exit(2);
}

const extensions = richTextExtensions();
const markdown = new MarkdownManager({ extensions });

async function api(method, path, body) {
  const headers = { Authorization: `Bearer ${TOKEN}`, Accept: "application/json" };
  if (body !== undefined) headers["Content-Type"] = "application/json";
  const res = await fetch(BASE + path, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) });
  const text = await res.text();
  if (!res.ok) throw new Error(`${method} ${path} → ${res.status}: ${text.slice(0, 600)}`);
  return text ? JSON.parse(text) : null;
}

async function listAll(path, key) {
  const out = [];
  for (let page = 1; ; page++) {
    const answer = await api("GET", `${path}${path.includes("?") ? "&" : "?"}per=100&page=${page}`);
    out.push(...answer[key]);
    if (answer[key].length < 100) return out;
  }
}

// ---- values ------------------------------------------------------------------

const TAG = /<\/?[A-Za-z][A-Za-z0-9]*(?:\s[^<>]*)?\/?>/;
/** An image's URL, as old content kept it beside (or instead of) the image itself. */
const IMAGE_URL = /(^|_)image_url$/;
const isDoc = (v) => v && typeof v === "object" && v.type === "doc";
const emptyDoc = (d) => !d.content?.some((n) => n.type !== "paragraph" || n.content?.length);

/** A value as the editor's document: HTML, Markdown or plain text in; null for nothing. */
function toDoc(value, wasMarkdown) {
  if (isDoc(value)) return value;
  if (typeof value !== "string" || !value.trim()) return null;
  let doc;
  if (TAG.test(value)) doc = generateJSON(value, extensions);
  else if (wasMarkdown) doc = markdown.parse(value);
  else doc = plainDoc(value);
  return emptyDoc(doc) ? null : doc;
}

/** Plain text as paragraphs: a blank line between them, a line break within. */
function plainDoc(text) {
  const content = text.replace(/\r\n?/g, "\n").trim().split(/\n\s*\n/).map((para) => {
    const parts = [];
    para.split("\n").forEach((line, i) => {
      if (i) parts.push({ type: "hardBreak" });
      if (line) parts.push({ type: "text", text: line });
    });
    return { type: "paragraph", content: parts };
  });
  return { type: "doc", content };
}

// ---- schemas -------------------------------------------------------------------

const PROSE = new Set(["text", "markdown"]);
const counts = { fields: 0, merged: 0, dropped: 0, values: 0, records: 0, bodies: 0, seo: 0 };
const notes = [];

/**
 * The plan for one owner's fields: the new definitions, and for each old
 * field what becomes of its value. Fields nest through `of` (repeaters,
 * groups).
 */
function plan(fields, at) {
  const out = [];
  const moves = [];
  const names = new Set(fields.map((f) => f.name));
  for (const f of fields) {
    const path = `${at}.${f.name}`;
    const of = f.of ?? f.fields;
    if (args["drop-url-caches"] && /_url$/.test(f.name) && ["string", "url"].includes(f.type)) {
      const id = fields.find((g) => g.name === f.name.replace(/_url$/, "_id") && g.type === "asset");
      if (id || IMAGE_URL.test(f.name)) {
        moves.push({ name: f.name, drop: true });
        counts.dropped++;
        notes.push(`drop ${path} (${id ? `the cache of ${id.name}` : "an image's URL: images are asset fields"})`);
        continue;
      }
    }
    if (CODE.has(path)) {
      out.push({ ...f, type: "code" });
      if (f.type !== "code") {
        counts.fields++;
        notes.push(`${path}: ${f.type} → code`);
      }
      continue;
    }
    if (PROSE.has(f.type) && !KEEP.has(path)) {
      out.push({ ...f, type: "richtext" });
      moves.push({ name: f.name, convert: f.type === "markdown" });
      counts.fields++;
      notes.push(`${path}: ${f.type} → richtext`);
      continue;
    }
    if (f.type === "repeater" && of?.length === 1 && PROSE.has(of[0].type) && !KEEP.has(`${path}.${of[0].name}`)) {
      const name = names.has("body") ? f.name : "body";
      out.push({ name, label: "Text", type: "richtext", ...(f.required ? { required: true } : {}), ...(f.help ? { help: f.help } : {}) });
      moves.push({ name: f.name, mergeInto: name, sub: of[0].name, convert: of[0].type === "markdown" });
      counts.merged++;
      notes.push(`${path}[].${of[0].name}: repeater → one richtext field ${at}.${name}`);
      continue;
    }
    // Already rich text (a run that stopped halfway, an earlier one): any
    // value that isn't a document yet is still converted, as Markdown.
    if (f.type === "richtext") {
      out.push(f);
      moves.push({ name: f.name, convert: true });
      continue;
    }
    if ((f.type === "repeater" || f.type === "group") && of?.length) {
      const inner = plan(of, path);
      out.push({ ...f, [f.of ? "of" : "fields"]: inner.fields });
      if (inner.moves.length) moves.push({ name: f.name, nested: inner.moves, repeater: f.type === "repeater" });
      continue;
    }
    out.push(f);
  }
  return { fields: out, moves };
}

/** data with a plan's moves made; whether anything changed. */
function apply(data, moves) {
  if (!data || typeof data !== "object") return false;
  let changed = false;
  // A URL cache no schema declares any more, beside its asset id.
  if (args["drop-url-caches"]) {
    for (const k of Object.keys(data)) {
      if (/_url$/.test(k) && (IMAGE_URL.test(k) || k.replace(/_url$/, "_id") in data) && !moves.some((m) => m.name === k)) {
        delete data[k];
        counts.dropped++;
        changed = true;
      }
    }
  }
  for (const m of moves) {
    if (!(m.name in data)) continue;
    const v = data[m.name];
    if (m.drop) {
      delete data[m.name];
      changed = true;
    } else if (m.mergeInto) {
      if (!Array.isArray(v)) continue;
      const content = v.flatMap((item) => toDoc(item?.[m.sub], m.convert)?.content ?? []);
      delete data[m.name];
      data[m.mergeInto] = content.length ? { type: "doc", content } : null;
      if (data[m.mergeInto] === null) delete data[m.mergeInto];
      counts.values++;
      changed = true;
    } else if (m.nested) {
      for (const item of m.repeater ? (Array.isArray(v) ? v : []) : [v]) changed = apply(item, m.nested) || changed;
    } else if (!isDoc(v)) {
      if (v === null || v === undefined) continue;
      const doc = toDoc(v, m.convert);
      if (doc) data[m.name] = doc;
      else delete data[m.name];
      counts.values++;
      changed = true;
    }
  }
  return changed;
}

// ---- run -----------------------------------------------------------------------

const blockTypes = (await api("GET", "/api/block_types")).block_types;
const collections = (await api("GET", "/api/collections")).collections;
const globals = await Promise.all((await api("GET", "/api/globals")).globals.map(async (g) => (await api("GET", `/api/globals/${g.slug}`)).global));

// Before anything is written: an image URL with no image beside it would be
// an image lost, so the run stops and says where.
if (args["drop-url-caches"]) {
  const orphans = [];
  const look = (v, at) => {
    if (Array.isArray(v)) return v.forEach((x, i) => look(x, `${at}[${i}]`));
    if (!v || typeof v !== "object" || isDoc(v)) return;
    for (const [k, x] of Object.entries(v)) {
      if (IMAGE_URL.test(k) && typeof x === "string" && x.trim() && !v[k.replace(/_url$/, "_id")]) orphans.push(`${at}.${k} = ${x}`);
      look(x, `${at}.${k}`);
    }
  };
  for (const s of await listAll("/api/pages?sort=path", "pages")) look((await api("GET", `/api/pages/${s.path}`)).page.blocks, `page ${s.path}`);
  for (const c of collections) {
    for (const s of await listAll(`/api/collections/${c.slug}/entries`, "entries")) {
      const e = (await api("GET", `/api/collections/${c.slug}/entries/${encodeURIComponent(s.slug)}`)).entry;
      look({ frontmatter: e.frontmatter, blocks: e.blocks }, `entry ${c.slug}/${e.slug}`);
    }
  }
  for (const g of globals) look(g.data, `global ${g.slug}`);
  if (orphans.length) {
    console.error(`These image URLs have no image beside them; pick each image in the media library first:\n  ${orphans.join("\n  ")}`);
    process.exit(1);
  }
}

const blockPlans = {};
for (const bt of blockTypes) {
  const p = plan(bt.fields ?? [], bt.slug);
  blockPlans[bt.slug] = p.moves;
  if (p.moves.length && !DRY) await api("PATCH", `/api/block_types/${bt.slug}`, { block_type: { fields: p.fields } });
}
const collectionPlans = {};
for (const c of collections) {
  const fields = (await api("GET", `/api/collections/${c.slug}`)).collection.schema?.fields ?? [];
  const p = plan(fields, c.slug);
  collectionPlans[c.slug] = p.moves;
  if (p.moves.length && !DRY) await api("PATCH", `/api/collections/${c.slug}/schema`, { fields: p.fields });
}
// A global's schema and data change in one save: the CMS checks its data
// against its schema whenever either changes.
const globalPlans = {};
for (const g of globals) {
  const p = plan(g.fields ?? [], g.slug);
  globalPlans[g.slug] = p;
}

/** A list of blocks with each one's moves made, nested blocks too. */
function applyBlocks(blocks) {
  let changed = false;
  for (const b of Array.isArray(blocks) ? blocks : []) {
    changed = apply(b.data, blockPlans[b.type] ?? []) || changed;
    for (const v of Object.values(b.data ?? {})) {
      if (Array.isArray(v) && v.some((x) => x?.type && x?.data)) changed = applyBlocks(v) || changed;
    }
  }
  return changed;
}

const SEO_ALIASES = { seo_title: "meta_title", seo_description: "meta_description", description: "meta_description", no_index: "noindex" };
function seoAliases(seo) {
  if (!args["seo-aliases"] || !seo || typeof seo !== "object") return false;
  let changed = false;
  for (const [old, std] of Object.entries(SEO_ALIASES)) {
    if (!(old in seo)) continue;
    let v = seo[old];
    if (std === "noindex") v = v === true || v === 1 || v === "1" || v === "true";
    if (seo[std] === undefined || seo[std] === null || seo[std] === "") seo[std] = v;
    delete seo[old];
    changed = true;
  }
  if (typeof seo.noindex === "number") {
    seo.noindex = seo.noindex === 1;
    changed = true;
  }
  if (changed) counts.seo++;
  return changed;
}

async function save(path, kind, body, label) {
  counts.records++;
  console.log(`${DRY ? "would save" : "saved"} ${label}: ${Object.keys(body).join(", ")}`);
  if (!DRY) await api("PATCH", path, { [kind]: body });
}

for (const summary of await listAll("/api/pages?sort=path", "pages")) {
  const page = (await api("GET", `/api/pages/${summary.path}`)).page;
  const body = {};
  if (applyBlocks(page.blocks)) body.blocks = page.blocks;
  if (seoAliases(page.seo)) body.seo = page.seo;
  if (Object.keys(body).length) await save(`/api/pages/${page.path}`, "page", { ...body, lock_version: page.lock_version }, `page ${page.path}`);
}
for (const c of collections) {
  for (const summary of await listAll(`/api/collections/${c.slug}/entries`, "entries")) {
    const path = `/api/collections/${c.slug}/entries/${encodeURIComponent(summary.slug)}`;
    const entry = (await api("GET", path)).entry;
    const body = {};
    if (apply(entry.frontmatter, collectionPlans[c.slug] ?? [])) body.frontmatter = entry.frontmatter;
    if (applyBlocks(entry.blocks)) body.blocks = entry.blocks;
    if (typeof entry.body_markdown === "string" && TAG.test(entry.body_markdown)) {
      body.body_markdown = markdown.serialize(generateJSON(entry.body_markdown, extensions));
      counts.bodies++;
    }
    if (seoAliases(entry.seo)) body.seo = entry.seo;
    if (Object.keys(body).length) await save(path, "entry", { ...body, lock_version: entry.lock_version }, `entry ${c.slug}/${entry.slug}`);
  }
}
for (const g of globals) {
  const { fields, moves } = globalPlans[g.slug];
  const data = g.data ?? {};
  const changed = apply(data, moves);
  if (!changed && JSON.stringify(fields) === JSON.stringify(g.fields ?? [])) continue;
  await save(`/api/globals/${g.slug}`, "global", { schema: { fields }, data, lock_version: g.lock_version }, `global ${g.slug}`);
}

for (const n of notes) console.log(`  ${n}`);
console.log(`${DRY ? "Dry run: " : ""}${counts.fields} fields → richtext, ${counts.merged} repeaters merged, ${counts.dropped} URL caches dropped; ` +
  `${counts.values} values converted, ${counts.bodies} entry bodies' HTML → Markdown, ${counts.seo} SEO aliased; ${counts.records} records saved.`);
if (DRY) process.exit(0);

// ---- check ---------------------------------------------------------------------

const left = [];
const scan = (v, at) => {
  if (typeof v === "string") { if (TAG.test(v)) left.push(`HTML at ${at}`); return; }
  if (isDoc(v)) return;
  if (Array.isArray(v)) v.forEach((x, i) => scan(x, `${at}[${i}]`));
  else if (v && typeof v === "object") for (const [k, x] of Object.entries(v)) {
    if (args["drop-url-caches"] && /_url$/.test(k) && (IMAGE_URL.test(k) || `${k.replace(/_url$/, "_id")}` in v)) left.push(`URL cache at ${at}.${k}`);
    scan(x, `${at}.${k}`);
  }
};
for (const summary of await listAll("/api/pages?sort=path", "pages")) scan((await api("GET", `/api/pages/${summary.path}`)).page.blocks, `page ${summary.path}`);
for (const c of collections) {
  for (const summary of await listAll(`/api/collections/${c.slug}/entries`, "entries")) {
    const e = (await api("GET", `/api/collections/${c.slug}/entries/${encodeURIComponent(summary.slug)}`)).entry;
    scan({ frontmatter: e.frontmatter, blocks: e.blocks, body_markdown: e.body_markdown }, `entry ${c.slug}/${e.slug}`);
  }
}
for (const g of globals) scan((await api("GET", `/api/globals/${g.slug}`)).global.data, `global ${g.slug}`);
if (left.length) {
  console.error(`Still left:\n  ${left.join("\n  ")}`);
  process.exit(1);
}
console.log("Checked: no HTML in text, no URL caches.");
