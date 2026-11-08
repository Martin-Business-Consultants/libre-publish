import { Controller } from "@hotwired/stimulus"

// rune-flash: a notice or alert; closes on ×, and goes by itself after timeout (ms) if set.
export default class extends Controller {
  static values = { timeout: Number }

  connect() {
    if (this.timeoutValue > 0) this.timer = setTimeout(() => this.close(), this.timeoutValue)
  }

  disconnect() { clearTimeout(this.timer) }

  // Leaves with the stylesheet's own transition (is-leaving), removed once it has played out.
  close() {
    if (this.leaving) return
    this.leaving = true
    this.element.classList.add("is-leaving")
    const seconds = getComputedStyle(this.element).transitionDuration.split(",").map(parseFloat)
    setTimeout(() => this.element.remove(), (Math.max(...seconds) * 1000 || 250) + 20)
  }
}
