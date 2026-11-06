import { Controller } from "@hotwired/stimulus"

// A data table's Columns menu (ui/_data_table): each checkbox shows or hides the cells of one
// column (th, td and col carrying data-column="key"). The choice is this browser's, per table
// (localStorage, keyed by the table's id), and holds through pagination, which appends rows,
// and Turbo morphs, which re-render them: an observer hides new cells as they arrive.
export default class extends Controller {
  static targets = [ "toggle", "table" ]
  static values = { key: String }

  connect() {
    const hidden = this.#stored
    this.toggleTargets.forEach(toggle => { toggle.checked = !hidden.includes(toggle.value) })
    this.apply()
    this.observer = new MutationObserver(() => this.apply())
    if (this.hasTableTarget) this.observer.observe(this.tableTarget, { childList: true, subtree: true, attributes: true, attributeFilter: [ "hidden" ] })
  }

  disconnect() {
    this.observer?.disconnect()
  }

  toggle() {
    this.#stored = this.#hidden
    this.apply()
  }

  apply() {
    const hidden = this.#hidden
    this.element.querySelectorAll("[data-column]").forEach(cell => {
      const hide = hidden.includes(cell.dataset.column)
      if (cell.hidden !== hide) cell.hidden = hide
    })
  }

  get #hidden() {
    return this.toggleTargets.filter(toggle => !toggle.checked).map(toggle => toggle.value)
  }

  get #storageKey() {
    return `data-table:${this.keyValue}:hidden`
  }

  get #stored() {
    try { return JSON.parse(localStorage.getItem(this.#storageKey)) || [] } catch { return [] }
  }

  set #stored(keys) {
    try { localStorage.setItem(this.#storageKey, JSON.stringify(keys)) } catch {}
  }
}
