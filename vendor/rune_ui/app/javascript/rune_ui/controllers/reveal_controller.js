import { Controller } from "@hotwired/stimulus"

// rune-reveal: shows the fields that go with the chosen option. Panels carry
// data-reveal-when="value other-value"; hidden panels' fields are disabled so they aren't sent.
export default class extends Controller {
  static targets = [ "select", "panel" ]

  connect() { this.update() }

  update() {
    const value = this.selectTarget.value
    this.panelTargets.forEach(panel => {
      const shown = panel.dataset.revealWhen.split(" ").includes(value)
      panel.hidden = !shown
      panel.querySelectorAll("input, select, textarea").forEach(field => field.disabled = !shown)
    })
  }
}
