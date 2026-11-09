/**
 * What the integration resolved for this build — the connection, and the
 * schema it checked against cms.lock.json — kept on globalThis for the code
 * that runs in the same process: the content loaders and the prerendering
 * pages. Free of Vite and Node imports, so it can sit in code that's bundled
 * for a Worker too.
 */
import { createClient, type CmsClient } from "./client.js";
import type { CmsSchema } from "./types.js";

export interface Connection { url: string; token: string }

/** The variables a connection can come from, in the order they're read. */
export const URL_VARIABLES = ["CMS_BASE_URL", "CMS_URL"] as const;
export const TOKEN_VARIABLES = ["CMS_API_TOKEN", "PRODUCTION_TOKEN"] as const;

/**
 * The CMS's address (CMS_BASE_URL, else CMS_URL) and the site's token
 * (CMS_API_TOKEN, else PRODUCTION_TOKEN), from whatever `read` looks in. A
 * trailing /api or /api/v1 on the address is dropped: the client adds it.
 */
export function connectionFrom(read: (name: string) => string | undefined, options: { url?: string; token?: string } = {}): Connection | null {
  const first = (names: readonly string[]) => names.map(read).find((value) => typeof value === "string" && value.trim() !== "");
  const url = options.url ?? first(URL_VARIABLES);
  const token = options.token ?? first(TOKEN_VARIABLES);
  return url && token ? { url: url.trim().replace(/\/+$/, "").replace(/\/api(\/v1)?$/, ""), token: token.trim() } : null;
}

/** The schema a build runs against: read once, its digest checked against the lock. */
export interface LockedSchema { schema: CmsSchema; digest: string }

interface BuildState {
  connection?: Connection;
  /** The schema the integration read and checked against the lock. */
  schema?: Promise<LockedSchema>;
  /** Every schema digest the CMS's answers carried during this build. */
  digests: Set<string>;
}

const KEY = Symbol.for("libre-publish.astro.build");
type Holder = { [KEY]?: BuildState };

export function buildState(): BuildState {
  return ((globalThis as Holder)[KEY] ??= { digests: new Set() });
}

export function keepConnection(connection: Connection) {
  buildState().connection = connection;
}

/** The build's connection, or null outside a build that has one. */
export function heldConnection(): Connection | null {
  return buildState().connection ?? null;
}

/** The build's connection; throws outside a build that has one. */
export function buildConnection(): Connection {
  const connection = heldConnection();
  if (!connection) {
    throw new Error("@libre-publish/astro: no CMS connection. Add cms() to astro.config's integrations and set CMS_BASE_URL and CMS_API_TOKEN.");
  }
  return connection;
}

export function buildClient(): CmsClient {
  return createClient({ ...buildConnection(), digests: buildState().digests });
}

/** Keep the schema the integration checked, for the loaders. */
export function keepSchema(schema: Promise<LockedSchema>) {
  buildState().schema = schema;
}

/** The schema the integration checked against the lock, or null when it didn't (a test, a loader without cms()). */
export function heldSchema(): Promise<LockedSchema> | null {
  return buildState().schema ?? null;
}
