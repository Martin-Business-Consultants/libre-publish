import { Controller } from "@hotwired/stimulus"

// The asset picker's grid, a page at a time: when the "More" link at its end
// comes into view in the sheet, the next page's tiles are fetched and added,
// with that page's own link, if there's more. (A lazy turbo-frame won't do:
// Turbo doesn't load one inside a modal dialog.)
export default class extends Controller {
  static targets = [ "next" ]

  connect() {
    this.observer = new IntersectionObserver(entries => {
      if (entries.some(entry => entry.isIntersecting)) this.load()
    }, { root: this.element.closest("dialog"), rootMargin: "0px 0px 600px 0px" })
  }

  disconnect() {
    this.observer.disconnect()
  }

  nextTargetConnected(element) {
    this.observer.observe(element)
  }

  nextTargetDisconnected(element) {
    this.observer.unobserve(element)
  }

  async load(event) {
    event?.preventDefault()
    const next = this.hasNextTarget && this.nextTarget
    const link = next && next.querySelector("a")
    if (!link || this.loading) return

    this.loading = true
    link.textContent = "Loading…"
    try {
      const response = await fetch(link.href, { headers: { Accept: "text/html" } })
      if (!response.ok) throw new Error(response.statusText)
      const page = new DOMParser().parseFromString(await response.text(), "text/html").querySelector("ul")
      next.replaceWith(...page.children)
    } catch {
      link.textContent = "More"
    } finally {
      this.loading = false
    }
  }
}
