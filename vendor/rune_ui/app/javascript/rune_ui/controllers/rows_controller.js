import { Controller } from "@hotwired/stimulus"

// rune-rows: repeating form rows (nested attributes). New rows come from a <template> whose
// field names hold NEW_ROW, replaced with a unique index. Removing a saved row ticks its
// _destroy field and hides it; removing a new one drops it. Rows carry data-row.
export default class extends Controller {
  static targets = [ "template", "list" ]

  add(event) {
    event.preventDefault()
    const html = this.templateTarget.innerHTML.replace(/NEW_ROW/g, Date.now().toString())
    this.listTarget.insertAdjacentHTML("beforeend", html)
  }

  remove(event) {
    event.preventDefault()
    const row = event.target.closest("[data-row]")
    const destroy = row.querySelector("input[name*='_destroy']")
    if (destroy) {
      destroy.value = "1"
      row.hidden = true
    } else {
      row.remove()
    }
  }
}
