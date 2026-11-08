import { Controller } from "@hotwired/stimulus"

// rune-shortcuts: keyboard shortcuts for the whole app (on the shell, beside rune-sidebar):
//   ⌘K / Ctrl+K   search and jump (the palette)
//   ⌘↵ / Ctrl+↵   send the form you're typing in (from a rich text field too)
//   ⇧⌘B           show or hide the sidebar
//   ⌘[ / ⌘]       previous / next, from links marked data-shortcut="prev" / "next"
//   j / k         move through a list's items (data-nav-item); Enter opens one
export default class extends Controller {
  handle(event) {
    const mod = event.metaKey || event.ctrlKey
    const typing = event.target.closest("input, textarea, select, [contenteditable], lexxy-editor")

    if (mod && event.key.toLowerCase() === "k") { event.preventDefault(); return this.palette() }
    if (mod && event.key === "Enter") {
      const form = event.target.closest("form")
      if (form) { event.preventDefault(); form.requestSubmit() }
      return
    }
    if (mod && event.shiftKey && event.key.toLowerCase() === "b") { event.preventDefault(); return this.sidebar()?.toggle() }
    if (mod && (event.key === "[" || event.key === "]")) {
      const link = document.querySelector(`[data-shortcut="${event.key === "[" ? "prev" : "next"}"]`)
      if (link) { event.preventDefault(); link.click() }
      return
    }
    if (typing || mod || event.altKey) return
    if (event.key === "j" || event.key === "k") { event.preventDefault(); this.move(event.key === "j" ? 1 : -1) }
  }

  palette() { window.dispatchEvent(new CustomEvent("rune-palette:open")) }

  sidebar() { return this.application.getControllerForElementAndIdentifier(this.element, "rune-sidebar") }

  move(step) {
    const items = [ ...document.querySelectorAll("[data-nav-item]") ].filter(item => !item.closest("[hidden]"))
    if (items.length === 0) return
    const index = items.indexOf(document.activeElement.closest("[data-nav-item]"))
    const next = items[Math.min(Math.max(index + step, 0), items.length - 1)]
    next.focus()
    next.scrollIntoView({ block: "nearest" })
  }
}
