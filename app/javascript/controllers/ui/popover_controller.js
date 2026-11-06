import { Controller } from "@hotwired/stimulus"

// Places a native popover (ui-menu, ui-popover) beside the button that opens it, and gives a
// menu shadcn's keyboard: arrows and Home/End move between items, a letter jumps to the next
// item starting with it, choosing an item closes the menu. The popover attribute does the rest
// (opening, light dismiss, Escape, the top layer).
//
//   <div data-controller="ui--popover" data-ui--popover-align-value="end">
//     <button popovertarget="menu-1" class="ui-button ui-button--outline">Open</button>
//     <div id="menu-1" popover class="ui-menu" data-ui--popover-target="popover">…</div>
//   </div>
//
// side: bottom (default) or top; align: start (default), center or end.
export default class extends Controller {
  static targets = [ "popover" ]
  static values = { side: { type: String, default: "bottom" }, align: { type: String, default: "start" }, offset: { type: Number, default: 4 } }

  popoverTargetConnected(popover) {
    popover.addEventListener("toggle", this.#toggled)
    popover.addEventListener("keydown", this.#keydown)
    popover.addEventListener("click", this.#clicked)
  }

  popoverTargetDisconnected(popover) {
    popover.removeEventListener("toggle", this.#toggled)
    popover.removeEventListener("keydown", this.#keydown)
    popover.removeEventListener("click", this.#clicked)
    window.removeEventListener("resize", this.#reposition)
    window.removeEventListener("scroll", this.#reposition, true)
  }

  close() {
    if (this.hasPopoverTarget && this.popoverTarget.matches(":popover-open")) this.popoverTarget.hidePopover()
  }

  get #trigger() {
    return this.element.querySelector(`[popovertarget="${this.popoverTarget.id}"]`)
  }

  get #items() {
    return [ ...this.popoverTarget.querySelectorAll(".ui-menu__item:not([aria-disabled=true]):not(:disabled)") ]
      .filter(item => item.offsetParent !== null)
  }

  #toggled = (event) => {
    const open = event.newState === "open"
    this.#trigger?.setAttribute("aria-expanded", open)

    if (open) {
      this.#place()
      window.addEventListener("resize", this.#reposition)
      window.addEventListener("scroll", this.#reposition, true)
      if (this.popoverTarget.classList.contains("ui-menu")) this.#items[0]?.focus({ preventScroll: true })
    } else {
      window.removeEventListener("resize", this.#reposition)
      window.removeEventListener("scroll", this.#reposition, true)
    }
  }

  #reposition = () => this.#place()

  #place() {
    const trigger = this.#trigger
    if (!trigger) return

    const popover = this.popoverTarget
    const anchor = trigger.getBoundingClientRect()
    const box = popover.getBoundingClientRect()
    const margin = 8

    let top = this.sideValue === "top" ? anchor.top - box.height - this.offsetValue : anchor.bottom + this.offsetValue
    if (top + box.height > window.innerHeight - margin && anchor.top - box.height - this.offsetValue > margin) {
      top = anchor.top - box.height - this.offsetValue
    }

    let left = anchor.left
    if (this.alignValue === "end") left = anchor.right - box.width
    if (this.alignValue === "center") left = anchor.left + (anchor.width - box.width) / 2
    left = Math.max(margin, Math.min(left, window.innerWidth - box.width - margin))

    popover.style.top = `${Math.max(margin, top)}px`
    popover.style.left = `${left}px`
    popover.dataset.placed = ""
  }

  #clicked = (event) => {
    const item = event.target.closest(".ui-menu__item")
    // A checkable item stays open, as shadcn's checkbox items do.
    if (item && !item.querySelector("input[type=checkbox]")) requestAnimationFrame(() => this.close())
  }

  #keydown = (event) => {
    if (!this.popoverTarget.classList.contains("ui-menu")) return

    const items = this.#items
    const index = items.indexOf(document.activeElement)
    let next

    switch (event.key) {
      case "ArrowDown": next = items[(index + 1) % items.length]; break
      case "ArrowUp": next = items[(index - 1 + items.length) % items.length]; break
      case "Home": next = items[0]; break
      case "End": next = items.at(-1); break
      case "Tab": this.close(); return
      default:
        if (event.key.length === 1 && /\S/.test(event.key)) {
          const letter = event.key.toLowerCase()
          const after = [ ...items.slice(index + 1), ...items.slice(0, index + 1) ]
          next = after.find(item => item.textContent.trim().toLowerCase().startsWith(letter))
        }
    }

    if (next) {
      event.preventDefault()
      event.stopPropagation()
      next.focus()
    }
  }
}
