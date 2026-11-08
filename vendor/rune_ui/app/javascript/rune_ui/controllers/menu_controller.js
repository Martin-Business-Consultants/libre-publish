import { Controller } from "@hotwired/stimulus"

// rune-menu: a <details> dropdown; closes on Escape, on a click elsewhere, and after choosing.
export default class extends Controller {
  connect() {
    this.outside = (event) => { if (!this.element.contains(event.target)) this.close() }
    this.escape = (event) => { if (event.key === "Escape") this.close() }
    document.addEventListener("click", this.outside)
    document.addEventListener("keydown", this.escape)
  }

  disconnect() {
    document.removeEventListener("click", this.outside)
    document.removeEventListener("keydown", this.escape)
  }

  close() { this.element.open = false }
}
