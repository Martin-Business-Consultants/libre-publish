import { Controller } from "@hotwired/stimulus"

// Fills a slug in from a title as it's typed, as the server makes one from a
// blank slug (parameterize): "Our Café & Bar" becomes our-cafe-bar (pages,
// entries, collections), or our_cafe_bar with separator "_" (globals and
// block types, which start with a letter). Typing in the slug takes it over;
// emptying it hands it back, from the title's next change. A saved
// record's slug never follows its title (locked), since changing it moves
// the record's address.
//
//   <form data-controller="slug" data-slug-separator-value="-" data-slug-locked-value="false">
//     <input data-slug-target="source" data-action="slug#fill">
//     <input data-slug-target="slug" data-action="slug#take">
export default class extends Controller {
  static targets = [ "source", "slug" ]
  static values = { separator: { type: String, default: "-" }, locked: Boolean }

  connect() {
    // A slug already there that isn't the title's (a form back with errors,
    // or a template's) is someone's: leave it.
    this.following = !this.lockedValue && (this.slugTarget.value === "" || this.slugTarget.value === this.#slugFrom(this.sourceTarget.value))
  }

  fill() {
    if (this.following) this.slugTarget.value = this.#slugFrom(this.sourceTarget.value)
  }

  take() {
    this.following = !this.lockedValue && this.slugTarget.value === ""
  }

  #slugFrom(text) {
    const separator = this.separatorValue
    let slug = text
      .normalize("NFKD").replace(/[\u0300-\u036f]/g, "")
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, separator)
      .replace(new RegExp(`^\\${separator}+|\\${separator}+$`, "g"), "")
    // Globals and block types start with a letter.
    if (separator === "_") slug = slug.replace(/^[^a-z]+/, "")
    return slug
  }
}
