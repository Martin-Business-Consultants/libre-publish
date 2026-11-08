import { Controller } from "@hotwired/stimulus"

// rune-clipboard: copies a value and says so on the button for a moment (its label, or its
// tooltip for an icon button).
export default class extends Controller {
  static values = { text: String }
  static targets = [ "button" ]

  async copy() {
    await navigator.clipboard.writeText(this.textValue)
    const button = this.buttonTarget
    const iconOnly = button.classList.contains("icon-button")
    const before = iconOnly ? button.title : button.textContent
    if (iconOnly) { button.title = "Copied"; button.classList.add("is-done") } else { button.textContent = "Copied" }
    setTimeout(() => {
      if (iconOnly) { button.title = before; button.classList.remove("is-done") } else { button.textContent = before }
    }, 1500)
  }
}
