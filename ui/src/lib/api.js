// The admin talks to the same /api as the CLI and agents, signed in by the
// session cookie, with the session's CSRF token on every write.
import { session } from "./session.svelte.js";
import { maintenance } from "./maintenance.svelte.js";

export class ApiError extends Error {
  constructor(status, body) {
    super((body && (body.message || body.error)) || `HTTP ${status}`);
    this.status = status;
    this.body = body || {};
  }
  get errors() { return this.body.errors || {}; }
}

export async function api(method, path, body, { quiet = false } = {}) {
  const headers = { Accept: "application/json" };
  let payload = body;
  if (body !== undefined && !(body instanceof FormData) && !(body instanceof Blob)) {
    headers["Content-Type"] = "application/json";
    payload = JSON.stringify(body);
  }
  if (method !== "GET") headers["X-CSRF-Token"] = session.csrf;
  const res = await fetch("/api" + path, { method, headers, body: payload, credentials: "same-origin" });
  if (res.status === 204) { maintenance.on = false; return null; }
  const text = await res.text();
  let data = null;
  try { data = text ? JSON.parse(text) : null; } catch { data = { message: text }; }
  if (res.status === 401 && !quiet) session.signedOut();
  maintenance.on = res.status === 503 && data?.error === "maintenance";
  if (!res.ok) throw new ApiError(res.status, data);
  data = data || {};
  Object.defineProperty(data, "__status", { value: res.status, enumerable: false });
  return data;
}

export const get = (path, opts) => api("GET", path, undefined, opts);
export const post = (path, body, opts) => api("POST", path, body, opts);
export const patch = (path, body, opts) => api("PATCH", path, body, opts);
export const del = (path, opts) => api("DELETE", path, undefined, opts);

// A page's path, escaped segment by segment for a URL.
export const pagePath = (path) => path.split("/").map(encodeURIComponent).join("/");
