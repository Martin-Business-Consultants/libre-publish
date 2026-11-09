// Shared by the tests: the contract fixtures, a fake fetch, a fake loader context.
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

/**
 * The CMS's contracts/ (this repository's root): every /api/v1 answer a site
 * builds from, recorded from a seeded install by
 * spec/contracts/delivery_contract_spec.rb. Same repository, so the tests
 * always run on the files the CMS is held to: a change there fails here
 * until the integration follows.
 */
export const contracts = new URL("../../../contracts/", import.meta.url);

/** contracts/delivery/<name>.json, a fresh copy each time. */
export function fixture(name) {
  return JSON.parse(readFileSync(fixturePath(name), "utf8"));
}

export function fixturePath(name) {
  return fileURLToPath(new URL(`delivery/${name}.json`, contracts));
}

/** contracts/index.json: for each answer, the request that produced it, its status and its contract headers. */
export function contractIndex() {
  return JSON.parse(readFileSync(new URL("index.json", contracts), "utf8"));
}

/** The CMS's webhook contract (spec/fixtures/contracts/webhook_contract.json). */
export function webhookContract() {
  return JSON.parse(readFileSync(new URL("../spec/fixtures/contracts/webhook_contract.json", contracts), "utf8")).webhook;
}

export const envelope = (data, meta = {}, included) => ({ data, meta, ...(included ? { included } : {}) });

/** A fetch answering from a table of path (with or without query) → { body, status, headers } (or a function of the path). */
export function fakeFetch(routes) {
  const calls = [];
  const fetcher = async (url, init = {}) => {
    calls.push({ url: String(url), init });
    const parsed = new URL(url);
    const route = routes[parsed.pathname + parsed.search] ?? routes[parsed.pathname];
    if (!route) return new Response(JSON.stringify({ error: "not_found", message: "no route" }), { status: 404 });
    const { body, status = 200, headers = {} } = typeof route === "function" ? route(parsed, init) : route;
    return new Response(typeof body === "string" ? body : JSON.stringify(body), { status, headers });
  };
  return { fetcher, calls };
}

/** Enough of Astro's LoaderContext for the loaders, with parseData running `schema`. */
export function fakeContext(schema, meta = {}) {
  const entries = new Map();
  return {
    entries,
    meta,
    context: {
      collection: "test",
      store: { set: (entry) => entries.set(entry.id, entry), delete: (id) => entries.delete(id), clear: () => entries.clear() },
      meta: { get: (key) => meta[key], set: (key, value) => { meta[key] = value; } },
      parseData: async ({ id, data }) => {
        const parsed = schema.safeParse(data);
        if (!parsed.success) throw new Error(`${id}: ${parsed.error.issues.map((issue) => `${issue.path.join(".")}: ${issue.message}`).join("; ")}`);
        return parsed.data;
      },
      generateDigest: (data) => JSON.stringify(data).length.toString(),
      logger: { info() {}, warn() {}, debug() {} },
    },
  };
}
