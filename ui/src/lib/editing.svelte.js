// Editing a record in the admin: its lock (who has it open, kept fresh by
// a heartbeat, taken over if need be) and its autosave (what's typed but not
// saved, put aside every few seconds and offered back after a crash or a
// takeover). See internal/cms/editing.go.
import { get, post, api } from "./api.js";
import { session } from "./session.svelte.js";

const HEARTBEAT = 30_000;
const AUTOSAVE = 15_000;

export class Editing {
  // "starting", "mine", "locked" (someone else has it), "lost" (taken over
  // from us), or "off" (nothing to lock: a new record).
  state = $state("starting");
  holder = $state(null);
  // An autosave newer than the record, offered on open.
  offer = $state(null);
  autosavedAt = $state(null);

  #type; #id; #key; #snapshot; #dirty; #recordUpdatedAt;
  #timers = [];
  #last = "";

  constructor({ type, id, key, snapshot, dirty, updatedAt }) {
    this.#type = type; this.#id = id; this.#key = key || String(id);
    this.#snapshot = snapshot; this.#dirty = dirty; this.#recordUpdatedAt = updatedAt;
  }

  async start() {
    if (this.#id) await this.#acquire(false, false);
    else this.state = "off";
    await this.#lookForAutosave();
    this.#timers.push(setInterval(() => this.autosaveNow(), AUTOSAVE));
    if (this.#id) this.#timers.push(setInterval(() => { if (this.state === "mine") this.#acquire(false, true); }, HEARTBEAT));
    addEventListener("pagehide", this.#leave);
  }

  async #acquire(takeOver, held) {
    try {
      await post("/locks", { type: this.#type, id: this.#id, take_over: takeOver, held }, { quiet: true });
      this.state = "mine"; this.holder = null;
    } catch (e) {
      if (e.status !== 409) return; // offline, or a blip: the next heartbeat tries again
      this.holder = e.body.lock;
      if (e.body.error === "lock_lost") { await this.autosaveNow(true); this.state = "lost"; }
      else this.state = "locked";
    }
  }

  takeOver() { return this.#acquire(true, false); }

  async #lookForAutosave() {
    try {
      const a = (await get(`/autosaves?type=${this.#type}&key=${encodeURIComponent(this.#key)}`)).autosave;
      if (!a) return;
      const newer = !this.#recordUpdatedAt || new Date(a.updated_at) > new Date(this.#recordUpdatedAt);
      if (newer && JSON.stringify(a.data) !== this.#snapshot()) this.offer = a;
      else this.discard();
    } catch {}
  }

  // autosaveNow puts aside what's typed, when there's something new.
  async autosaveNow(force = false) {
    if (this.state === "locked" || this.state === "lost" || (!force && !this.#dirty())) return;
    const snap = this.#snapshot();
    if (!snap || snap === this.#last) return;
    try {
      await api("PUT", `/autosaves?type=${this.#type}&key=${encodeURIComponent(this.#key)}`, { data: JSON.parse(snap) }, { quiet: true });
      this.#last = snap; this.autosavedAt = new Date();
    } catch {}
  }

  // After a save: what was put aside is no longer needed.
  async saved(updatedAt) {
    this.#recordUpdatedAt = updatedAt; this.#last = ""; this.autosavedAt = null; this.offer = null;
    await this.discard();
  }

  async discard() {
    this.offer = null;
    try { await api("DELETE", `/autosaves?type=${this.#type}&key=${encodeURIComponent(this.#key)}`, undefined, { quiet: true }); } catch {}
  }

  #leave = () => {
    if (this.state !== "mine") return;
    fetch(`/api/locks/${this.#type}/${this.#id}`, { method: "DELETE", keepalive: true, credentials: "same-origin", headers: { "X-CSRF-Token": session.csrf } });
  };

  stop() {
    this.#timers.forEach(clearInterval);
    removeEventListener("pagehide", this.#leave);
    this.autosaveNow();
    this.#leave();
  }
}
