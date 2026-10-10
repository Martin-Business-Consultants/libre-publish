import { Controller } from "@hotwired/stimulus"

// The admin menu's two states, both on <html> so CSS can style everything
// from one place: data-menu="folded" (icons only, remembered in localStorage
// and applied before paint by layouts/_menu_preference) and data-menu-open
// (the drawer on narrow screens, closed again on every visit). The menu stays
// put while the page scrolls, and scrolls on its own when it's taller than
// the window (.admin-menu--scrolls, set here; Safari clips fly-outs to a
// scrolling menu, so only one too tall to fit scrolls).
//
// Which item's fly-out is open is this controller's (.admin-menu__item--open),
// not :hover's, so the pointer can travel to a fly-out across other items:
// one opens at once when none is, stays open CLOSE_DELAY after the pointer
// leaves it, and gives way to another item's after SWITCH_DELAY, so passing
// over an item on the way doesn't take over.
const CLOSE_DELAY = 400
const SWITCH_DELAY = 300

export default class extends Controller {
  static targets = [ "foldToggle", "drawerToggle" ]

  connect() {
    this.closeDrawer = this.closeDrawer.bind(this)
    this.placeFlyout = this.placeFlyout.bind(this)
    this.replaceFlyout = this.replaceFlyout.bind(this)
    this.hover = this.hover.bind(this)
    this.leave = this.leave.bind(this)
    document.addEventListener("turbo:before-visit", this.closeDrawer)
    this.#menu?.addEventListener("mouseover", this.hover)
    this.#menu?.addEventListener("mouseleave", this.leave)
    this.#menu?.addEventListener("focusin", this.placeFlyout)
    this.#menu?.addEventListener("scroll", this.replaceFlyout, { passive: true })
    this.#watchHeight()
    this.#sync()
  }

  disconnect() {
    clearTimeout(this.timer)
    this.heightObserver?.disconnect()
    document.removeEventListener("turbo:before-visit", this.closeDrawer)
    this.#menu?.removeEventListener("mouseover", this.hover)
    this.#menu?.removeEventListener("mouseleave", this.leave)
    this.#menu?.removeEventListener("focusin", this.placeFlyout)
    this.#menu?.removeEventListener("scroll", this.replaceFlyout)
  }

  // The pointer is over an item (or its fly-out, which sits inside it).
  hover(event) {
    const item = event.target.closest(".admin-menu__item")
    const flyingOut = item?.querySelector(":scope > .admin-menu__submenu") ? item : null
    clearTimeout(this.timer)

    if (flyingOut && flyingOut === this.open) return
    if (!flyingOut) return this.#later(() => this.#openFlyout(null), CLOSE_DELAY)
    if (!this.open) return this.#openFlyout(flyingOut)
    this.#later(() => this.#openFlyout(flyingOut), SWITCH_DELAY)
  }

  leave() {
    this.#later(() => this.#openFlyout(null), CLOSE_DELAY)
  }

  #later(action, delay) {
    clearTimeout(this.timer)
    this.timer = setTimeout(action, delay)
  }

  #openFlyout(item) {
    this.open?.classList.remove("admin-menu__item--open")
    this.open = item
    if (!item) return

    item.classList.add("admin-menu__item--open")
    this.placeFlyout({ target: item })
  }

  // Fly-outs are fixed, beside the menu, so they need placing: level with
  // their item, shifted up just enough to stay in the window (Settings, at
  // the bottom, opens upward).
  placeFlyout(event) {
    const item = event.target.closest(".admin-menu__item")
    const flyout = item?.querySelector(":scope > .admin-menu__submenu")
    if (!flyout) return

    const { top, bottom } = item.getBoundingClientRect()
    flyout.style.setProperty("--flyout-top", `${top}px`)
    requestAnimationFrame(() => {
      // Too tall to open downward: open upward, ending level with the item.
      if (top + flyout.offsetHeight > window.innerHeight) {
        const bar = this.#menu.getBoundingClientRect().top
        flyout.style.setProperty("--flyout-top", `${Math.max(bar, bottom - flyout.offsetHeight)}px`)
      }
    })
  }

  // Scrolling the menu moves the open item; keep its fly-out beside it.
  replaceFlyout() {
    const item = this.open || this.#menu.querySelector(".admin-menu__item:focus-within")
    if (item) this.placeFlyout({ target: item })
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

  // The menu, and its list of items, change size with the window and with
  // what's open; each time, scroll only if the items no longer fit.
  #watchHeight() {
    const menu = this.#menu
    if (!menu) return

    this.heightObserver = new ResizeObserver(() => {
      menu.classList.toggle("admin-menu--scrolls", menu.scrollHeight > menu.clientHeight)
    })
    this.heightObserver.observe(menu)
    for (const child of menu.children) this.heightObserver.observe(child)
  }

  get #menu() {
    return document.getElementById("admin-menu")
  }

  #sync() {
    const root = document.documentElement
    if (this.hasFoldToggleTarget) this.foldToggleTarget.setAttribute("aria-pressed", root.dataset.menu === "folded")
    if (this.hasDrawerToggleTarget) this.drawerToggleTarget.setAttribute("aria-expanded", root.hasAttribute("data-menu-open"))
  }
}
