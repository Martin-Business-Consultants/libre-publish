import { Controller } from "@hotwired/stimulus"

// The editor's Preview tab: the page as the website draws it, with what's in
// the form now, saved or not. Each time the tab opens, the form is posted to
// its own address with ?website_preview, into the frame (or, from "Open in
// a new tab", a new tab); the controller renders it through the theme
// without saving (ContentEditing#render_website_preview).

// A save from the preview, waiting for the page it comes back to: the
// editor is drawn anew (the controller with it), so this outlives it.
let justSaved = false

export default class extends Controller {
  static targets = [ "frame", "save" ]
  static values = { form: String }

  connect() {
    this.receive = this.receive.bind(this)
    this.submitted = this.submitted.bind(this)
    this.picked = this.picked.bind(this)
    this.loaded = this.loaded.bind(this)
    // Fields changed here since the last save: a preview drawn again (after an
    // image changes) is told, so its Save still counts them.
    this.pending = new Set()
    window.addEventListener("message", this.receive)
    window.addEventListener("asset-picker:picked", this.picked)
    this.frameTarget.addEventListener("load", this.loaded)
    document.addEventListener("turbo:submit-end", this.submitted)
    // Opened on #preview: the tab was shown before this was here to hear it.
    if (!this.frameTarget.closest("[hidden]")) this.refresh()
  }

  disconnect() {
    window.removeEventListener("message", this.receive)
    window.removeEventListener("asset-picker:picked", this.picked)
    this.frameTarget.removeEventListener("load", this.loaded)
    document.removeEventListener("turbo:submit-end", this.submitted)
  }

  // A save started from the preview, finished. The page comes back on its
  // Edit tab, so the Preview tab opens again, drawn with what was saved, to
  // keep editing; one that didn't save says so, and the Edit tab shows why.
  submitted(event) {
    if (!this.saving || event.target.id !== this.formValue) return
    this.saving = false

    if (event.detail.success) {
      this.pending.clear()
      justSaved = true
      const reopen = () => document.querySelector("[data-controller~=website-preview] a[data-tab=preview]")?.click()
      document.addEventListener("turbo:render", reopen, { once: true })
      setTimeout(() => { if (justSaved) reopen() }, 1500)
    } else {
      this.frameTarget.contentWindow?.postMessage({ type: "lp-inline-save-failed" }, window.location.origin)
      this.element.querySelector("a[data-tab=edit]")?.click()
    }
  }

  // An edit from the preview: "title", or "blocks.<row>.<field>" for a
  // field of the form's nth block row.
  receive(event) {
    if (event.origin !== window.location.origin || event.source !== this.frameTarget.contentWindow) return
    if (event.data?.type === "lp-inline-save") return this.save()
    if (event.data?.type === "lp-image") return this.#image(event.data.action, event.data.field)
    if (event.data?.type !== "lp-inline-edit") return

    const input = this.#input(event.data.field)
    if (!input) return
    input.value = event.data.value
    input.dispatchEvent(new Event("input", { bubbles: true }))
    this.#changed(event.data.field)
  }

  // An image's Replace (the media picker the field opens) or Crop & edit
  // (the image editor, which saves a copy). Either answers with the field's
  // asset-picker:picked, as the picker does.
  #image(action, field) {
    const input = this.#input(field)
    const assetField = input?.closest("[data-controller~='asset-field']")
    if (!assetField) return
    this.awaiting = { field, id: assetField.dataset.assetFieldIdValue }

    if (action === "edit" && input.value) {
      window.dispatchEvent(new CustomEvent("image-editor:open", { detail: { assetId: input.value, field: this.awaiting.id } }))
    } else {
      assetField.querySelector("[data-action~='asset-field#choose']")?.click()
    }
  }

  // The image chosen or edited is in the field (asset-field set it): the
  // preview draws it.
  picked(event) {
    if (!this.awaiting || event.detail.field !== this.awaiting.id) return
    const { field } = this.awaiting
    this.awaiting = null
    setTimeout(() => {
      this.#changed(field)
      this.refresh()
    })
  }

  loaded() {
    if (this.pending.size) {
      this.frameTarget.contentWindow?.postMessage({ type: "lp-inline-pending", fields: [ ...this.pending ] }, window.location.origin)
    }
  }

  #changed(field) {
    this.pending.add(field)
    if (this.hasSaveTarget) this.saveTarget.disabled = false
  }

  save() {
    const form = document.getElementById(this.formValue)
    if (!form) return
    // A field the form holds in another tab that isn't filled in as it
    // should be stops the save before it starts: show it.
    if (!form.checkValidity()) {
      this.frameTarget.contentWindow?.postMessage({ type: "lp-inline-save-failed" }, window.location.origin)
      this.element.querySelector("a[data-tab=edit]")?.click()
      form.reportValidity()
      return
    }
    this.saving = true
    form.requestSubmit()
  }

  refresh() {
    const saved = justSaved
    justSaved = false
    this.#post(this.frameTarget.name, saved)
  }

  shown(event) {
    if (event.detail.name === "preview") this.refresh()
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

  #post(target, saved = false) {
    const form = document.getElementById(this.formValue)
    if (!form) return

    const url = new URL(form.action, window.location.href)
    url.searchParams.set("website_preview", "1")
    if (saved) url.searchParams.set("saved", "1")
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
