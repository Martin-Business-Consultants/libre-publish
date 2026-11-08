import { Controller } from "@hotwired/stimulus"

// rune-list-filter: narrows a list on the page to the items whose data-search holds what you
// type. An "empty" target shows when nothing matches.
export default class extends Controller {
  static targets = [ "query", "item", "empty" ]

  filter() {
    const query = this.queryTarget.value.trim().toLowerCase()
    let shown = 0
    this.itemTargets.forEach(item => {
      const match = !query || (item.dataset.search || item.textContent.toLowerCase()).includes(query)
      item.hidden = !match
      if (match) shown++
    })
    if (this.hasEmptyTarget) this.emptyTarget.hidden = shown > 0
  }
}
