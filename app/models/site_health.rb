# frozen_string_literal: true

# Whether the site is in good order. The business's details are complete and
# the same everywhere (name, address, phone: NAP), forms are protected from
# spam and tell someone, search engines get what they need, the pages a
# business must have exist, and backups, rebuilds and webhooks work. Checked against the site as it is; shown in Docs › Site health, at
# /api/site_health and by `cms site-health`.
#
# Plugins' parts come through what they provide (:published_forms,
# :spam_protection), so a site without a plugin simply has fewer checks.
module SiteHealth
  Check = Checklist::Check

  GROUPS = ["Business details", "Forms and spam", "Search", "Pages a site needs", "Content", "Operations"].freeze

  # The checks that are the CMS's own business (how it's run, not what the
  # site shows): a site's build isn't held to them (/api/v1/site_health's
  # `for_site`).
  CMS_ONLY_GROUPS = ["Operations"].freeze
  CMS_ONLY_KEYS = %w[time_zone].freeze

  # A US-style phone number, with or without a country code and separators.
  PHONE = /(?<![\d])(?:\+?1[\s.\-]?)?\(?(\d{3})\)?[\s.\-]?(\d{3})[\s.\-]?(\d{4})(?![\d])/

  module_function

  def checks
    GROUPS.flat_map { |group| send(group.parameterize(separator: "_")) }.compact
  end

  def summary(list = checks) = Checklist.summary(list)

  def for_site?(check) = !CMS_ONLY_GROUPS.include?(check.group) && !CMS_ONLY_KEYS.include?(check.key)

  # --- Business details (NAP) ------------------------------------------------

  def business_details
    general = Setting.get("general")
    address = %w[address_line1 city state zip].map { general[it].to_s.strip }
    phone = digits(general["phone"])
    others = phones_in_content.reject { |number, _| number == phone }
    [
      Check.new(key: "business_name", group: "Business details", title: "The business name is set",
        detail: "Settings › General › Business name: search results, emails and structured data use it.",
        ok: general["title"].present?, href: "/settings/general", cli: "cms get /settings/general"),
      Check.new(key: "address", group: "Business details", title: "The full address is set",
        detail: address.all?(&:present?) ? address.join(", ") : "Settings › General › Address, City, State and Zip, as the business is listed elsewhere.",
        ok: address.all?(&:present?), href: "/settings/general", cli: "cms get /settings/general"),
      Check.new(key: "phone", group: "Business details", title: "The phone number is set",
        detail: phone ? "The site reads it from Settings › General, so it changes in one place." : "Settings › General › Phone.",
        ok: phone.present?, href: "/settings/general", cli: "cms get /settings/general"),
      Check.new(key: "phone_consistent", group: "Business details", title: "One phone number, everywhere",
        detail: others.empty? ? "No other phone number appears in the site's pages or globals." :
          "Other numbers appear in: #{others.map { |number, where| "#{format_phone(number)} (#{where.first(3).to_sentence})" }.join("; ")}. Make them the business's, or read it from Settings.",
        ok: phone ? others.empty? : nil, href: "/pages", cli: "cms search \"#{format_phone(others.keys.first || phone)}\""),
      Check.new(key: "email", group: "Business details", title: "The contact email is set",
        detail: "Settings › General › Email: the address visitors write to.",
        ok: general["email"].to_s.include?("@"), href: "/settings/general", cli: "cms get /settings/general"),
      Check.new(key: "time_zone", group: "Business details", title: "The site's time zone is set",
        detail: "Settings › General › Time zone: schedules and dates are read in it.",
        ok: general["timezone"].present?, href: "/settings/general", cli: nil),
      Check.new(key: "business_profile", group: "Business details", title: "Google Business Profile matches",
        detail: "The name, address and phone on Google (and Apple, Bing, Yelp) should be exactly these. The CMS can't see them; check them yourself.",
        ok: nil, href: nil, cli: nil)
    ]
  end

  # --- Forms and spam --------------------------------------------------------

  def forms_and_spam
    published = Cms::Plugins.provided(:published_forms)
    return [] if published.nil?

    forms = Array(published)
    protection = Cms::Plugins.provided(:spam_protection) || {}
    silent = forms.reject { |form| form.notification_email&.enabled && form.notification_email.recipient_list.any? }
    sender = Setting.get("forms_settings")["from_email"].to_s
    site_domain = URI.parse(Setting.get("general")["site_base_url"].to_s).host.to_s.delete_prefix("www.") rescue ""
    [
      Check.new(key: "captcha", group: "Forms and spam", title: "Forms are protected from spam",
        detail: protection[:configured] ? "#{protection[:provider] == "turnstile" ? "Cloudflare Turnstile" : "Google reCAPTCHA"} is set up with both keys." :
          "Settings › Forms › Spam protection: Cloudflare Turnstile (recommended) or reCAPTCHA, with its site key and secret. The hidden _hp field alone stops only simple bots.",
        ok: forms.any? ? protection[:configured] == true : nil, href: "/settings/forms", cli: nil),
      Check.new(key: "form_notifications", group: "Forms and spam", title: "Every live form tells someone",
        detail: silent.empty? ? "Each published form's notification email is on, with recipients." : "#{silent.map(&:title).to_sentence} #{silent.one? ? "has" : "have"} no notification email on with recipients.",
        ok: forms.any? ? silent.empty? : nil, href: "/forms", cli: "cms emails <form>"),
      Check.new(key: "form_sender_domain", group: "Forms and spam", title: "Form emails come from the site's own domain",
        detail: sender.present? ? "They come from #{sender}." : "Settings › Forms › From address: an address on the site's domain gets delivered; a default may land in spam.",
        ok: forms.any? ? (sender.present? && (site_domain.blank? || sender.end_with?("@#{site_domain}") || sender.end_with?(".#{site_domain}"))) : nil,
        href: "/settings/forms", cli: nil)
    ]
  end

  # --- Search ----------------------------------------------------------------

  def search
    published = Page.where(status: "published").to_a
    home = published.find { it.path == "home" }
    seo = ->(record) { record.seo.is_a?(Hash) ? record.seo : {} }
    no_description = published.select { seo.(it)["meta_description"].blank? }
    hidden = published.select { ActiveModel::Type::Boolean.new.cast(seo.(it)["noindex"]) }
    structured = home && (seo.(home)["schema_type"].present? || seo.(home)["json_ld"].present?)
    [
      Check.new(key: "meta_descriptions", group: "Search", title: "Published pages have meta descriptions",
        detail: no_description.empty? ? "Every published page has one." : "#{no_description.size} #{"page".pluralize(no_description.size)} without: #{no_description.first(5).map(&:title).to_sentence}.",
        ok: published.any? ? no_description.empty? : nil, href: "/pages?status=published", cli: "cms pages --status published"),
      Check.new(key: "social_image", group: "Search", title: "The home page has a sharing image",
        detail: "The home page's SEO › Social image: what links to the site show in messages and social posts.",
        ok: home ? seo.(home)["og_image_id"].present? : nil, href: home ? "/pages/home/edit" : "/pages", cli: "cms page home"),
      Check.new(key: "structured_data", group: "Search", title: "The home page says what the business is",
        detail: "The home page's SEO › Structured data: a schema type (LocalBusiness, or a more exact one) or JSON-LD with the name, address and phone.",
        ok: home ? structured.present? : nil, href: home ? "/pages/home/edit" : "/pages", cli: "cms page home"),
      Check.new(key: "not_hidden", group: "Search", title: "No published page is hidden from search by mistake",
        detail: hidden.empty? ? "None is set to noindex." : "#{hidden.map(&:title).to_sentence} #{hidden.one? ? "is" : "are"} set to hide from search engines. Fine if meant.",
        ok: published.any? ? hidden.empty? : nil, href: "/pages", cli: nil),
      Check.new(key: "sitemap", group: "Search", title: "The sitemap lists the site",
        detail: "The site builds sitemap.xml from the CMS's sitemap; published pages and entries are in it unless hidden.",
        ok: published.any? ? Sitemap.new.entries.any? : nil, href: "/sitemap", cli: "cms sitemap"),
      Check.new(key: "redirects", group: "Search", title: "Old addresses redirect",
        detail: "After a redesign or a move, every old URL should redirect (Tools › Redirects), or its links and rankings are lost.",
        ok: nil, href: "/tools/redirects", cli: "cms redirects")
    ]
  end

  # --- Pages a site needs ----------------------------------------------------

  def pages_a_site_needs
    published = Page.where(status: "published").pluck(:path, :slug, :title)
    has = ->(*words) { published.any? { |path, slug, title| words.any? { [path, slug, title.to_s.downcase].join(" ").include?(it) } } }
    [
      Check.new(key: "home", group: "Pages a site needs", title: "A published home page",
        detail: "A page at the path home: the site serves it at /.", ok: published.any? { it.first == "home" }, href: "/pages", cli: "cms page home"),
      Check.new(key: "contact_page", group: "Pages a site needs", title: "A contact page",
        detail: "A published page visitors find the address, phone and a form on.", ok: has.("contact"), href: "/pages", cli: "cms pages"),
      Check.new(key: "privacy_page", group: "Pages a site needs", title: "A privacy policy",
        detail: "Required wherever a form collects details or tracking runs (GDPR, CCPA, Google Ads).", ok: has.("privacy"), href: "/pages", cli: "cms pages"),
      Check.new(key: "terms_page", group: "Pages a site needs", title: "Terms of service",
        detail: "Expected by anyone who sells, books or takes quotes online.", ok: has.("terms"), href: "/pages", cli: "cms pages"),
      Check.new(key: "accessibility_page", group: "Pages a site needs", title: "An accessibility statement",
        detail: "Recommended in the US and required for public bodies in the EU: what the site does for accessibility and whom to contact.",
        ok: has.("accessibility") || nil, href: "/pages", cli: "cms pages")
    ]
  end

  # --- Content ---------------------------------------------------------------

  def content
    # Without a media library (MediaLibrary), there are no images to check.
    images, unlabelled = MediaLibrary.images_without_alt || [[], []]
    [
      Check.new(key: "alt_text", group: "Content", title: "Images the site uses have alt text",
        detail: unlabelled.empty? ? "Every image in use has alt text." : "#{unlabelled.size} #{"image".pluralize(unlabelled.size)} in use without, such as #{unlabelled.first(3).map(&:title).to_sentence}.",
        ok: images.any? ? unlabelled.empty? : nil, href: "/media?kind=images", cli: "cms asset <id> set alt=\"…\"")
    ]
  end

  # --- Operations ------------------------------------------------------------

  def operations
    deploy = Setting.get(Deploys::SETTING_KEY)
    archives = SiteBackup.data_archives
    failing = Webhook.where(active: true).where.not(last_status: [nil, "", "success"]).pluck(:name)
    admins = User.joins(:role).where(roles: {name: "Admin"})
    [
      Check.new(key: "https", group: "Operations", title: "The site is served over HTTPS",
        detail: "Settings › General › Site base URL starts with https://.", ok: Setting.get("general")["site_base_url"].to_s.start_with?("https://"), href: "/settings/general", cli: nil),
      Check.new(key: "rebuilds", group: "Operations", title: "Publishing rebuilds the site, and the last rebuild worked",
        detail: Deploys.current.configured? ? "The last rebuild was #{deploy["last_status"].presence || "never run"}." : "Settings › Deploy: a GitHub dispatch or a host's build hook.",
        ok: Deploys.current.configured? && deploy["last_status"] == "success", href: "/settings/deploy", cli: "cms deploy"),
      Check.new(key: "webhooks", group: "Operations", title: "Webhooks are delivering",
        detail: failing.empty? ? "None is failing." : "#{failing.to_sentence} #{failing.one? ? "is" : "are"} failing.",
        ok: Webhook.where(active: true).exists? ? failing.empty? : nil, href: "/webhooks", cli: "cms webhooks"),
      Check.new(key: "recent_backup", group: "Operations", title: "A backup from the last week",
        detail: archives.any? ? "The newest is from #{archives.map(&:taken_at).max.to_date}." : "Tools › Backup: none yet. Updates take one automatically; download one too.",
        ok: archives.any? { it.taken_at > 7.days.ago }, href: "/tools/backup", cli: "cms backup > backup.tar.gz"),
      Check.new(key: "two_factor", group: "Operations", title: "Admins use two-factor sign-in",
        detail: "Settings › Two-factor, for each person with the Admin role.",
        ok: admins.any? ? admins.where(totp_enabled: false).none? : nil, href: "/settings/two_factor", cli: nil)
    ]
  end

  # --- Helpers ---------------------------------------------------------------

  def digits(text)
    match = text.to_s.match(PHONE) or return nil
    match.captures.join
  end

  def format_phone(number)
    number ? "(#{number[0, 3]}) #{number[3, 3]}-#{number[6, 4]}" : ""
  end

  # {"2695551234" => ["Home", "Footer"], …}: the phone numbers written into
  # published pages and globals, and where.
  def phones_in_content
    found = Hash.new { |hash, key| hash[key] = [] }
    sources = Page.where(status: "published").map { [it.title, [it.blocks, it.frontmatter]] } +
      Global.all.map { [it.name, [it.data]] }
    sources.each do |label, values|
      strings(values).each do |text|
        text.scan(PHONE) { found[$~.captures.join] |= [label] }
      end
    end
    found
  end

  def strings(value)
    case value
    when String then [value]
    when Hash then value.values.flat_map { strings(it) }
    when Array then value.flat_map { strings(it) }
    else []
    end
  end
end
