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
      ["GitHub", :settings_github_path, "settings:read", "Access token and the site's repository."],
      ["Deploy", :settings_deploy_path, "settings:read", "The build hook the CMS pings on publish."],
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
    visible.group_by(&:group).each do |group, pages|
      section = sections.find { |name, _| name == group } || (sections << [group, []]).last
      core = section[1].map { |label, path, description| [label, [path, description]] }
      additions = pages.map { |page| [page.label, [instance_exec(&page.path), page.description], page.after] }
      section[1] = Cms::Plugins.arrange(core, additions).map { |label, (path, description)| [label, path, description] }
    end
    sections.select { |_, links| links.any? }
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

  # A secret, code or command shown for copying (type.css's code-block,
  # wrapped wherever it breaks).
  def settings_code_classes(extra = nil)
    ["code-block code-block--wrap", extra].compact.join(" ")
  end

  # A labelled field: its name, the control from the block, and a hint.
  def settings_field(label, hint: nil, &block)
    tag.label class: "field" do
      safe_join([
        tag.span(label, class: "label"),
        capture(&block),
        (tag.span(hint, class: "help") if hint)
      ].compact)
    end
  end

  # A labelled on/off switch for a boolean field. The switch's look is
  # forms.css's (switch, switch__input, switch__btn): it follows the
  # checkbox's :checked and :disabled.
  def settings_switch(form, method, label, hint: nil, checked: nil)
    tag.label class: "switch-field" do
      safe_join([
        tag.span(class: "switch") do
          safe_join([
            form.check_box(method, {class: "switch__input", checked: checked}.compact),
            tag.span(class: "switch__btn")
          ])
        end,
        tag.span(class: "stack stack--2xs") do
          safe_join([tag.span(label, class: "label"), (tag.span(hint, class: "help") if hint)].compact)
        end
      ])
    end
  end

  # A button that copies text (a secret, a command) to the clipboard.
  def copy_button(content, label: "Copy")
    tag.button label, type: "button", class: "btn btn--sm no-shrink",
      data: {controller: "copy-to-clipboard", copy_to_clipboard_content_value: content,
             copy_to_clipboard_success_class: "btn--success", action: "copy-to-clipboard#copy"}
  end
end
