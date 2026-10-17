// What the shell shows around every screen: the collections (for the menu
// and "+ New"), how many changes wait for review, and the public site URL.
import { get } from "./api.js";
import { pluginMenus } from "./plugins.svelte.js";

class Site {
  collections = $state([]);
  pendingReviews = $state(0);
  siteURL = $state("");

  async refresh() {
    const [cols, revs, general] = await Promise.all([
      get("/collections").catch(() => ({ collections: [] })),
      get("/revisions").catch(() => ({ revisions: [] })),
      get("/settings/general").catch(() => ({ setting: { data: {} } })),
    ]);
    this.collections = cols.collections;
    this.pendingReviews = revs.revisions.length;
    this.siteURL = general.setting?.data?.site_base_url || "";
    pluginMenus.refresh();
  }
}

export const site = new Site();
