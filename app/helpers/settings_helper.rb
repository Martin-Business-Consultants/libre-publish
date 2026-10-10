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
      ["Updates", :settings_updates_path, "settings:read", "The version this install runs, and updating to the newest release."]
    ],
    "Integrations" => [
      ["GitHub", :settings_github_path, "settings:read", "Access token and the site's repository."],
      ["Deploy", :settings_deploy_path, "settings:read", "The build hook the CMS pings on publish."]
    ]
  }.freeze

  # [[group, [[label, path, description], …]], …] for what this role can open.
  # Settings › Plugins sits under Workspace; each enabled plugin's own page
  # (Cms::Plugins.settings) under the group it names, "Plugins" by default.
  def settings_sections
    sections = SETTINGS_SECTIONS.filter_map do |group, items|
      links = items.filter_map do |label, path, capability, description|
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

  # A secret, code or command shown for copying: mono, on gray-50.
  SETTINGS_CODE_CLASSES = "block rounded-md border border-gray-200 bg-gray-50 px-3 py-2 font-mono text-xs text-gray-800 break-all whitespace-pre-wrap"

  def settings_code_classes(extra = nil)
    [SETTINGS_CODE_CLASSES, extra].compact.join(" ")
  end

  # A labelled field: its name, the control from the block, and a hint.
  def settings_field(label, hint: nil, &block)
    tag.label class: "flex flex-col gap-1.5" do
      safe_join([
        tag.span(label, class: ui(:label)),
        capture(&block),
        (tag.span(hint, class: ui(:help)) if hint)
      ].compact)
    end
  end

  # A labelled on/off switch for a boolean field. The switch's look is
  # inputs.css's (switch, switch__input, switch__btn): it follows the
  # checkbox's :checked and :disabled.
  def settings_switch(form, method, label, hint: nil, checked: nil)
    tag.label class: "flex items-center gap-3" do
      safe_join([
        tag.span(class: "switch shrink-0") do
          safe_join([
            form.check_box(method, {class: "switch__input", checked: checked}.compact),
            tag.span(class: "switch__btn")
          ])
        end,
        tag.span(class: "flex flex-col gap-0.5") do
          safe_join([tag.span(label, class: ui(:label)), (tag.span(hint, class: ui(:help)) if hint)].compact)
        end
      ])
    end
  end

  # A button that copies text (a secret, a command) to the clipboard.
  def copy_button(content, label: "Copy")
    tag.button label, type: "button", class: ui(:button, :small, "shrink-0"),
      data: {controller: "copy-to-clipboard", copy_to_clipboard_content_value: content,
             copy_to_clipboard_success_class: "btn--success", action: "copy-to-clipboard#copy"}
  end
end
