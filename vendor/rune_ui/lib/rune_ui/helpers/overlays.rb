module RuneUi
  module Helpers
    # Things that open over the page: popover menus, dialogs, sheets; and tabs, alerts,
    # avatars, which pages use alongside them.
    module Overlays
      # A person (or anything named) as a round picture, or their initials on a steady colour.
      # size: nil (18px), :md (24px), :lg (28px). title: the tooltip and what screen readers say.
      def avatar(name, url: nil, size: nil, title: name, **options)
        hue = name.to_s.bytes.sum % 8
        content = url.present? ? image_tag(url, alt: "", loading: "lazy") : initials(name)
        tag.span content, class: [ "avatar", "letter--#{hue}", ("avatar--#{size}" if size), options.delete(:class) ],
          title: title, role: "img", aria: { label: title }, **options
      end

      # Nobody: a dashed circle.
      def empty_avatar(title = "Nobody", size: nil)
        tag.span class: [ "avatar", "avatar--empty", ("avatar--#{size}" if size) ], title: title, role: "img", aria: { label: title }
      end

      # Overlapping avatars: avatar_stack { safe_join(people.map { avatar(it.name) }) }
      def avatar_stack(&avatars) = tag.span(capture(&avatars), class: "avatar-stack")

      def initials(name)
        words = name.to_s.strip.split(/\s+/)
        (words.size > 1 ? words.first(2).map { it[0] } : [ words.first.to_s[0, 2] ]).join.upcase
      end

      # A menu that opens in the top layer (the popover attribute), placed beside its trigger:
      # for menus in rows that scroll or clip, where #menu's <details> can't escape. side:
      # :bottom or :top; align: :start or :end. Fill it as #menu (menu_link, menu_button…).
      def popover_menu(label, id: nil, side: :bottom, align: :end, trigger_class: nil, title: nil, &items)
        id ||= "popover-#{SecureRandom.hex(4)}"
        trigger = tag.button(safe_join([ label, (safe_join([ " ", icon(:chevron, css: "icon--down") ]) unless trigger_class) ].compact),
          type: "button", class: trigger_class || button_classes, popovertarget: id, title: title,
          data: { rune_popover_target: "trigger" }, aria: { haspopup: "menu" })
        menu = tag.div(capture(&items), id: id, class: "popover menu__items", popover: "auto", role: "menu",
          data: { rune_popover_target: "popover", action: "click->rune-popover#chose keydown->rune-popover#key" })
        tag.div safe_join([ trigger, menu ]), class: "popover-menu",
          data: { controller: "rune-popover", rune_popover_side_value: side, rune_popover_align_value: align }
      end

      # A modal dialog and the button that opens it. trigger: the button's label (any HTML);
      # trigger_class: its look (a regular button by default). The block is the body; give it
      # actions with #dialog_actions. Esc, the × and a click outside close it.
      def dialog(title, trigger:, trigger_class: nil, id: nil, size: nil, &body)
        modal(title, trigger:, trigger_class:, id:, classes: [ "dialog", ("dialog--#{size}" if size) ], body: capture(&body))
      end

      # The same, sliding in from the right.
      def sheet(title, trigger:, trigger_class: nil, id: nil, &body)
        modal(title, trigger:, trigger_class:, id:, classes: %w[dialog sheet], body: capture(&body))
      end

      def modal(title, trigger:, trigger_class:, id:, classes:, body:)
        opener = tag.button(trigger, type: "button", class: trigger_class || button_classes, data: { action: "rune-dialog#open" }, aria: { haspopup: "dialog" })
        header = tag.header(safe_join([ tag.h2(title, class: "dialog__title"), icon_button(:close, label: "Close", data: { action: "rune-dialog#close" }) ]),
          class: "dialog__header")
        box = tag.div(safe_join([ header, tag.div(body, class: "dialog__body") ]), class: "dialog__box")
        element = tag.dialog(box, class: classes.compact, id: id, aria: { label: title },
          data: { rune_dialog_target: "dialog", action: "click->rune-dialog#backdrop" })
        tag.div safe_join([ opener, element ]), class: "dialog-wrap", data: { controller: "rune-dialog" }
      end
      private :modal

      def dialog_actions(&buttons)
        tag.div safe_join([ tag.button("Cancel", type: "button", class: button_classes(variant: :ghost), data: { action: "rune-dialog#close" }),
                            capture(&buttons) ]), class: "dialog__actions"
      end

      # "Delete this?" in a dialog, for any destructive action: the trigger, a sentence, and the
      # button that sends it.
      def confirm_dialog(trigger, url, title:, body: nil, button: "Delete", method: :delete, trigger_class: nil)
        dialog(title, trigger: trigger, trigger_class: trigger_class || button_classes(variant: :danger)) do
          safe_join([ (tag.p(body, class: "muted") if body),
                      dialog_actions { action_button(button, url, method: method, variant: :danger) } ].compact)
        end
      end

      # Tabs as links: tabs([["Work", work_path, current: true, count: 3], ["History", history_path]]).
      # Or as buttons that set state: pass a block and write the buttons yourself, with
      # aria-pressed.
      def tabs(items = nil, label: "Sections", &buttons)
        content = if buttons
          capture(&buttons)
        else
          safe_join(items.map do |text, url, options = {}|
            link_to url, class: "tabs__tab", aria: { current: ("page" if options[:current]) }, data: options[:data] do
              safe_join([ (icon(options[:icon]) if options[:icon]), text, (tag.span(options[:count], class: "count count--quiet") if options[:count]) ].compact)
            end
          end)
        end
        tag.nav content, class: "tabs", aria: { label: label }
      end

      # A message that stays on the page (not a flash): tone :info, :ok, :attention, :danger.
      # (Not `alert`: that's Rails' flash[:alert] helper.)
      def callout(text = nil, tone: :info, title: nil, &body)
        tag.div class: [ "alert", "alert--#{tone}" ], role: (tone == :danger ? "alert" : "status") do
          safe_join([ (tag.strong(title, class: "alert__title") if title), (body ? capture(&body) : tag.p(text)) ].compact)
        end
      end

      # A bar for how far along something is (0–100).
      def progress_bar(percent, label: nil)
        percent = percent.to_f.clamp(0, 100)
        tag.span class: "progress", role: "progressbar", aria: { valuenow: percent.round, valuemin: 0, valuemax: 100, label: label } do
          tag.span(class: "progress__bar", style: "width: #{percent}%")
        end
      end
    end
  end
end
