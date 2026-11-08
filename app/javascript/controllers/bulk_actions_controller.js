import { Controller } from "@hotwired/stimulus"

// A list table's bulk bar (layouts/shared/_bulk_actions). The rows' checkboxes belong to its form
// (form="…"), wherever they sit in the table; while any is ticked the bar takes the toolbar's row
// (data-bulk-active), saying how many, and each action's button posts them where it says. Delete
// asks first in a dialog. Without JavaScript the bar stays put and Delete opens a <details>.
export default class extends Controller {
  static targets = [ "bar", "count", "delete", "fallback", "clear", "dialog" ]
  static values = { form: String }

  connect() {
    this.update = this.update.bind(this)
    document.addEventListener("change", this.update)
    this.deleteTargets.forEach(button => { button.hidden = false })
    this.clearTargets.forEach(button => { button.hidden = false })
    this.fallbackTargets.forEach(details => { details.hidden = true })
    this.update()
  }

  disconnect() {
    document.removeEventListener("change", this.update)
  }

  update() {
    const count = this.#ticked.length
    this.element.toggleAttribute("data-bulk-active", count > 0)
    this.barTargets.forEach(bar => { bar.hidden = count === 0 })
    this.countTargets.forEach(target => { target.textContent = `${count} selected` })
    this.#boxes.forEach(box => box.closest("tr")?.toggleAttribute("data-picked", box.checked))
  }

  clear() {
    this.#ticked.forEach(box => {
      box.checked = false
      box.dispatchEvent(new Event("change", { bubbles: true }))
    })
  }

  confirm() {
    this.dialogTarget.showModal()
  }

  cancel() {
    this.dialogTarget.close()
  }

  backdrop(event) {
    if (event.target === this.dialogTarget) this.cancel()
  }

  get #boxes() {
    const form = document.getElementById(this.formValue)
    return form ? Array.from(form.elements).filter(element => element.type === "checkbox") : []
  }

  get #ticked() {
    return this.#boxes.filter(box => box.checked)
  }
}
