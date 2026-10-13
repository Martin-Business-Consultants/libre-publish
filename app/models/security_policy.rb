# frozen_string_literal: true

# Settings › Security policy: the Content-Security-Policy the public website
# sends, and what the admin's may allow beyond its own. Kept in the
# "security_policy" setting.
#
# The website's is off until someone turns it on: report only (browsers say
# what it would block, to /csp-reports, and block nothing) or enforced. It
# allows the site itself, the services ticked (PRESETS), the sources added by
# hand per directive, and inline scripts (what the Scripts global pastes
# carries no nonce) unless "strict" is chosen, when only the CMS's own inline
# scripts, which carry the request's nonce, run.
#
# The admin's is always enforced (ApplicationController); here it only gains
# sources, a directive at a time (a sign-in page a form goes on to:
# form-action), and reports what it blocks.
module SecurityPolicy
  SETTING_KEY = "security_policy"
  MODES = {"off" => "Off", "report" => "Report only (test it)", "enforce" => "Enforced"}.freeze
  DIRECTIVES = %w[script-src style-src img-src font-src connect-src frame-src media-src form-action frame-ancestors].freeze
  ADMIN_DIRECTIVES = %w[script-src style-src font-src connect-src frame-src media-src form-action].freeze
  SOURCE = %r{\A(https?://)?(\*\.)?[a-z0-9-]+(\.[a-z0-9-]+)+(:\d+)?(/\S*)?\z|\A(https:|data:|blob:|wss?://\S+)\z}i

  # Services a website commonly runs, and what each needs.
  PRESETS = {
    "turnstile" => {label: "Cloudflare Turnstile (the CMS's forms)", sources: {"script-src" => %w[https://challenges.cloudflare.com], "frame-src" => %w[https://challenges.cloudflare.com]}},
    "google_analytics" => {label: "Google Analytics and Google Tag Manager",
                           sources: {"script-src" => %w[https://www.googletagmanager.com https://*.googletagmanager.com],
                                     "connect-src" => %w[https://*.google-analytics.com https://*.analytics.google.com https://*.googletagmanager.com],
                                     "img-src" => %w[https://*.google-analytics.com https://*.googletagmanager.com]}},
    "google_ads" => {label: "Google Ads conversion tracking",
                     sources: {"script-src" => %w[https://www.googleadservices.com https://googleads.g.doubleclick.net https://www.google.com],
                               "img-src" => %w[https://googleads.g.doubleclick.net https://www.google.com https://*.google.com],
                               "connect-src" => %w[https://*.doubleclick.net https://www.google.com https://google.com],
                               "frame-src" => %w[https://bid.g.doubleclick.net https://td.doubleclick.net]}},
    "meta_pixel" => {label: "Meta (Facebook) pixel",
                     sources: {"script-src" => %w[https://connect.facebook.net], "img-src" => %w[https://www.facebook.com],
                               "connect-src" => %w[https://www.facebook.com https://connect.facebook.net], "frame-src" => %w[https://www.facebook.com]}},
    "clarity" => {label: "Microsoft Clarity",
                  sources: {"script-src" => %w[https://www.clarity.ms https://*.clarity.ms], "connect-src" => %w[https://*.clarity.ms], "img-src" => %w[https://*.clarity.ms]}},
    "google_fonts" => {label: "Google Fonts", sources: {"style-src" => %w[https://fonts.googleapis.com], "font-src" => %w[https://fonts.gstatic.com]}},
    "google_maps" => {label: "Google Maps embeds",
                      sources: {"frame-src" => %w[https://www.google.com https://maps.google.com], "img-src" => %w[https://*.googleapis.com https://*.gstatic.com]}},
    "youtube" => {label: "YouTube videos", sources: {"frame-src" => %w[https://www.youtube.com https://www.youtube-nocookie.com], "img-src" => %w[https://i.ytimg.com]}},
    "vimeo" => {label: "Vimeo videos", sources: {"frame-src" => %w[https://player.vimeo.com], "img-src" => %w[https://i.vimeocdn.com]}},
    "calendly" => {label: "Calendly booking",
                   sources: {"script-src" => %w[https://assets.calendly.com], "style-src" => %w[https://assets.calendly.com], "frame-src" => %w[https://calendly.com]}},
    "stripe" => {label: "Stripe payments",
                 sources: {"script-src" => %w[https://js.stripe.com], "frame-src" => %w[https://js.stripe.com https://hooks.stripe.com], "connect-src" => %w[https://api.stripe.com]}}
  }.freeze

  DEFAULTS = {"mode" => "off", "strict" => false, "presets" => %w[turnstile], "sources" => {}, "admin_sources" => {}}.freeze

  module_function

  def get
    data = DEFAULTS.merge(Setting.get(SETTING_KEY).to_h.slice(*DEFAULTS.keys))
    data.merge("sources" => clean(data["sources"], DIRECTIVES), "admin_sources" => clean(data["admin_sources"], ADMIN_DIRECTIVES),
      "presets" => Array(data["presets"]) & PRESETS.keys)
  end

  def mode = get["mode"]
  def website? = mode != "off"

  # From Settings › Security policy: only what was sent changes. Sources come one a line (or space-separated) per directive.
  def update(submitted)
    submitted = submitted.to_h.stringify_keys
    data = {}
    data["mode"] = submitted["mode"].presence_in(MODES.keys) || "off" if submitted.key?("mode")
    data["strict"] = ActiveModel::Type::Boolean.new.cast(submitted["strict"]) || false if submitted.key?("strict")
    data["presets"] = Array(submitted["presets"]) & PRESETS.keys if submitted.key?("presets")
    data["sources"] = clean(submitted["sources"], DIRECTIVES) if submitted.key?("sources")
    data["admin_sources"] = clean(submitted["admin_sources"], ADMIN_DIRECTIVES) if submitted.key?("admin_sources")
    Setting.set(SETTING_KEY, data) if data.any?
    get
  end

  # One source added to a directive (a report's "Allow"), on the website's policy or the admin's.
  def allow(surface, directive, source)
    key = (surface.to_s == "admin") ? "admin_sources" : "sources"
    allowed = (key == "admin_sources") ? ADMIN_DIRECTIVES : DIRECTIVES
    return false unless allowed.include?(directive) && source.to_s.match?(SOURCE)

    current = get[key]
    Setting.set(SETTING_KEY, key => current.merge(directive => (Array(current[directive]) | [source])))
    true
  end

  # {directive => [sources]}: the website's, made from the presets ticked and the sources added.
  def website_sources(settings = get)
    merged = Hash.new { |hash, key| hash[key] = [] }
    settings["presets"].each { |preset| PRESETS.dig(preset, :sources).each { |directive, list| merged[directive] |= list } }
    settings["sources"].each { |directive, list| merged[directive] |= list }
    merged
  end

  # The website's header value. `nonce` for a strict policy (inline scripts the CMS printed carry it).
  def website_header(nonce: nil, settings: get, report_uri: "/csp-reports?surface=website")
    sources = website_sources(settings)
    inline = settings["strict"] && nonce ? ["'nonce-#{nonce}'"] : ["'unsafe-inline'"]
    directives = {
      "default-src" => ["'self'"],
      "script-src" => ["'self'", *inline, *sources["script-src"]],
      "style-src" => ["'self'", "'unsafe-inline'", *sources["style-src"]],
      "img-src" => ["'self'", "data:", "blob:", *sources["img-src"]],
      "font-src" => ["'self'", "data:", *sources["font-src"]],
      "connect-src" => ["'self'", *sources["connect-src"]],
      "frame-src" => ["'self'", *sources["frame-src"]],
      "media-src" => ["'self'", "blob:", *sources["media-src"]],
      "form-action" => ["'self'", *sources["form-action"]],
      "frame-ancestors" => ["'self'", *sources["frame-ancestors"]],
      "object-src" => ["'none'"],
      "base-uri" => ["'self'"]
    }
    directives["report-uri"] = [report_uri] if report_uri
    directives.map { |name, values| "#{name} #{values.uniq.join(" ")}" }.join("; ")
  end

  def header_name(settings = get) = (settings["mode"] == "report") ? "Content-Security-Policy-Report-Only" : "Content-Security-Policy"

  # The services and hosts the Scripts global loads from that the website's policy doesn't allow yet:
  # {presets: [key], hosts: {directive => [source]}}.
  def suggestions(settings = get)
    html = Array(Global.find_by(slug: Global::SCRIPTS_SLUG)&.data.to_h["items"]).grep(Hash).flat_map { [it["head"], it["body"]] }.compact.join("\n")
    html = Global::ScriptCode.restore(html).to_s
    presets = PRESETS.keys.reject { settings["presets"].include?(it) }.select do |key|
      PRESETS.dig(key, :sources).values.flatten.any? { |source| host_in?(html, source) }
    end
    allowed = website_sources(settings.merge("presets" => settings["presets"] | presets))
    found = Hash.new { |hash, key| hash[key] = [] }
    Nokogiri::HTML5::DocumentFragment.parse(html).css("script[src], iframe[src], img[src], link[href]").each do |element|
      url = element["src"] || element["href"]
      origin = origin_of(url) or next
      directive = {"script" => "script-src", "iframe" => "frame-src", "img" => "img-src", "link" => "style-src"}.fetch(element.name)
      found[directive] |= [origin] unless covered?(allowed[directive], origin)
    end
    {presets: presets, hosts: found.reject { |_, list| list.empty? }}
  end

  def clean(sources, directives)
    sources.to_h.stringify_keys.slice(*directives).to_h do |directive, list|
      list = list.is_a?(String) ? list.split(/[\s,]+/) : Array(list)
      [directive, list.map(&:strip).compact_blank.select { it.match?(SOURCE) }.uniq.first(50)]
    end.reject { |_, list| list.empty? }
  end

  def origin_of(url)
    uri = URI.parse(url.to_s.strip)
    return unless uri.scheme.in?(%w[http https]) && uri.host

    "https://#{uri.host}"
  rescue URI::InvalidURIError
    nil
  end

  def host_in?(html, source)
    host = source.sub(%r{\Ahttps?://}, "").delete_prefix("*.")
    html.include?(host)
  end

  def covered?(list, origin)
    host = origin.sub(%r{\Ahttps?://}, "")
    Array(list).any? do |source|
      allowed = source.sub(%r{\Ahttps?://}, "").sub(%r{/.*\z}, "")
      allowed == host || (allowed.start_with?("*.") && host.end_with?(allowed.delete_prefix("*")))
    end
  end
end
