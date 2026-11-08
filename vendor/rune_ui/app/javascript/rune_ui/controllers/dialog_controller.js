import { Controller } from "@hotwired/stimulus"

// rune-dialog: opens its <dialog> as a modal; closes on ×, Cancel, Esc (the browser's) or a
// click on the backdrop. The first field marked autofocus (or the first button) gets focus.
export default class extends Controller {
  static targets = [ "dialog" ]

  open(event) {
    event?.preventDefault()
    this.dialogTarget.showModal()
    this.dialogTarget.querySelector("[autofocus]")?.focus()
  }

  close() { this.dialogTarget.close() }

  backdrop(event) { if (event.target === this.dialogTarget) this.close() }
}
