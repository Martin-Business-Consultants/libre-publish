import { Controller } from "@hotwired/stimulus"

// rune-sidebar: shows and hides the sidebar. On wide screens it collapses, as
// data-sidenav="collapsed" on <html>, remembered in localStorage under the key value (put
// sidebar_preload_tag in <head> so it holds from the first paint). On narrow screens it's a
// drawer (.sidebar-open on the shell). Buttons that toggle it get aria-expanded.
export default class extends Controller {
  static values = { key: { type: String, default: "rune.sidebar" }, breakpoint: { type: Number, default: 860 } }

  connect() {
    try { if (localStorage.getItem(this.keyValue) === "collapsed") this.root.dataset.sidenav = "collapsed" } catch {}
    this.sync()
  }

  toggle() {
    if (window.matchMedia(`(max-width: ${this.breakpointValue}px)`).matches) {
      this.element.classList.toggle("sidebar-open")
    } else {
      const collapse = this.root.dataset.sidenav !== "collapsed"
      if (collapse) this.root.dataset.sidenav = "collapsed"
      else delete this.root.dataset.sidenav
      try { collapse ? localStorage.setItem(this.keyValue, "collapsed") : localStorage.removeItem(this.keyValue) } catch {}
    }
    this.sync()
  }

  close() { this.element.classList.remove("sidebar-open"); this.sync() }

  sync() {
    const narrow = window.matchMedia(`(max-width: ${this.breakpointValue}px)`).matches
    const expanded = narrow ? this.element.classList.contains("sidebar-open") : this.root.dataset.sidenav !== "collapsed"
    this.element.querySelectorAll("[data-action*='rune-sidebar#toggle']").forEach(button => button.setAttribute("aria-expanded", expanded))
  }

  get root() { return document.documentElement }
}
