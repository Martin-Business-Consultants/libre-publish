pin "rune_ui", to: "rune_ui/index.js"
pin_all_from RuneUi::Engine.root.join("app/javascript/rune_ui/controllers"), under: "rune_ui/controllers", to: "rune_ui/controllers"
