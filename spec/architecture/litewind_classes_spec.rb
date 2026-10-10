# frozen_string_literal: true

require "rails_helper"

# The admin is styled with Litewind's precompiled Tailwind utilities
# (vendor/assets/stylesheets, STYLE.md), which hold most of Tailwind but not
# all of it: a class Litewind doesn't have silently does nothing. So every
# class the views and helpers write must be one Litewind defines, one the
# app's stylesheets define (tailwind-extras.css, and the hooks that state and
# behaviour rules hang on), or a hook JavaScript or a spec looks for.
RSpec.describe "Architecture: classes in the markup exist" do
  VIEWS = ["app/views/**/*.erb", "engines/*/app/views/**/*.erb", "plugins/*/app/views/**/*.erb"].freeze
  RUBY = ["app/helpers/**/*.rb", "engines/*/app/helpers/**/*.rb", "plugins/*/app/helpers/**/*.rb"].freeze
  STYLESHEETS = ["app/assets/stylesheets/**/*.css", "engines/*/app/assets/stylesheets/**/*.css", "plugins/*/app/assets/stylesheets/**/*.css"].freeze
  HOOK_SOURCES = ["app/javascript/**/*.js", "engines/*/app/javascript/**/*.js", "plugins/*/app/javascript/**/*.js", "spec/**/*.rb", "plugins/*/spec/**/*.rb"].freeze

  CLASS_ATTRIBUTE = /\bclass="((?:<%.*?%>|[^"])*)"/m
  CLASS_OPTION = /\b(?:class|form_class):\s*"([^"]*)"/
  CLASS_NAMES_CALL = /\b(?:class_names|token_list)\((.*?)\)(?=\s*(?:%>|,|\)|$|\s+do\b|\s*\}))/m
  CLASSES_VARIABLE = /\b\w*classes\s*=\s*"([^"]*)"/i
  STRING = /"([^"#]*)"/
  SYMBOL_KEY = /(?<![\w"])([a-z][\w-]*):(?!:)/

  it "writes only classes Litewind, the app's stylesheets or a hook define" do
    known = litewind_classes | stylesheet_classes | hook_classes
    offenders = used_classes.reject { |name, _| known.include?(name) }

    expect(offenders).to be_empty, <<~MESSAGE
      Classes nothing defines:
      #{offenders.map { |name, file| "  #{name} (#{file})" }.join("\n")}
      Use one Litewind has (vendor/assets/stylesheets), or add Tailwind's
      definition to app/assets/stylesheets/tailwind-extras.css.
    MESSAGE
  end

  it "never gives one element two classes that set the same property" do
    offenders = class_lists.flat_map do |file, list|
      Litewind.conflicts(list).map { |first, second, shared| "  #{first} and #{second} (#{shared.join(", ")}) in #{file}" }
    end

    expect(offenders).to be_empty, <<~MESSAGE
      Classes that fight over a property (which wins depends on Litewind's
      order, not the markup's):
      #{offenders.uniq.join("\n")}
    MESSAGE
  end

  # Settings › Branding's color, type and surface reach the markup only
  # through tokens (_global.css, STYLE.md): classes that bypass them would
  # look the same whatever the branding says.
  OFF_BRAND = {
    /\A(?:[\w-]+:)*(?:bg|text|border|ring|divide|placeholder|accent|outline|decoration|from|via|to|fill|stroke)-(?:slate|zinc|neutral|stone|orange|amber|lime|emerald|teal|cyan|sky|indigo|violet|purple|fuchsia|pink|rose)-\d+\z/ =>
      "a color family the themes and branding don't re-point: use gray (neutral), blue (accent), red, green or yellow",
    /\A(?:[\w-]+:)*(?:bg|text|border)-black\z/ => "black ignores the theme: use gray-900",
    /\A(?:[\w-]+:)*shadow(?:-(?:2xs|xs|sm|md|lg|xl|2xl|inner))?\z/ => "a fixed shadow: use shadow-surface or shadow-overlay",
    /\A(?:[\w-]+:)*rounded(?:-[trblse]{1,2})?\z/ => "a fixed radius: name a size (rounded-md…), which the branding's corners set",
    /\A(?:[\w-]+:)*font-serif\z/ => "a font the branding doesn't set: use font-sans (the default) or font-mono"
  }.freeze

  it "draws only with the tokens Settings › Branding sets" do
    offenders = used_classes.filter_map do |name, file|
      reason = OFF_BRAND.find { |pattern, _| name.match?(pattern) }&.last
      "  #{name} (#{file}): #{reason}" if reason
    end

    expect(offenders).to be_empty, "Classes that bypass the branding's color, type or surface:\n#{offenders.join("\n")}"
  end

  private

  # Every literal list of classes, with what's in ERB tags left out.
  def class_lists
    Dir.glob(VIEWS + RUBY, base: Rails.root.to_s).flat_map do |file|
      source = Rails.root.join(file).read.gsub(/<%#.*?%>/m, "")
      lists = source.scan(CLASS_ATTRIBUTE).flatten.map { it.gsub(/<%.*?%>/m, " ") }
      lists += source.scan(CLASS_OPTION).flatten + source.scan(CLASSES_VARIABLE).flatten
      lists.map { [file, it] }
    end
  end

  def used_classes
    Dir.glob(VIEWS + RUBY, base: Rails.root.to_s).each_with_object({}) do |file, found|
      source = Rails.root.join(file).read.gsub(/<%#.*?%>/m, "")
      lists = source.scan(CLASS_ATTRIBUTE).flatten.map { it.gsub(/<%.*?%>/m, " ") }
      lists += source.scan(CLASS_OPTION).flatten
      lists += source.scan(CLASSES_VARIABLE).flatten
      source.scan(CLASS_NAMES_CALL).flatten.each do |arguments|
        arguments = arguments.gsub(/[!=]=\s*"[^"]*"/, "")
        lists += arguments.scan(STRING).flatten
        lists += arguments.gsub(STRING, "").scan(SYMBOL_KEY).flatten
        lists += arguments.scan(/"([^"#]*)":/).flatten
      end
      lists += ui_recipes(source) if file.end_with?("ui_helper.rb")
      lists.flat_map(&:split).each do |name|
        next if name.match?(/[\#{}<>%=]/) || name.end_with?("-")
        found[name] ||= file
      end
    end
  end

  # UiHelper's recipes: the strings in UI_RECIPES.
  def ui_recipes(source)
    source[/UI_RECIPES = \{.*?^  \}\.freeze/m].to_s.scan(/:\s*"([^"]*)"/).flatten
  end

  def litewind_classes
    Dir.glob(Rails.root.join("vendor/assets/stylesheets/litewind-*.css")).flat_map do |file|
      File.read(file).scan(/^\s*\.((?:\\.|[^\s,{:\\])+(?:\\:(?:\\.|[^\s,{:\\])+)*)/).flatten.map { it.delete("\\") }
    end.to_set
  end

  def stylesheet_classes
    Dir.glob(STYLESHEETS, base: Rails.root.to_s).flat_map do |file|
      Rails.root.join(file).read.gsub(%r{/\*.*?\*/}m, "").scan(/\.(-?[a-zA-Z_](?:\\.|[\w-])*)/).flatten.map { it.delete("\\") }
    end.to_set
  end

  # Classes in selectors (querySelector, closest, matches, at_css…), in
  # classList calls and className assignments, and in class="…" a spec
  # expects.
  def hook_classes
    Dir.glob(HOOK_SOURCES, base: Rails.root.to_s).excluding("spec/architecture/litewind_classes_spec.rb").flat_map do |file|
      source = Rails.root.join(file).read
      selectors = source.scan(/(?:querySelector(?:All)?|closest|matches|at_css|css|have_css|have_selector)\(\s*["'`]([^"'`]*)/).flatten
      lists = source.scan(/classList\.\w+\(([^)]*)\)/).flatten.flat_map { it.scan(/["'`]([^"'`]*)["'`]/).flatten }
      lists += source.scan(/className\s*=\s*["'`]([^"'`]*)/).flatten
      lists += source.scan(/class=\\?"([^"\\'\n]*)/).flatten
      lists += source.scan(/\b[a-z][\w-]*(?:__|--)[\w-]+/) if file.start_with?("spec/")
      selectors.flat_map { it.scan(/\.([a-z][\w-]*)/).flatten } + lists.flat_map(&:split)
    end.select { it.match?(/\A[a-z][\w-]*\z/) }.to_set
  end
end
