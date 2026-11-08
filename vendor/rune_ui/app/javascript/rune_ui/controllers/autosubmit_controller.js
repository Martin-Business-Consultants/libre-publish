import { Controller } from "@hotwired/stimulus"

// rune-autosubmit: submits its form when a field changes (filters), or a moment after typing
// stops (search: input->rune-autosubmit#later).
export default class extends Controller {
  static values = { delay: { type: Number, default: 300 } }

  submit() { this.element.requestSubmit() }

  later() {
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.submit(), this.delayValue)
  }

  disconnect() { clearTimeout(this.timer) }
}
