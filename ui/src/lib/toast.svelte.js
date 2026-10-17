// Flash messages (svelte-sonner, drawn by <Toasts />); an error stays a
// little longer.
import { toast as sonner } from "svelte-sonner";

export const toast = (m) => sonner.success(m);
export const toastError = (e) => {
  const msg = e && e.status === 403 ? `Your role doesn't allow that${e.body?.capability ? ` (${e.body.capability})` : ""}.` : (e?.message || String(e));
  sonner.error(msg, { duration: 7000 });
};
// toasts.show(message, tone) for a tone other than success: info or danger.
export const toasts = {
  show(m, tone = "info") { tone === "danger" ? sonner.error(m, { duration: 7000 }) : tone === "success" ? sonner.success(m) : sonner.info(m); },
};

// undoable says what happened with an Undo button for a while: the
// reversible actions (trash, a status change) ask no question first.
export function undoable(message, undo, { done = "Undone." } = {}) {
  if (!undo) return toast(message);
  sonner.success(message, {
    duration: 8000,
    action: { label: "Undo", onClick: async () => { try { await undo(); sonner.success(done); } catch (e) { toastError(e); } } },
  });
}
