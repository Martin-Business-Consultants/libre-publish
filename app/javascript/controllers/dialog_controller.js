import { Controller } from "@hotwired/stimulus"

// For plugins' screens drawn before 1.34 (the core's dialogs are rune_ui's rune-dialog): a modal
// <dialog> (data-dialog-target="dialog") opened with dialog#open and closed with dialog#close,
// Esc, or a click on the backdrop outside its box. data-dialog-auto-open-value="true" opens it
// as it arrives (a form sent back with errors); lazy frames inside load once it opens.
// data-dialog-modal-value is accepted and ignored: every dialog here is modal. Dispatches
// dialog:show and dialog:close, which plugins' outlets listen for.
export default class extends Controller {
  static targets = [ "dialog" ]
  static values = { autoOpen: Boolean, modal: { type: Boolean, default: true } }

  connect() {
    this.dialogTarget.addEventListener("click", this.#backdrop)
    if (this.autoOpenValue) this.open()
  }

  disconnect() {
    this.dialogTarget.removeEventListener("click", this.#backdrop)
  }

  open() {
    if (!this.dialogTarget.open) this.dialogTarget.showModal()
    this.dialogTarget.querySelectorAll("turbo-frame[loading='lazy']").forEach(frame => { frame.loading = "eager" })
    this.dispatch("show")
  }

  toggle() {
    this.dialogTarget.open ? this.close() : this.open()
  }

  close() {
    if (this.dialogTarget.open) this.dialogTarget.close()
    this.dispatch("close")
  }

  #backdrop = (event) => {
    const dialog = this.dialogTarget
    if (event.target !== dialog || !dialog.open) return
    const box = dialog.getBoundingClientRect()
    const inside = event.clientX >= box.left && event.clientX <= box.right && event.clientY >= box.top && event.clientY <= box.bottom
    if (!inside) this.close()
  }
}
