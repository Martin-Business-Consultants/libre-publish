# frozen_string_literal: true

# The class lists for the admin's repeated pieces (buttons, panels, menus,
# badges, notices, tables, form text), in one place so every screen draws
# them alike, after Payload's admin: neutral, flat and compact. They draw
# only with the tokens Settings › Branding sets (_global.css): blue is the
# accent (the primary color; black until one's set), gray the neutral,
# rounded-* the corners, shadow-surface/-overlay the shadow. A view writes `class: ui(:button, :primary)`, adding its own layout
# classes as a string: `ui(:button, :small, "w-full")`.
#
# Each recipe has a base and groups of variants. One variant from each group
# applies, the first unless the call names another, so a recipe never puts
# two classes that set the same property on one element.
module UiHelper
  UI_RECIPES = {
    button: {
      base: "inline-flex items-center justify-center gap-1.5 rounded-md font-medium whitespace-nowrap",
      tone: {
        secondary: "border border-gray-300 bg-white text-gray-900 hover:border-gray-400 hover:bg-gray-50",
        primary: "border border-blue-600 bg-blue-600 text-on-accent hover:bg-blue-700",
        danger: "border border-gray-300 bg-white text-red-600 hover:bg-red-50",
        destructive: "border border-red-600 bg-red-600 text-white hover:bg-red-700",
        plain: "border border-transparent text-gray-600 hover:bg-gray-100 hover:text-gray-900"
      },
      size: {
        regular: "h-8 px-3 text-sm",
        small: "h-7 px-2.5 text-xs",
        icon: "size-8 text-sm"
      }
    },
    panel: {
      base: "rounded-xl border border-gray-200 bg-white shadow-surface"
    },
    dialog: {
      base: "gap-4 rounded-xl border border-gray-200 bg-white p-6 text-left text-gray-900 shadow-overlay"
    },
    sheet: {
      base: "dialog dialog--sheet gap-6 overflow-y-auto rounded-l-xl border-l border-gray-200 bg-white p-6 text-left text-gray-900 shadow-overlay"
    },
    menu: {
      base: "rounded-xl border border-gray-200 bg-white p-1 shadow-overlay"
    },
    menu_item: {
      base: "flex w-full items-center gap-2 rounded-md px-2.5 py-1.5 text-left text-sm text-gray-700 hover:bg-gray-100 hover:text-gray-900"
    },
    badge: {
      base: "inline-flex items-center gap-1 rounded-sm px-1.5 py-0.5 text-xs font-medium whitespace-nowrap",
      tone: {
        gray: "bg-gray-100 text-gray-700",
        blue: "bg-blue-50 text-blue-700",
        green: "bg-green-50 text-green-700",
        yellow: "bg-yellow-50 text-yellow-800",
        red: "bg-red-50 text-red-700"
      }
    },
    notice: {
      base: "flex items-start gap-3 rounded-lg border px-4 py-3 text-sm",
      tone: {
        blue: "border-blue-200 bg-blue-50 text-blue-800",
        green: "border-green-200 bg-green-50 text-green-800",
        yellow: "border-yellow-200 bg-yellow-50 text-yellow-800",
        red: "border-red-200 bg-red-50 text-red-800"
      }
    },
    page_title: {
      base: "text-3xl font-semibold tracking-tight text-gray-900"
    },
    heading: {
      base: "text-base font-semibold text-gray-900"
    },
    label: {
      base: "block text-sm font-medium text-gray-900"
    },
    help: {
      base: "text-xs text-gray-500"
    },
    link: {
      base: "font-medium text-blue-600 underline underline-offset-2 hover:text-blue-700"
    },
    table: {
      base: "w-full text-left text-sm"
    },
    th: {
      base: "border-b border-gray-200 px-3 py-2 text-xs font-medium text-gray-500"
    },
    td: {
      base: "border-b border-gray-100 px-3 py-2.5 align-middle text-gray-700"
    }
  }.freeze

  def ui(component, *options)
    recipe = UI_RECIPES.fetch(component)
    extra = options.grep(String)
    names = options.grep(Symbol)

    variants = recipe.except(:base).map do |_group, choices|
      choices.fetch(names.find { choices.key?(it) } || choices.keys.first)
    end

    unknown = names.reject { |name| recipe.except(:base).values.any? { it.key?(name) } }
    raise ArgumentError, "#{component} has no variant #{unknown.join(", ")}" if unknown.any?

    [recipe[:base], *variants, *extra].join(" ")
  end
end
