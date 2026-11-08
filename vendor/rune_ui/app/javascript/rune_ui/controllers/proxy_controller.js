import { Controller } from "@hotwired/stimulus"

// rune-proxy: clicks another control, so a menu item can do what a button elsewhere does:
//   <button data-controller="rune-proxy" data-action="rune-proxy#click"
//           data-rune-proxy-selector-param="[data-keys='?']">Keyboard shortcuts</button>
export default class extends Controller {
  click({ params: { selector } }) {
    document.querySelector(selector)?.click()
  }
}
