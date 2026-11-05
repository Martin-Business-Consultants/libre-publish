import { Controller } from "@hotwired/stimulus"

// Clicks another control: a menu item standing in for a button that lives elsewhere (the
// sidebar's "Keyboard shortcuts" opens the ? sheet's own button).
//
//   <button data-controller="ui--proxy" data-action="ui--proxy#click"
//           data-ui--proxy-selector-param="[data-keys='?']">Keyboard shortcuts</button>
export default class extends Controller {
  click({ params: { selector } }) {
    document.querySelector(selector)?.click()
  }
}
