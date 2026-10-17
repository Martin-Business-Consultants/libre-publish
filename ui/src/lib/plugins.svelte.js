// Plugins in the admin's shell: each one's place in the menu (with the
// screens the signed-in person may open, and a count to badge it with), and
// what its screens are drawn from.
import { get } from "./api.js";

class PluginMenus {
  list = $state([]);
  badges = $state({});

  async refresh() {
    this.list = (await get("/plugin_menus").catch(() => ({ menus: [] }))).menus;
    for (const m of this.list) {
      if (m.badge) get(`/x/${m.key}${m.badge}`).then((r) => (this.badges[m.key] = r.count || 0)).catch(() => {});
    }
  }
}

export const pluginMenus = new PluginMenus();

const admins = new Map();
export function pluginAdmin(key) {
  if (!admins.has(key)) admins.set(key, get(`/plugins/${key}/admin`).then((r) => r.plugin).catch((e) => { admins.delete(key); throw e; }));
  return admins.get(key);
}
