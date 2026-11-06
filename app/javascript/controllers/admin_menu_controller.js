import { Controller } from "@hotwired/stimulus"

// The sidebar's two states, both on <html> so CSS can draw everything from one place
// (ui/app-shell.css): data-menu="folded" (icons only, remembered in localStorage and applied
// before paint by layouts/_menu_preference) and data-menu-open (the drawer below 768px, closed
// again on every visit). The header's toggle ([) folds the sidebar on a wide screen and opens
// the drawer on a narrow one.
const NARROW = "(max-width: 767px)"

export default class extends Controller {
  static targets = [ "toggle" ]

  connect() {
    this.closeDrawer = this.closeDrawer.bind(this)
    document.addEventListener("turbo:before-visit", this.closeDrawer)
    this.#sync()
  }

  disconnect() {
    document.removeEventListener("turbo:before-visit", this.closeDrawer)
  }

  toggle() {
    window.matchMedia(NARROW).matches ? this.toggleDrawer() : this.toggleFold()
  }

  toggleFold() {
    const folded = document.documentElement.dataset.menu !== "folded"
    if (folded) {
      document.documentElement.dataset.menu = "folded"
    } else {
      delete document.documentElement.dataset.menu
    }
    try { localStorage.setItem("admin-menu", folded ? "folded" : "open") } catch (error) {}
    this.#sync()
  }

  toggleDrawer() {
    document.documentElement.toggleAttribute("data-menu-open")
    this.#sync()
  }

  closeDrawer() {
    document.documentElement.removeAttribute("data-menu-open")
    this.#sync()
  }

  #sync() {
    const root = document.documentElement
    const expanded = window.matchMedia(NARROW).matches ? root.hasAttribute("data-menu-open") : root.dataset.menu !== "folded"
    this.toggleTargets.forEach(toggle => toggle.setAttribute("aria-expanded", expanded))
  }
}
