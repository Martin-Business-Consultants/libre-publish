import { Controller } from "@hotwired/stimulus"

// rune-palette: ⌘K. Find anything listed by typing, go there with Enter. Opens on the
// "rune-palette:open" window event (rune-shortcuts sends it).
export default class extends Controller {
  static targets = [ "input", "item", "empty" ]
  static values = { limit: { type: Number, default: 12 } }

  connect() {
    this.onOpen = () => this.open()
    window.addEventListener("rune-palette:open", this.onOpen)
  }

  disconnect() { window.removeEventListener("rune-palette:open", this.onOpen) }

  open() {
    if (this.element.open) return
    this.element.showModal()
    this.inputTarget.value = ""
    this.filter()
    this.inputTarget.focus()
  }

  close() { this.element.close() }

  backdrop(event) { if (event.target === this.element) this.close() }

  filter() {
    const words = this.inputTarget.value.trim().toLowerCase().split(/\s+/).filter(Boolean)
    let shown = 0
    this.itemTargets.forEach(item => {
      const match = words.every(word => item.dataset.search.includes(word)) && (words.length > 0 || item.dataset.default === "true")
      item.hidden = !match || shown >= this.limitValue
      if (!item.hidden) shown++
    })
    this.emptyTarget.hidden = shown > 0
    this.select(this.visible()[0])
  }

  key(event) {
    const items = this.visible()
    const index = items.indexOf(this.selected)
    if (event.key === "ArrowDown" || (event.ctrlKey && event.key === "n")) { event.preventDefault(); this.select(items[Math.min(index + 1, items.length - 1)]) }
    else if (event.key === "ArrowUp" || (event.ctrlKey && event.key === "p")) { event.preventDefault(); this.select(items[Math.max(index - 1, 0)]) }
    else if (event.key === "Enter" && this.selected) { event.preventDefault(); this.go(this.selected) }
  }

  hover(event) { this.select(event.currentTarget) }

  choose(event) { event.preventDefault(); this.go(event.currentTarget) }

  visible() { return this.itemTargets.filter(item => !item.hidden) }

  select(item) {
    this.itemTargets.forEach(other => other.setAttribute("aria-selected", other === item))
    this.selected = item
    item?.scrollIntoView({ block: "nearest" })
  }

  go(item) {
    this.close()
    const url = item.getAttribute("href")
    window.Turbo ? window.Turbo.visit(url) : (window.location.href = url)
  }
}
