// A write's outcome, the way every editor reports it: saved, held for review
// (202: the live content is unchanged until someone approves it), or
// unchanged. A 422's field errors come back for the form to show.
import { ApiError } from "./api.js";
import { toast, toasts, toastError } from "./toast.svelte.js";

export async function save(request, what = "changes") {
  try {
    const res = await request();
    if (res && res.__status === 202) {
      toasts.show(`Sent for review (revision ${res.revision.id}): the live ${what} stays as it is until someone approves it.`, "info");
      return { ok: true, held: true, res };
    }
    if (res && res.status === "unchanged") { toasts.show("Nothing changed.", "info"); return { ok: true, unchanged: true, res }; }
    toast("Saved.");
    return { ok: true, res };
  } catch (e) {
    if (e instanceof ApiError && e.status === 422) {
      toasts.show(e.body.message && e.body.message !== "Validation failed" ? e.body.message : "Some fields need attention.", "danger");
      return { ok: false, errors: e.errors };
    }
    toastError(e);
    return { ok: false, errors: {} };
  }
}

// ⌘S / Ctrl+S runs `fn` while an editor is open.
export function saveShortcut(fn) {
  const onKey = (e) => {
    if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "s") { e.preventDefault(); fn(); }
  };
  addEventListener("keydown", onKey);
  return () => removeEventListener("keydown", onKey);
}
