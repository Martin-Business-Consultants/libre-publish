import { Controller } from "@hotwired/stimulus"

// The editor's Preview tab: the page as the website draws it, with what's in
// the form now, saved or not. Each time the tab opens, the form is posted to
// its own address with ?website_preview, into the frame (or, from "Open in
// a new tab", a new tab); the controller renders it through the theme
// without saving (ContentEditing#render_website_preview).
export default class extends Controller {
  static targets = [ "frame" ]
  static values = { form: String }

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
