import { Controller } from "@hotwired/stimulus"

// The editor's Preview tab: the page as the website draws it, with what's in
// the form now, saved or not. Each time the tab opens, the form is posted to
// its own address with ?website_preview, into the frame (or, from "Open in
// a new tab", a new tab); the controller renders it through the theme
// without saving (ContentEditing#render_website_preview).
export default class extends Controller {
  static targets = [ "frame", "save" ]
  static values = { form: String }

  connect() {
    this.receive = this.receive.bind(this)
    window.addEventListener("message", this.receive)
  }

  disconnect() {
    window.removeEventListener("message", this.receive)
  }

  // An edit from the preview: "title", or "blocks.<row>.<field>" for a
  // field of the form's nth block row.
  receive(event) {
    if (event.origin !== window.location.origin || event.data?.type !== "lp-inline-edit") return
    if (event.source !== this.frameTarget.contentWindow) return

    const input = this.#input(event.data.field)
    if (!input) return
    input.value = event.data.value
    input.dispatchEvent(new Event("input", { bubbles: true }))
    if (this.hasSaveTarget) this.saveTarget.disabled = false
  }

  save() {
    document.getElementById(this.formValue)?.requestSubmit()
  }

  shown(event) {
    if (event.detail.name === "preview") this.refresh()
  }

  refresh() {
    this.#post(this.frameTarget.name)
  }

  openTab(event) {
    event.preventDefault()
    this.#post("_blank")
  }

  #input(field) {
    const form = document.getElementById(this.formValue)
    if (!form) return null
    const scope = this.formValue.replace(/_form$/, "")
    if (field === "title") return form.elements[`${scope}[title]`]

    const [, row, name] = field.match(/^blocks\.(\d+)\.(\w+)$/) || []
    if (row === undefined) return null
    const top = new RegExp(`^${scope}\\[blocks\\]\\[[^\\]]+\\]$`)
    const rows = [...form.querySelectorAll("li[data-row-scope]")].filter(li => top.test(li.dataset.rowScope))
    const scopeName = rows[Number(row)]?.dataset.rowScope
    return scopeName ? form.elements[`${scopeName}[data][${name}]`] : null
  }

  #post(target) {
    const form = document.getElementById(this.formValue)
    if (!form) return

    const url = new URL(form.action, window.location.href)
    url.searchParams.set("website_preview", "1")
    const button = document.createElement("button")
    button.type = "submit"
    button.hidden = true
    button.formAction = url.toString()
    button.formTarget = target
    button.formNoValidate = true
    button.dataset.turbo = "false"
    form.append(button)
    form.requestSubmit(button)
    button.remove()
  }
}
