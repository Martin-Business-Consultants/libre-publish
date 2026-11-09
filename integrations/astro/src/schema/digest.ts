/**
 * The schema's digest: "sha256:<hex>" of the canonical JSON of GET
 * /api/v1/schema's `data`. The CMS sends it (meta.schema_digest, and the
 * X-CMS-Schema-Digest header on every /api/v1 answer); this computes the same
 * thing over each part of the schema, to name what changed between two, and
 * is held to the CMS's own by the contract fixtures (test/contract.test.js).
 *
 * Canonical JSON is the CMS's CanonicalJson (app/models/canonical_json.rb):
 * object keys sorted by their UTF-8 bytes, no whitespace, `<`, `>` and `&`
 * (and U+2028, U+2029) escaped as \uXXXX, control characters as \n, \r,
 * \t, \b, \f or \u00XX, everything else as it is.
 */
import { createHash } from "node:crypto";

export function canonicalJson(value: unknown): string {
  if (value === null || value === undefined) return "null";
  if (typeof value === "string") return jsonString(value);
  if (typeof value === "number") return Number.isFinite(value) ? jsonNumber(value) : "null";
  if (typeof value === "boolean") return value ? "true" : "false";
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(",")}]`;
  if (typeof value === "object") {
    const keys = Object.keys(value as object).filter((key) => (value as Record<string, unknown>)[key] !== undefined).sort(byBytes);
    return `{${keys.map((key) => `${jsonString(key)}:${canonicalJson((value as Record<string, unknown>)[key])}`).join(",")}}`;
  }
  return "null";
}

export function digestOf(value: unknown): string {
  return `sha256:${createHash("sha256").update(canonicalJson(value)).digest("hex")}`;
}

/**
 * A digest per block type, collection, global, page with fields, and SEO —
 * what the lock keeps so a mismatch can say what changed: "block_types/hero",
 * "collections/posts", "globals/footer", "pages/about", "seo".
 */
export function partDigests(schema: { block_types?: object; collections?: object; globals?: object; pages?: object; seo?: unknown }): Record<string, string> {
  const parts: Record<string, string> = {};
  for (const section of ["block_types", "collections", "globals", "pages"] as const) {
    for (const [key, value] of Object.entries((schema[section] ?? {}) as Record<string, unknown>)) {
      parts[`${section}/${key}`] = digestOf(value).slice(0, 7 + 16);
    }
  }
  parts.seo = digestOf(schema.seo ?? null).slice(0, 7 + 16);
  return Object.fromEntries(Object.entries(parts).sort(([a], [b]) => byBytes(a, b)));
}

// Keys sort by their UTF-8 bytes. For ASCII (the slugs and field
// names a schema has) that's code unit order; past it, compare the bytes.
const ascii = /^[\x00-\x7f]*$/;
function byBytes(a: string, b: string): number {
  if (ascii.test(a) && ascii.test(b)) return a < b ? -1 : a > b ? 1 : 0;
  return Buffer.compare(Buffer.from(a, "utf8"), Buffer.from(b, "utf8"));
}

function jsonString(value: string): string {
  let out = '"';
  for (const char of value) {
    const code = char.codePointAt(0)!;
    if (char === '"') out += '\\"';
    else if (char === "\\") out += "\\\\";
    else if (char === "\n") out += "\\n";
    else if (char === "\r") out += "\\r";
    else if (char === "\t") out += "\\t";
    else if (char === "\b") out += "\\b";
    else if (char === "\f") out += "\\f";
    else if (code < 0x20 || char === "<" || char === ">" || char === "&" || code === 0x2028 || code === 0x2029) {
      out += `\\u${code.toString(16).padStart(4, "0")}`;
    } else out += char;
  }
  return `${out}"`;
}

// A whole float is written as an integer (1.0 → 1), as CanonicalJson does;
// other numbers as ES writes them, for the range a schema holds.
function jsonNumber(value: number): string {
  return Object.is(value, -0) ? "0" : String(value).replace(/e\+?(\d)/, "e+$1");
}
