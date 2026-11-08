module RuneUi
  module Helpers
    # The UI's building blocks. Pages say what they show ("a card titled Tools with a Refresh
    # button", "a row for this run"); the markup, classes and spacing live here, once. Every
    # button comes from #button_link, #action_button, #submit_button or #icon_button, so sizes
    # and variants stay consistent.
    #
    # The markup is built in Ruby, not partials, so it comes out the same whatever compiles the
    # app's templates (ReActionView's Herb rewrites tag helpers in templates it compiles). An app
    # overrides a component by defining a helper of the same name.
    #
    # Sizes: :md for page and form actions, :sm inside cards, rows and bars.
    # Variants: :primary (the one main action), :secondary, :ghost (quiet), :danger.
    module Components
      BUTTON_VARIANTS = %i[primary secondary ghost danger].freeze

      # The classes, as one string: link_to(…, class: button_classes(variant: :primary)), or in an
      # attribute: class="<%= button_classes %>". (A string, since Herb-compiled templates print
      # an array as its inspect.)
      def button_classes(variant: :secondary, size: :md, extra: nil)
        raise ArgumentError, "unknown button variant #{variant}" unless BUTTON_VARIANTS.include?(variant)

        [ "btn", "btn--#{variant}", ("btn--sm" if size == :sm), extra ].compact.join(" ")
      end

      # A link that looks like a button. icon: before the label; arrow: true, a chevron after
      # it ("see all").
      def button_link(label, url, variant: :secondary, size: :md, icon: nil, arrow: false, **options)
        link_to url, class: button_classes(variant:, size:, extra: options.delete(:class)), **options do
          safe_join([ (icon(icon) if icon), label, (icon(:chevron) if arrow) ].compact, " ")
        end
      end

      # "All 12 ›" at the top of a section that shows only its first few.
      def see_all_link(count, url, shown:)
        button_link("All #{count}", url, variant: :ghost, size: :sm, arrow: true) if count > shown
      end

      # A button that sends a request (button_to), with an optional confirmation.
      def action_button(label, url, method: :post, variant: :secondary, size: :md, confirm: nil, params: {}, **options)
        form = { data: { turbo_confirm: confirm }.compact }
        form[:data][:turbo] = false if options.delete(:turbo) == false
        button_to label, url, method:, params:, class: button_classes(variant:, size:, extra: options.delete(:class)), form:, **options
      end

      # A form's button. It shows it's working while the form is sent (rune_ui/index.js).
      def submit_button(form, label = nil, variant: :primary, size: :md, **options)
        form.button label, type: "submit", class: button_classes(variant:, size:, extra: options.delete(:class)), **options
      end

      # A square button with only an icon; label is what screen readers and the tooltip say.
      def icon_button(name, label:, url: nil, **options)
        classes = [ "icon-button", options.delete(:class) ].compact
        content = icon(name)
        if url
          link_to content, url, class: classes, title: label, aria: { label: label }, **options
        else
          tag.button content, type: "button", class: classes, title: label, aria: { label: label }, **options
        end
      end

      # An icon-only button that sends a request (button_to): sign out, say.
      def icon_action_button(name, url, label:, method: :post, danger: false, confirm: nil)
        button_to url, method:, class: [ "icon-button", ("icon-button--danger" if danger) ], title: label, aria: { label: label },
          form: { data: { turbo_confirm: confirm }.compact } do
          icon(name)
        end
      end

      def button_row(&buttons)
        tag.div capture(&buttons), class: "button-row"
      end

      # The page's title (in the panel bar, after its trail) and, in the page, what it's for
      # and its actions (the block). subtitle: text, or an array shown as a dotted list.
      def page_header(title, subtitle = nil, trail: [], &actions)
        crumbs(*trail, title)
        subtitle = tag.div(safe_join(subtitle.compact_blank.map { tag.span(it) }), class: "dot-list") if subtitle.is_a?(Array)
        actions = capture(&actions) if actions
        text = safe_join([ (tag.h1(title, class: "page-header__title") unless page_title_in_bar?),
                           (tag.div(subtitle, class: "page-header__subtitle") if subtitle.present?) ].compact)
        tag.header(safe_join([ tag.div(text, class: "page-header__text"), (tag.div(actions, class: "button-row") if actions.present?) ].compact),
          class: "page-header")
      end

      # A section. actions: buttons beside its title. flush: its content (a list or table) runs
      # to the edges. hint: a line under the title. Other options go on the <section>.
      def card(title = nil, actions: nil, hint: nil, css: nil, flush: false, **options, &body)
        head = if title.present? || actions.present? || hint.present?
          header = if title.present? || actions.present?
            tag.div(safe_join([ (tag.h2(title, class: "card__title") if title.present?),
                                (tag.div(actions, class: "button-row") if actions.present?) ].compact), class: "card__header")
          end
          tag.div(safe_join([ header, (tag.p(hint, class: "card__hint") if hint.present?) ].compact), class: "card__head")
        end
        classes = [ "card", css.presence, ("card--flush" if flush), options.delete(:class) ].compact
        tag.section safe_join([ head, capture(&body) ].compact), **options, class: classes
      end

      # One row of a list: avatar · title · muted detail · meta. j/k move between rows.
      def list_row(url, title:, sub: nil, meta: nil, avatar: nil, id: nil)
        content = safe_join([ avatar, tag.span(title, class: "list-row__title"), tag.span(sub, class: "list-row__sub"),
                              (tag.span(meta, class: "list-row__meta") if meta.present?) ].compact)
        if url
          link_to content, url, class: "list-row", id: id, data: { nav_item: true }
        else
          tag.div content, class: "list-row list-row--static", id: id
        end
      end

      # Items grouped by day: Today, Yesterday, Earlier this week, Older.
      def day_groups(items, &time)
        today = Time.zone.today
        items.group_by do |item|
          date = time.call(item).to_date
          if date == today then "Today"
          elsif date == today - 1 then "Yesterday"
          elsif date > today - 7 then "Earlier this week"
          else "Older"
          end
        end
      end

      # A labelled form field; the input is the block, or a rich text field for `rich: true`.
      def field(form, method, label: nil, hint: nil, rich: false, placeholder: nil, &input)
        input_html = rich ? rich_text_field(form, method, placeholder: placeholder) : capture(&input)
        tag.div safe_join([ form.label(method, label), input_html, (tag.p(hint, class: "field__hint") if hint.present?) ].compact), class: "field"
      end

      def form_errors(record)
        return unless record&.errors&.any?

        tag.div record.errors.full_messages.to_sentence, class: "flash flash--alert", role: "alert"
      end

      # Nothing to show. compact: inside a card, without the dashed box.
      def empty_state(text, compact: false, &action)
        action = capture(&action) if action
        tag.div safe_join([ tag.p(text), (tag.div(action, class: "button-row") if action.present?) ].compact),
          class: [ "empty", ("empty--compact" if compact) ].compact
      end

      # Secondary actions behind one button: fill it with #menu_link, #menu_button,
      # #menu_label and #menu_divider. up: opens above it. trigger_class: the button's look
      # instead of a regular button (label can then be any HTML, like an icon and a name).
      # (The <summary> must be <details>' own first child.)
      def menu(label = "More", up: false, trigger_class: nil, &items)
        summary = tag.summary(safe_join([ label, (safe_join([ " ", icon(:chevron, css: "icon--down") ]) unless trigger_class) ].compact),
          class: trigger_class || button_classes)
        tag.details safe_join([ summary, tag.div(capture(&items), class: "menu__items", role: "menu", data: { action: "click->rune-menu#close" }) ]),
          class: [ "menu", ("menu--up" if up) ].compact, data: { controller: "rune-menu" }
      end

      def menu_link(label, url, **options)
        link_to label, url, class: [ "menu__item", options.delete(:class) ].compact, **options
      end

      def menu_button(label, url, method: :post, danger: false, confirm: nil, icon: nil, params: {}, checked: nil, data: {})
        button_to url, method:, params:, class: [ "menu__item", ("menu__item--danger" if danger) ], role: (checked.nil? ? nil : "menuitemradio"),
          aria: { checked: checked }, data: data, form: { data: { turbo_confirm: confirm }.compact } do
          safe_join([ (icon(icon) if icon), label ].compact)
        end
      end

      def menu_label(text) = tag.div(text, class: "menu__label")
      def menu_divider = tag.div(class: "menu__divider", role: "separator")

      # A search box with its icon. data: wiring for rune-list-filter or rune-autosubmit.
      def search_input(name: nil, value: nil, placeholder: "Search", data: {})
        tag.label(class: "search") do
          icon(:search) + tag.input(type: "search", name: name, value: value, placeholder: placeholder, autocomplete: "off",
                                    aria: { label: placeholder }, data: data)
        end
      end

      # Search and dropdowns that filter a list, sent (GET) as you type or choose:
      #   filter_bar runs_path, search: { name: :q, value: @query, placeholder: "Search runs" },
      #     status: { label: "Status", options: [["Failed", "failed"]], selected: @status }
      # A GET form drops its action's query string, so what the url carries (?scope=mine) goes
      # along as hidden fields.
      def filter_bar(url, search: nil, **filters)
        form_with url: url, method: :get, class: "filter-bar", data: { controller: "rune-autosubmit", turbo_action: "replace" } do |form|
          carried = Rack::Utils.parse_query(URI(url).query.to_s).map { |key, value| hidden_field_tag(key, value, id: nil) }
          box = (search_input(name: search[:name], value: search[:value], placeholder: search[:placeholder], data: { action: "input->rune-autosubmit#later" }) if search)
          selects = filters.map do |name, filter|
            form.select name, options_for_select(filter[:options], filter[:selected]),
              { include_blank: filter.fetch(:blank, "Any #{filter[:label].downcase}") },
              aria: { label: filter[:label] }, data: { action: "rune-autosubmit#submit" }
          end
          clear = (button_link("Clear", url, variant: :ghost) if ([ search&.dig(:name) ] + filters.keys).compact.any? { params[it].present? })
          safe_join([ *carried, box, *selects, clear ].compact)
        end
      end

      # Copies text to the clipboard; says "Copied" for a moment.
      def copy_button(text, label: "Copy", icon_only: false)
        tag.span(class: "copy", data: { controller: "rune-clipboard", rune_clipboard_text_value: text }) do
          wiring = { rune_clipboard_target: "button", action: "rune-clipboard#copy" }
          if icon_only
            icon_button(:copy, label: label, data: wiring)
          else
            tag.button(label, type: "button", class: button_classes(size: :sm), data: wiring)
          end
        end
      end

      # A value people paste elsewhere (an address), with a Copy button.
      def copy_field(value)
        tag.div(class: "copy-field") { tag.code(value, title: value) + copy_button(value) }
      end

      # Settings as Rune lays them out: a heading above a card of rows, each a label (and hint)
      # on the left and its control on the right.
      def settings_group(title, hint: nil, &rows)
        tag.section safe_join([ tag.h2(title, class: "settings-group__title"), (tag.p(hint, class: "settings-group__hint") if hint.present?),
                                tag.div(capture(&rows), class: "settings-group__card") ].compact), class: "settings-group"
      end

      def setting_row(label, hint: nil, for_id: nil, &control)
        label_html = for_id ? label_tag(for_id, label, class: "setting-row__label") : tag.span(label, class: "setting-row__label")
        text = tag.div(safe_join([ label_html, (tag.span(hint, class: "setting-row__hint") if hint.present?) ].compact), class: "setting-row__text")
        tag.div safe_join([ text, tag.div(capture(&control), class: "setting-row__control") ]), class: "setting-row"
      end

      # A checkbox drawn as a switch.
      def switch(form, method, **options)
        tag.span(class: "switch") { form.check_box(method, role: "switch", **options) + tag.span(class: "switch__track", aria: { hidden: true }) }
      end

      # One of a few options as a segmented control (radio buttons):
      #   segmented(form, :theme, [["Light", "light", :light], ["Dark", "dark", :dark]])
      def segmented(form, method, choices, **input_options)
        tag.div(class: "segmented", role: "radiogroup") do
          safe_join(choices.map do |label, value, icon_name|
            tag.label(class: "segmented__option") do
              form.radio_button(method, value, **input_options) + tag.span(safe_join([ (icon(icon_name) if icon_name), label ].compact))
            end
          end)
        end
      end

      # The message box: a rich text field without toolbar, what it's sent to on the left (the
      # block), and the send button. ⌘↵ sends.
      def composer(form, method, placeholder:, mentions: nil, send_label: "Send", hint: nil, &context)
        context = capture(&context) if context
        send = tag.button(icon(:send), type: "submit", class: "send-button", aria: { label: "#{send_label} (⌘↵)" }, title: "#{send_label} (⌘↵)")
        bar = tag.div(safe_join([ tag.div(context, class: "composer__context"), tag.span(hint || "⌘↵ to send", class: "composer__hint"), send ]),
          class: "composer__bar")
        tag.div safe_join([ rich_text_field(form, method, placeholder: placeholder, toolbar: false, mentions: mentions), bar ]), class: "composer__box"
      end
    end
  end
end
