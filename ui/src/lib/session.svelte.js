// Who's signed in, what they can do, and the site's name and branding.
import { brand } from "./branding.svelte.js";

class Session {
  me = $state(null);
  csrf = $state("");
  site = $state("");
  version = $state("");
  needsSetup = $state(false);
  ready = $state(false);

  can(capability) {
    return !!this.me && this.me.capabilities.includes(capability);
  }

  async load() {
    const { get } = await import("./api.js");
    try {
      const s = await get("/session", { quiet: true });
      this.site = s.site || "";
      brand.set(s.branding);
      this.version = s.version || "";
      this.needsSetup = !!s.needs_setup;
      this.me = s.signed_in ? s : null;
      this.csrf = s.signed_in ? s.csrf : "";
    } catch {
      this.me = null;
    }
    this.ready = true;
  }

  signedOut() {
    this.me = null;
    this.csrf = "";
  }
}

export const session = new Session();
