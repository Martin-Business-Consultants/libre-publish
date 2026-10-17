// Bringing back what was just trashed (Undo), when the role may.
import { post } from "./api.js";
import { session } from "./session.svelte.js";

export function restorer(kind, ids, after) {
  if (!session.can("trash:write") || !ids.length) return null;
  return async () => {
    for (const id of ids) await post(`/trash/${kind}/${id}/restore`);
    after?.();
  };
}
