import { Controller } from "@hotwired/stimulus"

// The rows' one delete dialog (layouts/shared/_row_delete_dialog), rather than one in every row:
// a row's Delete (layouts/shared/_row_links) names what goes, and this fills the dialog in,
// points its form at the record and opens it. Esc and the backdrop close it.
export default class extends Controller {
  static targets = [ "dialog", "title", "message", "form" ]

  open({ params: { name, path, message } }) {
    if (!this.hasDialogTarget) return

    const title = `Delete ${name}?`
    this.titleTarget.textContent = title
    this.dialogTarget.setAttribute("aria-label", title)
    this.messageTarget.textContent = message || "This can’t be undone."
    this.formTarget.action = path
    this.dialogTarget.showModal()
    this.dialogTarget.querySelector("button[type=submit]")?.focus()
  }

  close() {
    this.dialogTarget.close()
  }

  backdrop(event) {
    if (event.target === this.dialogTarget) this.close()
  }
}
