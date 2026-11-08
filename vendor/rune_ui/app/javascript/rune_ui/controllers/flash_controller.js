import { Controller } from "@hotwired/stimulus"

// rune-flash: a notice or alert; closes on ×, and goes by itself after timeout (ms) if set.
export default class extends Controller {
  static values = { timeout: Number }

  connect() {
    if (this.timeoutValue > 0) this.timer = setTimeout(() => this.close(), this.timeoutValue)
  }

  disconnect() { clearTimeout(this.timer) }

  close() {
    this.element.classList.add("is-leaving")
    setTimeout(() => this.element.remove(), 250)
  }
}
