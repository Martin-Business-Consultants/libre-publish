/**
 * Where the CMS is and how to reach it. At build time the integration resolves
 * it once (options, then the environment and .env) and keeps it for the
 * content loaders, which run in the same process (build-connection.ts). At
 * request time the runtime reads it from astro:env (runtime/env.ts), which on
 * Cloudflare means the Worker's variables and secrets.
 */
import { loadEnv } from "vite";
import { connectionFrom, type Connection } from "./build-connection.js";

export { buildClient, buildConnection, buildState, connectionFrom, keepConnection, keepSchema, TOKEN_VARIABLE, URL_VARIABLE, type Connection } from "./build-connection.js";

export function resolveConnection(root: string, mode: string, options: { url?: string; token?: string }): Connection | null {
  const env = { ...loadEnv(mode, root, ""), ...process.env };
  return connectionFrom((name) => env[name], options);
}

