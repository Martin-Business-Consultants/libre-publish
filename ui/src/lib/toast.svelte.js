// Flash messages, bottom right; an error stays a little longer.
let next = 1;
class Toasts {
  items = $state([]);
  show(message, tone = "info") {
    const id = next++;
    this.items.push({ id, message, tone });
    setTimeout(() => this.dismiss(id), tone === "danger" ? 7000 : 3500);
  }
  dismiss(id) { this.items = this.items.filter((t) => t.id !== id); }
}
export const toasts = new Toasts();
export const toast = (m) => toasts.show(m, "success");
export const toastError = (e) => {
  const msg = e && e.status === 403 ? `Your role doesn't allow that${e.body?.capability ? ` (${e.body.capability})` : ""}.` : (e?.message || String(e));
  toasts.show(msg, "danger");
};
