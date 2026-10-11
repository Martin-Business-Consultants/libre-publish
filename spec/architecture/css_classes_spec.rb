# frozen_string_literal: true

require "rails_helper"

# The admin is drawn with its own CSS (app/assets/stylesheets, STYLE.md):
# components, layout pieces and a few helpers, named for what they are. A
# class nothing defines silently does nothing, and a rule nothing uses is
# weight every page carries, so both fail here.
RSpec.describe "Architecture: the admin's CSS classes" do
  VIEWS = ["app/views/**/*.erb", "engines/*/app/views/**/*.erb", "plugins/*/app/views/**/*.erb"].freeze
  RUBY = ["app/helpers/**/*.rb", "engines/*/app/helpers/**/*.rb", "plugins/*/app/helpers/**/*.rb"].freeze
  SCRIPTS = ["app/javascript/**/*.js", "engines/*/app/javascript/**/*.js", "plugins/*/app/javascript/**/*.js"].freeze
  SPECS = ["spec/**/*.rb", "plugins/*/spec/**/*.rb"].freeze
  STYLESHEETS = ["app/assets/stylesheets/**/*.css", "engines/*/app/assets/stylesheets/**/*.css", "plugins/*/app/assets/stylesheets/**/*.css"].freeze

  # Classes a stylesheet styles that the markup never writes, because
  # something else puts them in the DOM: Lexxy's editor, Turbo, the
  # browser's own (::file-selector-button is not a class), Stimulus
  # controllers that name a class in a value (data-*-class) or build one
  # from a string.
  BUILT_ELSEWHERE = %w[
    turbo-progress-bar
  ].freeze

  # Families of classes built the same way: icon_tag makes icon--<name>
  # from names that live in data (a collection's icon), the menu's
  # definitions and plugins; Lexxy and Action Text write their editor's,
  # attachments' and mentions' classes themselves.
  BUILT_ELSEWHERE_PATTERNS = [
    /\Aicon(?:--[\w-]+)?\z/,
    /\Alexxy-/,
    /\Aattachment(?:-gallery)?(?:--|__|\z)/,
    /\A(?:actiontext|mention|node--selected|horizontal-divider)\z/
  ].freeze

  CLASS_ATTRIBUTE = /\bclass="((?:<%.*?%>|[^"])*)"/m
  CLASS_OPTION = /\b(?:class|form_class|link_class|klass):\s*"([^"]*)"/
  CLASS_OPTION_TERNARY = /\b(?:class|form_class|link_class|klass):\s*[^,"\n]*\?\s*"([^"]*)"\s*:\s*"([^"]*)"/
  CLASS_NAMES_CALL = /\b(?:class_names|token_list)\((.*?)\)(?=\s*(?:%>|,|\)|$|\s+do\b|\s*\}))/m
  CLASSES_CONSTANT = /\b\w*(?:classes|CLASSES|BADGES)\s*=\s*(?:\{[^}]*\}|"[^"]*"|%w\[[^\]]*\])/m
  STRING = /"([^"#]*)"/
  SYMBOL_KEY = /(?<![\w"])([a-z][\w-]*):(?!:)/

  it "writes only classes a stylesheet defines, or a hook a script or spec reads" do
    known = stylesheet_classes | hook_classes
    offenders = used_classes.reject { |name, _| known.include?(name) }

    expect(offenders).to be_empty, <<~MESSAGE
      Classes nothing defines:
      #{offenders.map { |name, file| "  #{name} (#{file})" }.join("\n")}
      Use one of the admin's components or helpers (STYLE.md), or define it
      in the stylesheet for that screen.
    MESSAGE
  end

  it "writes no variant classes (hover:, sm:, lg:…)" do
    offenders = used_classes.select { |name, _| name.include?(":") }

    expect(offenders).to be_empty, <<~MESSAGE
      Classes with a variant prefix: a state or a breakpoint belongs in the
      component's stylesheet, not the markup.
      #{offenders.map { |name, file| "  #{name} (#{file})" }.join("\n")}
    MESSAGE
  end

  it "defines no class that nothing uses" do
    used = used_classes.keys.to_set | hook_classes | BUILT_ELSEWHERE.to_set
    unused = stylesheet_definitions.reject { |name, _| used.include?(name) || BUILT_ELSEWHERE_PATTERNS.any? { name.match?(it) } }

    expect(unused).to be_empty, <<~MESSAGE
      Classes a stylesheet defines that no view, helper, script or spec uses:
      #{unused.map { |name, file| "  .#{name} (#{file})" }.join("\n")}
      Delete the rule, or (for a class something else puts in the DOM) add it
      to BUILT_ELSEWHERE with where it comes from.
    MESSAGE
  end

  private

  def sources(globs)
    Dir.glob(globs, base: Rails.root.to_s).map { [it, Rails.root.join(it).read] }
  end

  # name => the first file that writes it.
  def used_classes
    @used_classes ||= sources(VIEWS + RUBY).each_with_object({}) do |(file, source), found|
      source = source.gsub(/<%#.*?%>/m, "")
      lists = source.scan(CLASS_ATTRIBUTE).flatten.map { it.gsub(/<%.*?%>/m, " ") }
      # Strings inside ERB in a class attribute (a ternary's two classes).
      lists += source.scan(CLASS_ATTRIBUTE).flatten.flat_map { it.scan(/<%.*?%>/m) }.flat_map { it.scan(STRING).flatten }
      lists += source.scan(CLASS_OPTION).flatten + source.scan(CLASS_OPTION_TERNARY).flatten
      # A hash's values are classes; its keys ("positive" =>) are not.
      lists += source.scan(CLASSES_CONSTANT).map { it.gsub(/"[^"]*"\s*=>/, "") }.flat_map { it.scan(STRING).flatten + it[/%w\[([^\]]*)\]/, 1].to_s.split }
      source.scan(CLASS_NAMES_CALL).flatten.each do |arguments|
        arguments = arguments.gsub(/[!=]=\s*"[^"]*"/, "")
        lists += arguments.scan(STRING).flatten
        lists += arguments.gsub(STRING, "").scan(SYMBOL_KEY).flatten
        lists += arguments.scan(/"([^"#]*)":/).flatten
      end
      lists.flat_map(&:split).each do |name|
        next if name.match?(/[\#{}<>%=()]/) || name.end_with?("-")
        found[name] ||= file
      end
    end
  end

  def stylesheet_classes
    stylesheet_definitions.keys.to_set
  end

  # name => the stylesheet that defines it.
  def stylesheet_definitions
    @stylesheet_definitions ||= sources(STYLESHEETS).each_with_object({}) do |(file, source), found|
      css = source.gsub(%r{/\*.*?\*/}m, "").gsub(/url\([^)]*\)/, "")
      # Selectors only: what comes before a {, not property values.
      css.scan(/([^{};]+)\{/).flatten.each do |selector|
        next if selector.strip.start_with?("@")
        selector.scan(/\.(-?[a-zA-Z_](?:\\.|[\w-])*)/).flatten.each { found[it.delete("\\")] ||= file }
      end
    end
  end

  # Classes in selectors (querySelector, closest, matches, at_css…), in
  # classList calls and className assignments, in a Stimulus class value
  # (data-*-class; a helper's link_class: or form_class: is markup, read
  # above), and in class="…" or a BEM name a spec expects.
  def hook_classes
    @hook_classes ||= sources(SCRIPTS + SPECS + VIEWS + RUBY).reject { |file, _| file == "spec/architecture/css_classes_spec.rb" }.flat_map do |file, source|
      selectors = source.scan(/(?:querySelector(?:All)?|closest|matches|at_css|css|have_css|have_no_css|have_selector|find|all|within)\(\s*["'`]([^"'`]*)/).flatten
      lists = source.scan(/classList\.\w+\(([^)]*)\)/).flatten.flat_map { it.scan(/["'`]([^"'`]*)["'`]/).flatten }
      lists += source.scan(/className\s*=\s*["'`]([^"'`]*)/).flatten
      lists += source.scan(/(?:data-[\w-]+-class(?:es)?=|(?<!\blink|\bform)_class(?:es)?(?:_value)?:\s*)\\?["']([^"'\\]*)/).flatten
      if file.start_with?("spec/", "plugins/")
        lists += source.scan(/class=\\?"([^"\\'\n]*)/).flatten
        lists += source.scan(/\b[a-z][\w-]*(?:__|--)[\w-]+/)
      end
      selectors.flat_map { it.scan(/\.([a-z][\w-]*)/).flatten } + lists.flat_map(&:split)
    end.select { it.match?(/\A[a-z][\w-]*\z/) }.to_set
  end
end
