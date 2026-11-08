import { Controller } from "@hotwired/stimulus"

// rune-dialog: opens its <dialog> as a modal; closes on ×, Cancel, Esc (the browser's) or a
// click on the backdrop. The first field marked autofocus (or the first button) gets focus.
//
// data-rune-dialog-auto-open-value="true" opens it as it arrives (a form sent back with errors).
// A link that opens it and loads a turbo-frame inside it (data-turbo-frame) still goes, so the
// frame fills in behind the open dialog; lazy frames inside load once it opens.
export default class extends Controller {
  static targets = [ "dialog" ]
  static values = { autoOpen: Boolean }

  connect() { if (this.autoOpenValue && !this.dialogTarget.open) this.open() }

  open(event) {
    if (!event?.currentTarget?.dataset?.turboFrame) event?.preventDefault()
    if (!this.dialogTarget.open) this.dialogTarget.showModal()
    this.dialogTarget.querySelectorAll("turbo-frame[loading='lazy']").forEach(frame => { frame.loading = "eager" })
    this.dialogTarget.querySelector("[autofocus]")?.focus()
  }

  close() { this.dialogTarget.close() }

  // A click on the backdrop lands on the <dialog> itself, outside its box. So does one on the
  // empty part of a box its content doesn't fill (a sheet's lower half), which stays open.
  backdrop(event) {
    if (event.target !== this.dialogTarget) return
    const box = this.dialogTarget.getBoundingClientRect()
    const inside = event.clientX >= box.left && event.clientX <= box.right && event.clientY >= box.top && event.clientY <= box.bottom
    if (!inside) this.close()
  }
}
