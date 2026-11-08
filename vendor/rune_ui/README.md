# rune_ui

A no-build UI kit for Rails apps on Hotwire, Propshaft and importmap, after Rune. It has:

- **Components as view helpers and partials:** buttons, menus, cards, list rows, fields, filter bars, settings rows, switches, segmented controls, a Lexxy composer, empty states and flash.
- **An app shell:** a sidebar on the page, the content in an inset panel with a crumb bar, a ⌘K palette and keyboard shortcuts.
- **Plain CSS, light and dark,** built on `light-dark()` tokens, all in the `rune` cascade layer.
- **Stimulus controllers,** registered as `rune-*` and served through importmap.

It was extracted from Botter and is used by Botter and Runwell.

## Install

```ruby
# Gemfile
gem "rune_ui", path: "../rune_ui"   # or github: "…/rune_ui"
```

The gem pins its JavaScript and puts its stylesheets on the asset path by itself. Three steps wire it in:

```erb
<%# layouts/application.html.erb %>
<%= tag.html data: theme_data(Current.user&.theme) do %>
  <head>
    …
    <%= rune_ui_stylesheet_tags %>               <%# fonts + rune_ui/*.css (+ Lexxy theming if Lexxy is loaded) %>
    <%= stylesheet_link_tag :app, "data-turbo-track": "reload" %>
    <%= javascript_importmap_tags %>
  </head>
  <body>
    <% if authenticated? %>
      <%= app_shell sidebar: render("layouts/sidebar"), main: yield %>
      <%= palette palette_items %>
    <% else %>
      <%= narrow_shell main: yield %>
    <% end %>
  </body>
<% end %>
```

```js
// controllers/index.js
import { application } from "controllers/application"
import { eagerLoadControllersFrom } from "@hotwired/stimulus-loading"
import { registerRuneUi } from "rune_ui"

registerRuneUi(application)            // rune-* controllers, and busy buttons on form submit
eagerLoadControllersFrom("controllers", application)
```

```ruby
# config/initializers/rune_ui.rb
Rails.application.config.to_prepare do
  RuneUi.register_icons(runs: '<circle cx="8" cy="8" r="5.5"/>')   # 16×16, stroked paths
  RuneUi.badge_tones.merge!("completed" => :ok, "failed" => :danger, "running" => :busy)
end
```

## Overriding

- **CSS.** Every rule is in a layer of `rune` (`rune.tokens`, `rune.base`, `rune.components`, `rune.utilities`), so the app's own unlayered CSS always wins, whatever its specificity. To restyle, set tokens on `:root`, for example `--accent`, `--panel`, `--font-sans`, `--sidebar-width` or `--main-width`. Sizes are rem, so `--text-scale` resizes everything. Corners go through `--radius-scale`, controls share `--radius-control`, and pills use `--radius-pill`. One exception: `rune_ui/lexxy.css` is unlayered, because it has to beat Lexxy's own CSS.
- **Helpers.** These are added to `ActionController::Base`'s helpers ahead of the app's own, so an app helper with the same name wins. Most often an app overrides `page_title_in_bar?`, for example as `authenticated?`.
- **No partials.** Every component's markup is built in Ruby, so it renders the same whatever compiles the app's templates. ReActionView's Herb, in slots mode, rewrites tag helpers in the templates it compiles: it drops `**splat` attributes and prints arrays as text. To change a component, define a helper of the same name in the app.

## Helpers

| Area | Helpers |
|---|---|
| Buttons | `button_link`, `action_button`, `submit_button`, `icon_button`, `icon_action_button`, `see_all_link`, `button_row`, `button_classes`. Variants: `:primary`, `:secondary`, `:ghost`, `:danger`. Sizes: `:md`, `:sm` |
| Menus | `menu(label, up:, trigger_class:) { menu_link / menu_button / menu_label / menu_divider }` |
| Page | `page_header(title, subtitle, trail:) { actions }`, `crumbs`, `card(title, actions:, hint:, flush:)`, `empty_state`, `settings_group`, `setting_row` |
| Lists | `list_row(url, title:, sub:, meta:, avatar:)`, `day_groups(items) { time }`. Rows are `data-nav-item`, so j/k moves between them |
| Forms | `field(form, :attr, label:, hint:, rich:)`, `form_errors`, `switch`, `segmented`, `search_input`, `filter_bar(url, search:, **selects)`, `copy_button`, `copy_field` |
| Rich text (Lexxy) | `rich_text_field`, `rich_text_field_tag`, `mention_prompt`, `rich_text`, `composer(form, :attr, placeholder:, mentions:, hint:) { context }` |
| Marks | `icon`, `letter_avatar`, `avatar(name, url:, size:)`, `empty_avatar`, `avatar_stack`, `badge(status, label, tone:)`, `status_dot(state)`, `count_pill`, `time_ago(time, short:)` |
| Overlays | `popover_menu(label, side:, align:) { menu items }` (top layer, for rows that scroll or clip), `dialog(title, trigger:) { … dialog_actions { … } }`, `sheet`, `confirm_dialog(trigger, url, title:, body:, button:)`, `data-tooltip="…"` |
| Data | `tabs([[label, url, current:, count:, icon:]], pills:)`, `callout(text, tone:, title:)`, `progress_bar(percent)`, and the classes `.table` (in `.table-wrap`; one column convention: the first column, or `.table__grow`, takes the leftover width and every other column fits its content; `.table__cap` truncates long text in a fitted column; `.table--even` opts out; a table with a `<colgroup>` sizes itself) and `.skeleton` |
| Shell | `app_shell`, `narrow_shell`, `sidebar_brand`, `sidebar_search`, `sidebar_link(label, path, icon:, count:, current:, sub:)` (sub: a submenu under the current item), `sidebar_section`, `sidebar_toggle`, `flash_messages(toast:)` (toast: true floats them bottom right; lift with `--toast-bottom`), `palette(items)`, `theme_data`, `rune_ui_stylesheet_tags` |

Utility classes: `stack`, `grid-2`, `catalog`, `dot-list`, `dl.details`, `muted`, `faint`, `small`, `nowrap`, `visually-hidden`. Card modifiers: `card--muted`, `card--attention`, `card--danger`, `card--fold`, `card--sm`. Card parts beyond the helper's: `card__content`, `card__action` (beside the title and hint), `card__head--bordered`, `card__footer--bordered`. List rows with more to them: `list-row__media`, `list-row__content` (holding `list-row__title` and `list-row__desc`), `list-row__actions`; modifiers `list-row--tall`, `list-row--outline`. Buttons: `btn--block`, `btn--accent`, and `pill` (a filter or picker's trigger: its choice and a chevron). Forms: `field-row` (fields side by side). Tabs: `tabs--icons`, `tabs--pills`. Alerts: `alert__icon`, `alert__body`. Rules: `separator`, `separator--label`. Tables: `a.row-link`. Folds: `fold`, `fold__summary`, `fold__chevron`, `fold__body`. Other classes: `chip`, `prose`, `composer-dock`.

## Stimulus controllers

| Controller | What it does |
|---|---|
| `rune-menu` | Closes a `<details>` menu on Escape, on a click outside, or once you pick an item |
| `rune-sidebar` | Collapses the sidebar (and remembers it, per `key` value), or opens it as a drawer on narrow screens |
| `rune-shortcuts` | ⌘K palette, ⌘↵ sends the form, ⇧⌘B toggles the sidebar, ⌘[ / ⌘] go to `data-shortcut="prev"`/`"next"`, j/k move through `[data-nav-item]` |
| `rune-palette` | The ⌘K dialog. Opens on the `rune-palette:open` window event |
| `rune-popover` | Places a `[popover]` menu beside its trigger, moves through items with the arrow keys, and closes once you pick one |
| `rune-dialog` | Opens its `<dialog>` as a modal; closes on ×, Cancel, Esc or a backdrop click |
| `rune-proxy` | `#click` clicks the element matching its `selector` param, so a menu item can act like a button elsewhere |
| `rune-theme` | Previews light, dark or system right away (`data-theme` on `<html>`) |
| `rune-autosubmit` | `#submit` sends the form on change; `#later` sends it after typing stops |
| `rune-list-filter` | Filters `item` targets by their `data-search` as you type |
| `rune-reveal` | Shows the panels whose `data-reveal-when` matches the select, and disables the fields in hidden ones |
| `rune-rows` | Repeating nested-form rows from a `<template>` (`NEW_ROW`) |
| `rune-clipboard` | Copies a value and shows "Copied" briefly |
| `rune-flash` | Dismiss button, and a timeout after which the message removes itself |
| `rune-local-time` | Keeps `time_ago` output current |

## Rules the kit keeps

- Containers space their children with `gap`, never sibling margins. ERB tooling such as ReActionView can wrap output in `display: contents` spans, and `gap` sees through them.
- There are two control heights, `--control-h` and `--control-h-sm`.
- No coloured edge stripes. States show as tints, weight, dots and badges.
