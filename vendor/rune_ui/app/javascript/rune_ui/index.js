// rune_ui's Stimulus controllers, registered as rune-*, and the busy state of buttons that
// send forms. In an app's controllers/index.js:
//
//   import { application } from "controllers/application"
//   import { registerRuneUi } from "rune_ui"
//   registerRuneUi(application)
import Autosubmit from "rune_ui/controllers/autosubmit_controller"
import Clipboard from "rune_ui/controllers/clipboard_controller"
import Dialog from "rune_ui/controllers/dialog_controller"
import Flash from "rune_ui/controllers/flash_controller"
import ListFilter from "rune_ui/controllers/list_filter_controller"
import LocalTime from "rune_ui/controllers/local_time_controller"
import Menu from "rune_ui/controllers/menu_controller"
import Palette from "rune_ui/controllers/palette_controller"
import Popover from "rune_ui/controllers/popover_controller"
import Proxy from "rune_ui/controllers/proxy_controller"
import Reveal from "rune_ui/controllers/reveal_controller"
import Rows from "rune_ui/controllers/rows_controller"
import Shortcuts from "rune_ui/controllers/shortcuts_controller"
import Sidebar from "rune_ui/controllers/sidebar_controller"
import Theme from "rune_ui/controllers/theme_controller"

export const controllers = {
  "rune-autosubmit": Autosubmit,
  "rune-clipboard": Clipboard,
  "rune-dialog": Dialog,
  "rune-flash": Flash,
  "rune-list-filter": ListFilter,
  "rune-local-time": LocalTime,
  "rune-menu": Menu,
  "rune-palette": Palette,
  "rune-popover": Popover,
  "rune-proxy": Proxy,
  "rune-reveal": Reveal,
  "rune-rows": Rows,
  "rune-shortcuts": Shortcuts,
  "rune-sidebar": Sidebar,
  "rune-theme": Theme
}

export function registerRuneUi(application, { busyButtons = true } = {}) {
  for (const [ name, controller ] of Object.entries(controllers)) application.register(name, controller)
  if (busyButtons) installBusyButtons()
}

// Whichever button sent a form shows it's working until the answer comes back, and can't be
// pressed twice (.btn[aria-busy] and .send-button[aria-busy] draw a spinner).
let installed = false
function installBusyButtons() {
  if (installed) return
  installed = true
  document.addEventListener("turbo:submit-start", ({ detail }) => {
    const button = detail.formSubmission.submitter
    if (button) { button.setAttribute("aria-busy", "true"); button.disabled = true }
  })
  document.addEventListener("turbo:submit-end", ({ detail }) => {
    const button = detail.formSubmission.submitter
    if (button) { button.removeAttribute("aria-busy"); button.disabled = false }
  })
}
