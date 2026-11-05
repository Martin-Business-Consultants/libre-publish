# frozen_string_literal: true

# Runwell UI: builders for the shadcn/ui port (app/assets/stylesheets/ui). The CSS classes are
# the components; these only spell them, the way shadcn's buttonVariants() and badgeVariants()
# do, so a view writes ui_button("Save") or link_to(…, class: ui_button_classes(:outline)).
# The styleguide at /cms/ui (development) shows every component.
module UiHelper
  BUTTON_VARIANTS = %i[default destructive outline secondary ghost link].freeze
  BUTTON_SIZES = %i[default sm lg icon icon_sm icon_lg].freeze
  BADGE_VARIANTS = %i[default secondary destructive outline positive warning info negative neutral count].freeze

  # Every class these builders can write, built from the variants above (named so the classes
  # spec reads them).
  BUILT_CLASSES = %w[
    ui-button--destructive ui-button--outline ui-button--secondary ui-button--ghost ui-button--link
    ui-button--sm ui-button--lg ui-button--icon ui-button--icon-sm ui-button--icon-lg ui-button--block
    ui-badge--secondary ui-badge--destructive ui-badge--outline ui-badge--positive ui-badge--warning
    ui-badge--info ui-badge--negative ui-badge--neutral ui-badge--count
    ui-avatar ui-avatar--sm ui-avatar--lg
  ].freeze

  # Class names for a button: ui_button_classes(:outline, size: :sm), plus any of the caller's.
  def ui_button_classes(variant = :default, size: :default, full_width: false, **options)
    variant = variant.to_sym
    size = size.to_sym
    raise ArgumentError, "unknown button variant #{variant}" unless BUTTON_VARIANTS.include?(variant)
    raise ArgumentError, "unknown button size #{size}" unless BUTTON_SIZES.include?(size)

    ["ui-button",
      (variant == :default) ? nil : "ui-button--#{variant}",
      (size == :default) ? nil : "ui-button--#{size.to_s.dasherize}",
      full_width ? "ui-button--block" : nil,
      options[:class].presence].compact.join(" ")
  end

  # A <button>: ui_button("Save"), ui_button(variant: :outline) { … }, or with an icon:
  # ui_button("Add", icon: "add"). type defaults to "button"; pass type: "submit" in a form.
  def ui_button(text = nil, variant: :default, size: :default, icon: nil, full_width: false, **options, &block)
    options[:type] ||= "button"
    options[:class] = ui_button_classes(variant, size: size, full_width: full_width, class: options[:class])
    tag.button(**options) { ui_button_content(text, icon, &block) }
  end

  # A link drawn as a button: ui_link_button("New page", new_page_path, variant: :outline).
  def ui_link_button(text, url, variant: :default, size: :default, icon: nil, full_width: false, **options)
    options[:class] = ui_button_classes(variant, size: size, full_width: full_width, class: options[:class])
    link_to(url, **options) { ui_button_content(text, icon) }
  end

  # A badge: ui_badge("Active", :positive), or a status in its tone: ui_status_badge("draft").
  def ui_badge(text, variant = :default, **options)
    variant = variant.to_sym
    raise ArgumentError, "unknown badge variant #{variant}" unless BADGE_VARIANTS.include?(variant)

    tag.span text, **options, class: ["ui-badge", (variant == :default) ? nil : "ui-badge--#{variant}", options[:class].presence].compact.join(" ")
  end

  STATUS_BADGES = {"positive" => :positive, "negative" => :negative, "waiting" => :warning, "progress" => :info, "neutral" => :neutral}.freeze

  def ui_status_badge(label, highlight: false, **options)
    tone = status_tone(label, highlight: highlight)
    ui_badge(label, STATUS_BADGES.fetch(tone), data: {tone: tone}, **options)
  end

  def ui_kbd(*keys)
    return tag.kbd(keys.first, class: "ui-kbd") if keys.one?

    tag.span(safe_join(keys.map { tag.kbd(it, class: "ui-kbd") }), class: "ui-kbd-group")
  end

  # Initials in a circle, or the image when there is one: ui_avatar("Ted Martin", size: :sm).
  def ui_avatar(name, image: nil, size: nil, **options)
    classes = ["ui-avatar", size ? "ui-avatar--#{size}" : nil, options.delete(:class)].compact.join(" ")
    tag.span(class: classes, title: name, **options) do
      if image
        image_tag(image, alt: name)
      else
        name.to_s.split.first(2).map { it[0] }.join.upcase
      end
    end
  end

  # Data table (ui/_data_table): one column of it. key names the column (its cells carry
  # data-column="key", so the Columns menu can hide them); align: :end for numbers;
  # hideable: false keeps it out of the Columns menu (the name column).
  UiColumn = Data.define(:key, :label, :align, :hideable, :header_class)

  def ui_column(key, label = key.to_s.humanize, align: nil, hideable: true, header_class: nil)
    UiColumn.new(key: key.to_s, label: label, align: align, hideable: hideable, header_class: header_class)
  end

  def ui_data_table_th(column)
    numeric = (column.align == :end) ? "ui-table__numeric" : nil
    tag.th(tx(column.label), class: [column.header_class, numeric].compact.join(" ").presence, data: {column: column.key})
  end

  # The data table's checkbox column (the select-all controller): the header's box ticks every
  # row, a row's box joins the bulk actions' form (layouts/shared/bulk_actions) by its id.
  def ui_select_all_header(label = "Select every row")
    tag.th do
      tag.input(type: "checkbox", class: "ui-checkbox", aria: {label: tx(label)}, data: {select_all_target: "all", action: "select-all#toggle"})
    end
  end

  def ui_select_cell(value, label:, form:, name: "ids[]")
    tag.td do
      tag.input(type: "checkbox", class: "ui-checkbox", name: name, value: value, form: form, aria: {label: label},
        data: {select_all_target: "box", action: "select-all#sync"})
    end
  end

  private

  def ui_button_content(text, icon, &block)
    parts = []
    parts << icon_tag(icon) if icon
    parts << (block ? capture(&block) : text)
    safe_join(parts.compact)
  end
end
