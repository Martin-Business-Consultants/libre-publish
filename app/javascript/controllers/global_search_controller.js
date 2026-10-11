import { Controller } from "@hotwired/stimulus"

const MOD_K = event => (event.metaKey || event.ctrlKey) && !event.altKey && event.key.toLowerCase() === "k"

// Search everything, in a modal (layouts/shared/global_search): ⌘K / Ctrl+K
// or the admin bar's search link opens it; each keystroke asks for results
// (searches/_quick), the arrow keys walk them and Enter opens the one picked.
export default class extends Controller {
  static targets = [ "input", "results", "result" ]
  static values = { url: String }

  connect() {
    this.keydown = this.keydown.bind(this)
    this.clicked = this.clicked.bind(this)
    document.addEventListener("keydown", this.keydown)
    document.addEventListener("click", this.clicked)
  }

  disconnect() {
    document.removeEventListener("keydown", this.keydown)
    document.removeEventListener("click", this.clicked)
    clearTimeout(this.timer)
  }

  keydown(event) {
    if (!MOD_K(event)) return
    event.preventDefault()
    this.element.open ? this.element.close() : this.open()
  }

  clicked(event) {
    const opener = event.target.closest?.("[data-global-search-open]")
    if (!opener || event.metaKey || event.ctrlKey || event.shiftKey) return
    event.preventDefault()
    this.open()
  }

  open() {
    if (!this.element.open) this.element.showModal()
    this.inputTarget.focus()
    this.inputTarget.select()
  }

  search() {
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.#fetch(), 90)
  }

  // ↑ ↓ pick a result, Enter opens it.
  navigate(event) {
    if (MOD_K(event)) return
    const results = this.resultTargets
    if (event.key === "ArrowDown" || event.key === "ArrowUp") {
      event.preventDefault()
      if (!results.length) return
      const step = event.key === "ArrowDown" ? 1 : -1
      this.#select((this.#index() + step + results.length) % results.length)
    } else if (event.key === "Enter" && event.target === this.inputTarget) {
      event.preventDefault()
      clearTimeout(this.timer)
      const picked = results[this.#index()]
      if (picked) this.#go(picked)
      else this.#fetch().then(() => { if (this.resultTargets[0]) this.#go(this.resultTargets[0]) })
    }
  }

  hover(event) {
    this.#select(this.resultTargets.indexOf(event.currentTarget), { scroll: false })
  }

  // A click on the backdrop lands on the dialog itself, outside its box.
  closeOnBackdrop(event) {
    if (event.target !== this.element) return
    const box = this.element.getBoundingClientRect()
    const inside = event.clientX >= box.left && event.clientX <= box.right && event.clientY >= box.top && event.clientY <= box.bottom
    if (!inside) this.element.close()
  }

  async #fetch() {
    const term = this.inputTarget.value.trim()
    const url = new URL(this.urlValue, window.location.href)
    url.searchParams.set("quick", "1")
    url.searchParams.set("q", term)

    this.controller?.abort()
    this.controller = new AbortController()
    try {
      const response = await fetch(url, { headers: { Accept: "text/html" }, signal: this.controller.signal })
      if (!response.ok || term !== this.inputTarget.value.trim()) return
      this.resultsTarget.innerHTML = await response.text()
      this.resultsTarget.scrollTop = 0
      this.#select(0)
    } catch (error) {
      if (error.name !== "AbortError") throw error
    }
  }

  #go(link) {
    this.element.close()
    if (window.Turbo) window.Turbo.visit(link.href)
    else window.location.href = link.href
  }

  #index() {
    return this.resultTargets.findIndex(result => result.getAttribute("aria-selected") === "true")
  }

  #select(index, { scroll = true } = {}) {
    this.resultTargets.forEach((result, at) => result.setAttribute("aria-selected", at === index))
    if (scroll) this.resultTargets[index]?.scrollIntoView({ block: "nearest" })
  }
}
