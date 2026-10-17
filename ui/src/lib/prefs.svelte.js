// The signed-in person's admin preferences (list columns, rows per page,
// density, the publish checklist), kept on the server so they follow the
// person: read from the session, written back a moment after a change.
import { api } from "./api.js";
import { session } from "./session.svelte.js";

let pending = {}, timer;

export const prefs = {
  get(key, fallback) {
    const v = session.me?.preferences?.[key];
    return v === undefined ? fallback : v;
  },
  set(key, value) {
    if (!session.me) return;
    session.me.preferences = { ...(session.me.preferences || {}), [key]: value };
    pending[key] = value;
    clearTimeout(timer);
    timer = setTimeout(() => { const body = pending; pending = {}; api("PATCH", "/me/preferences", body, { quiet: true }).catch(() => {}); }, 400);
  },
};

// A list's view: its hidden columns, rows a page and density.
export function listView(name, defaults = {}) {
  const key = "list:" + name;
  const read = () => ({ hidden: [], per: 25, density: "compact", ...defaults, ...(prefs.get(key, {}) || {}) });
  return {
    get hidden() { return read().hidden; },
    get per() { return read().per; },
    get density() { return read().density; },
    update(change) { prefs.set(key, { ...read(), ...change }); },
  };
}
