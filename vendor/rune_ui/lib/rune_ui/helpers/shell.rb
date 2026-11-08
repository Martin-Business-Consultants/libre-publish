module RuneUi
  module Helpers
    # The app's frame: a sidebar on the page, the content in an inset panel with a bar (its
    # trail of crumbs and context) on top, flash messages, and the ⌘K palette.
    #
    #   <%= tag.html data: theme_data(Current.user&.theme) do %>
    #     <head> … <%= rune_ui_stylesheet_tags %> <%= stylesheet_link_tag :app %> …</head>
    #     <body><%= app_shell(sidebar: render("layouts/sidebar"), main: yield) %>
    #           <%= palette(items) %></body>
    module Shell
      def rune_ui_stylesheet_tags(lexxy: defined?(::Lexxy), fonts: true)
        sheets = RuneUi::STYLESHEETS.map { "rune_ui/#{it}" } + (lexxy ? [ "rune_ui/lexxy" ] : [])
        safe_join([ (rune_ui_font_tags if fonts), stylesheet_link_tag(*sheets, "data-turbo-track": "reload") ].compact, "\n")
      end

      # Inter and IBM Plex Mono, the faces the tokens name.
      def rune_ui_font_tags
        safe_join([
          tag.link(rel: "preconnect", href: "https://fonts.googleapis.com"),
          tag.link(rel: "preconnect", href: "https://fonts.gstatic.com", crossorigin: ""),
          tag.link(rel: "stylesheet", href: "https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@400;500&family=Inter:wght@400..700&display=swap")
        ], "\n")
      end

      # data-theme for <html>: "light" or "dark" pins it; nil or "system" follows the device.
      def theme_data(theme)
        theme.present? && theme.to_s != "system" ? { theme: theme } : {}
      end

      # sidebar: its HTML (a nav.sidebar). main: the page. storage_key: where the collapsed
      # state is remembered (put sidebar_preload_tag(storage_key) in <head>).
      #
      # For an app with more going on: bar: the panel bar's content after the toggle (instead of
      # the crumbs and :context); toggle: its own toggle button; flash: its own flash markup;
      # shortcuts: false leaves out rune-shortcuts (an app with its own keys); attributes: merged
      # onto the shell (id, data: { controller: "…" } adds controllers); main_attributes: onto
      # <main> (id, data); main_class: an extra class there ("main--wide"); after: HTML after
      # the shell (trays, dialogs).
      def app_shell(sidebar:, main:, storage_key: "rune.sidebar", bar: nil, toggle: nil, flash: nil, shortcuts: true,
                    attributes: {}, main_attributes: {}, main_class: nil, after: nil)
        attributes = attributes.deep_dup
        data = attributes.delete(:data) || {}
        controllers = [ "rune-sidebar", ("rune-shortcuts" if shortcuts), data.delete(:controller) ].compact.join(" ")
        actions = [ ("keydown@document->rune-shortcuts#handle" if shortcuts), data.delete(:action) ].compact.join(" ").presence
        app_attributes = attributes.merge(data: data.merge(controller: controllers, action: actions, rune_sidebar_key_value: storage_key).compact)

        bar ||= safe_join([
          tag.nav(content_for?(:crumbs) ? content_for(:crumbs) : tag.span(content_for(:title), class: "crumbs__current"), class: "crumbs", aria: { label: "You are here" }),
          tag.div(content_for(:context), class: "panel-bar__context")
        ])
        panel = tag.div(class: "panel") do
          safe_join([
            tag.header(safe_join([ toggle || sidebar_toggle(class: "panel-bar__toggle"), bar ]), class: "panel-bar"),
            tag.main(safe_join([ flash || flash_messages, main ]), **main_attributes, class: [ "main", main_class ].compact)
          ])
        end
        shell = tag.div(safe_join([ sidebar, tag.div(class: "sidebar-scrim", data: { action: "click->rune-sidebar#close" }), panel ]),
          **app_attributes, class: "app")
        safe_join([ shell, after ].compact)
      end

      # Sets data-sidenav="collapsed" on <html> before the first paint, from rune-sidebar's
      # stored choice, so a collapsed sidebar doesn't flash open on each page.
      def sidebar_preload_tag(storage_key = "rune.sidebar")
        javascript_tag(nonce: true) do
          %(try{if(localStorage.getItem(#{storage_key.to_json})==="collapsed")document.documentElement.dataset.sidenav="collapsed"}catch(e){}).html_safe
        end
      end

      # The bare frame for signed-out pages (sign in): a narrow column.
      def narrow_shell(main:)
        tag.main(safe_join([ flash_messages, main ]), class: "main main--narrow")
      end

      # Whether the page's title shows in the panel bar (as the last crumb) rather than as an
      # h1 in the page. Apps whose signed-out pages have no shell override it:
      #   def page_title_in_bar? = authenticated?
      def page_title_in_bar? = true

      def sidebar_brand(name, url, logo: name.to_s.first)
        tag.div(class: "sidebar__top") do
          link_to(url, class: "sidebar__brand") { tag.span(logo, class: "sidebar__logo", aria: { hidden: true }) + " " + name } +
            sidebar_toggle(label: "Hide the sidebar (⇧⌘B)")
        end
      end

      def sidebar_toggle(label: "Show the sidebar (⇧⌘B)", **options)
        icon_button(:sidebar, label: label, data: { action: "rune-sidebar#toggle" }, **options)
      end

      # Search in the sidebar: opens the palette.
      def sidebar_search(label = "Search")
        tag.button(type: "button", class: "sidebar__link", data: { action: "rune-shortcuts#palette" }) do
          safe_join([ icon(:search), tag.span(label, class: "sidebar__label"), tag.span("⌘K", class: "sidebar__kbd") ])
        end
      end

      # A link in the sidebar, current on its page and the pages under it. count: a pill.
      # current: true or false decides it instead (an app that works out which item is current
      # itself). Other options (title, data) go on the link.
      #
      # sub: the item's submenu, shown under it while it's current: hashes of label:, url: and
      # optionally current: and icon:. With one, the item is a div.sidebar__item, and its own
      # link is the current page only when none of the submenu's links is.
      #   sidebar_link "Pages", pages_path, icon: :document,
      #     sub: [ { label: "All pages", url: pages_path }, { label: "Add new", url: new_page_path } ]
      def sidebar_link(label, path, icon:, count: 0, exact: false, current: nil, sub: nil, **options)
        current = sidebar_current?(path, exact:) if current.nil?
        sub = Array(sub).map { { current: sidebar_current?(it[:url], exact: true) }.merge(it) }
        own_page = current && sub.none? { it[:current] }
        link = link_to path, **options, class: [ "sidebar__link", options[:class] ].compact, aria: { current: ("page" if own_page) } do
          safe_join([ icon(icon), tag.span(label, class: "sidebar__label"), count_pill(count) ].compact)
        end
        return link if sub.empty?

        links = sub.map do |item|
          tag.li do
            link_to item[:url], class: "sidebar__sub-link", aria: { current: ("page" if item[:current]) } do
              safe_join([ (icon(item[:icon], css: "icon--sm") if item[:icon]), tag.span(item[:label], class: "sidebar__label") ].compact)
            end
          end
        end
        tag.div safe_join([ link, tag.ul(safe_join(links), class: "sidebar__sub", aria: { label: label }) ]),
          class: [ "sidebar__item", ("sidebar__item--current" if current) ].compact
      end

      def sidebar_current?(path, exact: false)
        path = path.to_s
        request.path == path || (!exact && path != "/" && request.path.start_with?("#{path.chomp("/")}/"))
      end
      private :sidebar_current?

      def sidebar_section(label) = tag.div(label, class: "sidebar__section")

      # The flash as dismissible messages; notices go by themselves after a few seconds.
      # Notices and alerts. toast: true floats them in the bottom right as toasts, out of the page's
      # flow, so a message never pushes the page down (lift them with --toast-bottom, e.g. above
      # buttons in that corner). A notice goes by itself after six seconds; an alert stays.
      def flash_messages(toast: false)
        messages = { notice: flash[:notice], alert: flash[:alert] }.compact_blank
        return if messages.empty?

        tag.div(class: [ "flashes", ("flashes--toast" if toast) ].compact.join(" ")) do
          safe_join(messages.map do |kind, text|
            tag.div(class: "flash flash--#{kind}", role: (kind == :alert ? "alert" : "status"),
                    data: { controller: "rune-flash", rune_flash_timeout_value: (kind == :notice ? 6000 : 0) }) do
              tag.span(text) + icon_button(:close, label: "Dismiss", class: "flash__close", data: { action: "rune-flash#close" })
            end
          end)
        end
      end

      # ⌘K: everything the person can go to, filtered as they type. items: hashes of label:,
      # url:, and optionally sub:, kind:, icon: or letter: (a letter avatar), default: true
      # (shown before typing).
      def palette(items, placeholder: "Search…")
        search = tag.div(class: "palette__search") do
          safe_join([ icon(:search),
                      tag.input(type: "text", placeholder: placeholder, autocomplete: "off", spellcheck: "false", aria: { label: "Search" },
                                data: { rune_palette_target: "input", action: "input->rune-palette#filter keydown->rune-palette#key" }),
                      tag.kbd("esc") ])
        end
        rows = items.map do |item|
          link_to item[:url], class: "palette__item", role: "option",
                  data: { rune_palette_target: "item", search: [ item[:label], item[:sub], item[:kind] ].compact.join(" ").downcase,
                          default: (item[:default] == true).to_s, action: "click->rune-palette#choose mouseenter->rune-palette#hover" } do
            safe_join([ (item[:letter] ? letter_avatar(item[:letter]) : icon(item[:icon] || :chevron)),
                        tag.span(item[:label], class: "palette__label"), tag.span(item[:sub], class: "palette__sub"),
                        tag.span(item[:kind], class: "palette__kind") ])
          end
        end
        list = tag.div(safe_join([ *rows, tag.p("Nothing matches.", class: "palette__empty", hidden: true, data: { rune_palette_target: "empty" }) ]),
          class: "palette__list", role: "listbox")
        tag.dialog tag.div(safe_join([ search, list ]), class: "palette__box"), class: "palette", aria: { label: "Search" },
          data: { controller: "rune-palette", action: "click->rune-palette#backdrop" }
      end
    end
  end
end
