# frozen_string_literal: true

module ApplicationHelper
  LITEWIND_STYLESHEET = "litewind-2.0.1"

  def page_title_tag
    tag.title [@page_title, current_branding[:site_title].presence || "CMS"].compact.join(" | ")
  end

  # Herb compiles stylesheet_link_tag into a single <link>, which skips
  # Propshaft's :app expansion, so the layout calls this instead. Litewind
  # (vendor/assets, Tailwind's utilities with no build step) comes first: its
  # @layer statement sets the order the app's layers join (_global.css).
  #
  # A plugin's stylesheets load only where it shows something
  # (page_plugins), each in its own tag, which Turbo adds and drops as pages
  # change (data-turbo-track="dynamic"). One that can't be found (a plugin
  # installed after the image was built, whose assets haven't compiled yet)
  # is left out and reported: the page without that plugin's styles, rather
  # than a page that fails.
  def app_stylesheet_tags
    safe_join([
      stylesheet_link_tag(LITEWIND_STYLESHEET, "data-turbo-track": "reload"),
      stylesheet_link_tag(:app, "data-turbo-track": "reload"),
      *Cms::Plugins.enabled_stylesheets(page_plugins).filter_map { plugin_stylesheet_tag(it) }
    ], "\n")
  end

  # The plugins this page shows something of: the one whose page it is
  # (PluginGated's `plugin :key`, or the plugin whose engine holds the
  # controller, for one that isn't gated, as Media's file manager), those
  # whose slots it renders (plugin_slots, all rendered by the time the
  # layout's <head> is), and those in the admin bar, which is on every page.
  def page_plugins
    owner = (controller.plugin_key if controller.respond_to?(:plugin_key)) || Cms::Plugins.owner_of(controller.class)
    [owner, *@plugins_on_page, *Cms::Plugins.enabled_slots(:nav_actions).keys].compact.uniq
  end

  def plugin_stylesheet_tag(name)
    stylesheet_link_tag(name, "data-turbo-track": "dynamic")
  rescue Propshaft::MissingAssetError => error
    Rails.error.report(error, handled: true, context: {plugin_stylesheet: name})
    nil
  end

  # What enabled plugins registered for a slot in this view, noting them so
  # the page loads their stylesheets (page_plugins).
  def plugin_slots(name, **locals)
    slots = Cms::Plugins.enabled_slots(name)
    (@plugins_on_page ||= []).concat(slots.keys)
    safe_join(slots.values.map { |partial| render(partial, **locals) })
  end

  # The core's version, for Settings and the footer of the Settings index.
  def cms_version = Cms::VERSION

  def icon_tag(name, **options)
    tag.span class: class_names("icon icon--#{name}", options.delete(:class)), "aria-hidden": true, **options
  end

  STATUS_TONES = {
    "positive" => %w[published active approved paid accepted delivered succeeded success enabled ready verified],
    "negative" => %w[failed rejected void overdue canceled failure revoked off not\ verified],
    "waiting" => %w[draft pending scheduled queued sent open],
    "progress" => %w[running in\ progress],
    "neutral" => %w[archived unpublished dismissed closed skipped disabled]
  }.flat_map { |tone, labels| labels.map { [it, tone] } }.to_h.freeze

  def status_tone(label, highlight: false)
    STATUS_TONES.fetch(label.to_s.downcase) { highlight ? "progress" : "neutral" }
  end

  # The badge color for each tone: green for what's live or done, red for
  # what failed, yellow for what waits, the accent for what's under way.
  STATUS_BADGES = {"positive" => :green, "negative" => :red, "waiting" => :yellow, "progress" => :blue, "neutral" => :gray}.freeze

  # A status label as a small chip tinted by what it means (data-tone names
  # the meaning).
  def status_tag(label, highlight: false)
    tone = status_tone(label, highlight: highlight)
    tag.span label, class: ui(:badge, STATUS_BADGES.fetch(tone)), data: {tone: tone}
  end

  # The site's color and font (Settings › Branding) on top of the app's
  # stylesheets: /branding.css, plus the Google font it names. Nothing when
  # the site hasn't set either.
  def branding_stylesheet_tags
    branding = Branding.current
    return unless branding.customized?

    version = Setting.find_by(key: Branding::KEY)&.updated_at.to_i
    safe_join([
      (tag.link(rel: "preconnect", href: "https://fonts.googleapis.com") if branding.font),
      (tag.link(rel: "preconnect", href: "https://fonts.gstatic.com", crossorigin: "") if branding.font),
      (stylesheet_link_tag(branding.google_font_url) if branding.font),
      stylesheet_link_tag(branding_stylesheet_path(v: version), "data-turbo-track": "reload")
    ].compact, "\n")
  rescue StandardError
    nil
  end

  # Where a content record is edited in the admin, or nil for a record with no
  # page of its own.
  def admin_record_path(record)
    case record
    when Page            then edit_page_path(record)
    when CollectionEntry then edit_collection_entry_path(record.collection.slug, record.slug)
    when Global          then edit_global_path(record.slug)
    end
  end

  EXTERNAL_URL = %r{\Ahttps?://\S+\z}i

  # Whether a URL someone typed (a canonical URL, a quote request's page_url)
  # is safe to link to: http(s) only, never javascript: or data:.
  def external_url?(url)
    url.to_s.match?(EXTERNAL_URL)
  end

  # A link that opens in a new tab, but only to an http(s) URL; anything else
  # shows as text.
  def external_link(url, text = url, link_class: nil)
    if external_url?(url)
      link_to text, url.to_s, class: link_class || ui(:link), target: "_blank", rel: "noopener"
    else
      text.to_s
    end
  end

  # "3 hours ago", with the exact time on hover, in the site's zone and named.
  def time_ago_tag(time)
    return "—" if time.blank?

    local = time.in_time_zone
    time_tag time, "#{time_ago_in_words(time)} ago", title: "#{l(local, format: :long)} #{local.strftime("%Z")}"
  end

  # A native date input with the date-field controller: a click opens the
  # picker; t, + and - move the date, Delete clears it.
  DATE_FIELD_DATA = {controller: "date-field", action: "click->date-field#open keydown->date-field#shortcut"}.freeze

  def date_input(form, method, **options)
    form.date_field(method, **options.merge(data: DATE_FIELD_DATA.merge(options[:data] || {})))
  end

  # A key, token or secret, masked until the eye is clicked. A helper, not a
  # partial, so it works inside form_with. reveal_controller toggles
  # .secret-field--shown, which swaps the eye's two icons (inputs.css).
  def secret_field(form, method, placeholder: nil, **options)
    tag.span class: "secret-field relative flex items-center", data: {controller: "reveal"} do
      safe_join([
        form.password_field(method, value: form.object.try(method), class: "w-full pr-10 font-mono", autocomplete: "off",
          spellcheck: false, placeholder: placeholder, data: {reveal_target: "input", "1p-ignore": true}, **options),
        tag.button(type: "button", class: ui(:button, :plain, :icon, "absolute right-0"), title: "Show", aria: {pressed: false},
          data: {reveal_target: "button", action: "reveal#toggle"}) do
          safe_join([icon_tag("eye", class: "secret-field__show size-4"), icon_tag("eye-off", class: "secret-field__hide size-4"),
            tag.span("Show or hide", class: "sr-only")])
        end
      ])
    end
  end

  # The site's branding for the layouts: logo, favicon, title and tokens.
  # Falls back to {} if anything goes wrong (no settings yet, etc.).
  def current_branding
    @current_branding ||= read_branding
  end

  private

  def read_branding
    branding = Setting.get("branding")
    general  = Setting.get("general")

    favicon_id = branding["favicon_id"]
    {
      logo_url:        branding_asset_url(branding["logo_id"]),
      # The admin menu's: as wide as the menu, at twice its pixels.
      logo_url_small:  branding_asset_url(branding["logo_id"], resize_to: 480),
      favicon_url:     branding_asset_url(favicon_id, resize_to: 64),
      favicon_url_180: branding_asset_url(favicon_id, resize_to: 180),
      favicon_type:    branding_asset_content_type(favicon_id),
      site_title:      general["title"],
      primary_color:   branding["primary_color"],
      secondary_color: branding["secondary_color"],
      font:            branding["font"],
      border_radius:   branding["border_radius"],
      box_shadow:      branding["box_shadow"]
    }
  rescue StandardError
    {}
  end

  # An asset's URL (MediaLibrary) with two niceties:
  #   * `resize_to:` (px) asks for a resized rendition of a raster image, so
  #     the browser doesn't download a multi-MB PNG to show a 32×32 favicon.
  #     SVGs, and an install without libvips, get the file as it is.
  #   * `?v=<updated_at_int>` cache-buster on the URL so swapping the
  #     underlying asset invalidates browser caches without a hard refresh.
  def branding_asset_url(id, resize_to: nil)
    asset = MediaLibrary.find(id) or return nil

    base = resize_to && ApplicationHelper.variants_supported? ? asset.thumb_url(resize_to) : asset.url
    "#{base}?v=#{asset.updated_at.to_i}" if base
  end

  def branding_asset_content_type(id)
    MediaLibrary.find(id)&.content_type
  end

  # One-time probe: can libvips actually be loaded? In dev on NixOS the Rails
  # server may have started outside a `nix develop` shell that exports
  # LD_LIBRARY_PATH, in which case asking Active Storage for a resized
  # variant URL would 500 on fetch. Falling back to the blob URL keeps the
  # favicon visible (just unresized) instead of breaking it.
  def self.variants_supported?
    return @variants_supported if defined?(@variants_supported)

    @variants_supported = begin
      require "vips"
      Vips::LIBRARY_VERSION
      true
    rescue LoadError, NameError, StandardError
      false
    end
  end
end
