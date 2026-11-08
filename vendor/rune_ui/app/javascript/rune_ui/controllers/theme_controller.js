import { Controller } from "@hotwired/stimulus"

// rune-theme: switches light / dark / system at once (data-theme on <html>). The form or menu
// button that carries the choice saves it. Use: data-action="rune-theme#preview" with
// data-rune-theme-theme-param="dark", or on a radio/select whose value is the theme.
export default class extends Controller {
  preview(event) {
    const theme = event.params.theme || event.target.value
    if (theme === "system") delete document.documentElement.dataset.theme
    else document.documentElement.dataset.theme = theme
  }
}
