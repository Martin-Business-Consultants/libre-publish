# frozen_string_literal: true

module SettingsHelper
  # Every zone Rails knows, one option per IANA name ("Asia/Tokyo"), labelled
  # with all the names Rails gives it ("(GMT+09:00) Osaka, Sapporo, Tokyo").
  # A stored zone Rails doesn't list is kept as an option, so saving the form
  # doesn't drop it.
  def site_time_zone_options(current = nil)
    options = ActiveSupport::TimeZone.all.group_by { it.tzinfo.name }.map { |name, zones|
      ["(GMT#{zones.first.formatted_offset}) #{zones.map(&:name).join(", ")}", name]
    }
    options << [current, current] if current.present? && options.none? { it.last == current }
    options
  end

  # The sections, grouped, with what each is for and the capability it needs
  # (nil: any signed-in user — your own account's pages). The workspace's
  # settings need settings:read to open and settings:write to save. Drives both the section list beside every
  # settings page and the Settings index.
  SETTINGS_SECTIONS = {
    "Your account" => [
      ["Account", :settings_profile_path, nil, "Your name, email, password, two-factor, sessions, and deleting your account."],
      ["API token", :settings_api_token_path, nil, "Your personal token for the API and the cms CLI."],
      # The workspace's credentials for machines sit with the personal token.
      ["Service tokens", :settings_service_tokens_path, "settings:read", "Credentials for machines: the site, builds, agents."]
    ],
    "Workspace" => [
      ["General", :settings_general_path, "settings:read", "Business name, contact details, public URL."],
      # Your appearance, and (with settings:read) the logo, colors, type and brand context.
      ["Branding", :settings_branding_path, nil, "Appearance, logo, favicon, colors, font, corners, and brand context."],
      ["Search", :settings_search_path, "settings:read", "How search engines and AI see the site: AI crawlers, who you are, robots.txt."],
      ["Security policy", :settings_security_policy_path, "settings:read", "The Content-Security-Policy the site and the admin send: what may load, and what browsers report blocked."],
      ["Media", :settings_media_path, "settings:read", "How heavy an image may be, and making uploads lighter."],
      ["Updates", :settings_updates_path, "settings:read", "The version this install runs, and updating to the newest release."],
      ["History", :settings_histories_path, "settings:read", "Every change to these settings, to compare and restore."]
    ],
    "Integrations" => [
      ["Deploy", :settings_deploy_path, "settings:read", "How the site rebuilds on publish: a build hook, Cloudflare, or GitHub with its repository and token."],
      ["Email delivery", :settings_mail_delivery_path, "settings:read", "The SMTP server the site's email goes through, and a test email."]
    ]
  }.freeze

  # [[group, [[label, path, description], …]], …] for what this role can open.
  # Settings › Plugins sits under Workspace; each enabled plugin's own page
  # (Cms::Plugins.settings) under the group it names, "Plugins" by default.
  def settings_sections
    sections = SETTINGS_SECTIONS.filter_map do |group, items|
      links = items.filter_map do |label, path, capability, description|
        # Deploy is a frontend's builds: only while the site is served over the API.
        next if path == :settings_deploy_path && !Serving.api?

        [label, public_send(path), description] if capability.nil? || Current.user&.can?(capability)
      end
      [group, links] if links.any?
    end

    visible = Cms::Plugins.enabled_settings_pages.values.select { |page| page.capability.nil? || Current.user&.can?(page.capability) }
    by_group = visible.group_by(&:group)
    plugin_pages = by_group.delete("Plugins") || []
    by_group.each do |group, pages|
      section = sections.find { |name, _| name == group } || (sections << [group, []]).last
      core = section[1].map { |label, path, description| [label, [path, description]] }
      additions = pages.map { |page| [page.label, [instance_exec(&page.path), page.description], page.after] }
      section[1] = Cms::Plugins.arrange(core, additions).map { |label, (path, description)| [label, path, description] }
    end
    sections << ["Plugins", plugins_section(plugin_pages)] if Current.user&.can?("settings:read")
    sections.select { |_, links| links.any? }
  end

  # Settings › Plugins and Themes, as Runwell nests them: each plugin's own
  # settings page (Cms::Plugins.settings, in the "Plugins" group) under All
  # plugins, as its fourth element [[label, url], …].
  def plugins_section(pages)
    nested = Cms::Plugins.arrange([], pages.map { |page| [page.label, instance_exec(&page.path), page.after] }).map { |label, url| [label, url] }
    [["All plugins", settings_plugins_path, "What this install adds to the CMS, and switching it on.", nested],
      ["Themes", settings_themes_path, "The theme that draws the site, and the others installed.", []]]
  end

  # The Settings nav's icon for a section (settings/nav), rune's dot for one
  # it doesn't know (a plugin's).
  SETTINGS_ICONS = {
    "Account" => "person", "API token" => "password", "Service tokens" => "lock", "General" => "globe",
    "Branding" => "art", "Search" => "search", "Security policy" => "authentication", "Media" => "image",
    "Updates" => "refresh", "History" => "history", "GitHub" => "code", "Deploy" => "paper-plane",
    "Email delivery" => "email", "All plugins" => "package", "Themes" => "sliders"
  }.freeze

  def settings_icon(label) = SETTINGS_ICONS.fetch(label, "dot")

  # A link in the Settings nav: an icon for a section, none for one nested
  # under it. Current on its page and the pages under it.
  def settings_nav_link(label, url, icon: nil)
    here = request.path == url || request.path.start_with?("#{url}/")
    link_to url, class: class_names("settings-nav__link", "settings-nav__link--nested": icon.nil?), aria: {current: ("page" if here)} do
      safe_join([(icon_tag(icon) if icon), tag.span(label)].compact)
    end
  end

  # Where a plugin's running copy came from (InstalledPlugins), and its repository.
  def plugin_source_label(plugin)
    key = plugin.key.to_s
    where = case InstalledPlugins.origins[key]
    when :installed then "Installed from Settings › Plugins"
    when :image then "Comes with this install"
    else plugin.bundled ? "Bundled with the CMS" : "This checkout"
    end
    [where, InstalledPlugins.repo(key)].compact.join(" · ")
  end

  # A secret, code or command shown for copying (base.css's code-block,
  # wrapped wherever it breaks).
  def settings_code_classes(extra = nil)
    ["code-block", extra].compact.join(" ")
  end

  # A labelled field (rune_ui's): its name, the control from the block, and a hint.
  def settings_field(label, hint: nil, &block)
    tag.label class: "field" do
      safe_join([
        tag.span(label, class: "field__label"),
        capture(&block),
        (tag.span(hint, class: "field__hint") if hint)
      ].compact)
    end
  end

  # A labelled on/off switch for a boolean field: rune_ui's switch beside its
  # label and hint.
  def settings_switch(form, method, label, hint: nil, checked: nil)
    tag.label class: "switch-field" do
      safe_join([
        switch(form, method, **{checked: checked}.compact),
        tag.span(class: "switch-field__text") do
          safe_join([tag.span(label, class: "field__label"), (tag.span(hint, class: "field__hint") if hint)].compact)
        end
      ])
    end
  end
end
