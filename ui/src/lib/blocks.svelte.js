// The block types, loaded once and shared by every editor.
import { get } from "./api.js";
class BlockTypes {
  list = $state([]);
  loaded = false;
  async load(force = false) {
    if (this.loaded && !force) return this.list;
    this.list = (await get("/block_types")).block_types;
    this.loaded = true;
    return this.list;
  }
  find(slug) { return this.list.find((t) => t.slug === slug); }
}
export const blockTypes = new BlockTypes();
