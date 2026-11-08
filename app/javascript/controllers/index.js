// Import and register all your controllers from the importmap via controllers/**/*_controller,
// and rune_ui's (rune-*: the sidebar, menus, popovers, dialogs, flash…), with busy buttons on
// form submit.
import { application } from "controllers/application"
import { eagerLoadControllersFrom } from "@hotwired/stimulus-loading"
import { registerRuneUi } from "rune_ui"

registerRuneUi(application)
eagerLoadControllersFrom("controllers", application)
