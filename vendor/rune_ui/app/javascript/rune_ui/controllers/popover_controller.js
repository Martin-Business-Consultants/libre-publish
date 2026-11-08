import { Controller } from "@hotwired/stimulus"

// rune-popover: places a [popover] menu beside its trigger when it opens (side: bottom|top,
// align: start|end), keeps it there on scroll, moves through its items with the arrow keys, and
// closes it once one is chosen. The popover attribute itself handles Esc and clicks outside.
export default class extends Controller {
  static targets = [ "trigger", "popover" ]
  static values = { side: { type: String, default: "bottom" }, align: { type: String, default: "end" } }

  connect() {
    this.onToggle = (event) => event.newState === "open" ? this.opened() : this.closed()
    this.place = this.place.bind(this)
    this.popoverTarget.addEventListener("toggle", this.onToggle)
  }

  disconnect() {
    this.popoverTarget.removeEventListener("toggle", this.onToggle)
    this.closed()
  }

  opened() {
    this.place()
    window.addEventListener("scroll", this.place, true)
    window.addEventListener("resize", this.place)
    this.items()[0]?.focus({ preventScroll: true })
  }

  closed() {
    window.removeEventListener("scroll", this.place, true)
    window.removeEventListener("resize", this.place)
  }

  place() {
    const trigger = this.triggerTarget.getBoundingClientRect()
    const popover = this.popoverTarget
    const { offsetWidth: width, offsetHeight: height } = popover
    const gap = 4
    let top = this.sideValue === "top" ? trigger.top - height - gap : trigger.bottom + gap
    if (top + height > window.innerHeight && trigger.top - height - gap > 0) top = trigger.top - height - gap
    if (top < 0) top = trigger.bottom + gap
    let left = this.alignValue === "start" ? trigger.left : trigger.right - width
    left = Math.min(Math.max(left, 8), window.innerWidth - width - 8)
    popover.style.top = `${Math.round(top)}px`
    popover.style.left = `${Math.round(left)}px`
  }

  key(event) {
    const items = this.items()
    if (items.length === 0) return
    const index = items.indexOf(document.activeElement)
    if (event.key === "ArrowDown") { event.preventDefault(); items[(index + 1) % items.length].focus() }
    else if (event.key === "ArrowUp") { event.preventDefault(); items[(index - 1 + items.length) % items.length].focus() }
    else if (event.key === "Home") { event.preventDefault(); items[0].focus() }
    else if (event.key === "End") { event.preventDefault(); items[items.length - 1].focus() }
  }

  chose(event) {
    if (event.target.closest(".menu__item")) this.popoverTarget.hidePopover()
  }

  items() { return [ ...this.popoverTarget.querySelectorAll(".menu__item:not([disabled])") ] }
}
