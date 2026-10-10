# frozen_string_literal: true

# What each Litewind class sets, read from the vendored stylesheet and the
# app's tailwind-extras.css, so specs can tell when one element's classes
# fight: two classes under the same variant (none, hover:, md:…) setting the
# same property, like text-gray-600 beside text-blue-600, where which wins
# depends on where Litewind happens to define them.
module Litewind
  SOURCES = ["vendor/assets/stylesheets/litewind-*.css", "app/assets/stylesheets/tailwind-extras.css"].freeze

  # Properties that come along with others and don't decide anything alone.
  IGNORED = %w[line-height].freeze

  class Conflict < StandardError; end

  module_function

  def properties
    @properties ||= SOURCES.flat_map { Dir.glob(Rails.root.join(it)) }.each_with_object({}) do |file, found|
      rules(File.read(file).gsub(%r{/\*.*?\*/}m, "")).each do |selector, body|
        # A property set from one of Tailwind's own variables (border-2's
        # border-style: var(--tw-border-style)) is how utilities compose,
        # not a choice: border-dashed sets that variable.
        declared = body.scan(/(?:\A|[{;])\s*([a-z][a-z-]*)\s*:(?!:)\s*([^;{}]*)/)
          .reject { |_, value| value.strip.start_with?("var(--tw-") }.map(&:first).uniq - IGNORED
        next if declared.empty?

        selector.split(",").map(&:strip).grep(/\A\./).each do |single|
          (found[single[1..].delete("\\")] ||= Set.new).merge(declared)
        end
      end
    end
  end

  # [selector, body] for each block, nested blocks' bodies included in the
  # one around them.
  def rules(css)
    found = []
    stack = []
    start = 0
    index = 0
    while index < css.length
      case css[index]
      when "\\" then index += 1
      when "{"
        stack << [css[start...index].strip.split(/[;}]/).last.to_s.strip, index + 1]
        start = index + 1
      when ";" then start = index + 1
      when "}"
        selector, from = stack.pop
        found << [selector, css[from...index]] if selector
        start = index + 1
      end
      index += 1
    end
    found
  end

  # Pairs of classes in the list that set the same property under the same
  # variant.
  def conflicts(classes)
    names = classes.to_s.split.uniq.select { properties.key?(it) }
    names.combination(2).filter_map do |first, second|
      next unless variant(first) == variant(second)
      shared = properties[first] & properties[second]
      [first, second, shared.to_a] if shared.any?
    end
  end

  def check!(classes)
    found = conflicts(classes)
    return classes if found.empty?

    raise Conflict, "Classes that set the same property on one element: " +
      found.map { |first, second, shared| "#{first} and #{second} (#{shared.join(", ")})" }.join("; ") +
      " in #{classes.inspect}"
  end

  # The variant prefix, counting the utilities that style something other
  # than the element itself (its placeholder, the hairlines or space between
  # its children) as variants of their own.
  def variant(name)
    *prefixes, utility = name.split(":")
    [*prefixes, utility[/\A(placeholder|divide|space-[xy])-/, 1]].compact.join(":")
  end

  # In the test environment, ui() and class_names check what they return.
  module Checked
    def ui(...) = Litewind.check!(super)
    def token_list(...) = Litewind.check!(super)
    def class_names(...) = Litewind.check!(super)
  end
end

UiHelper.prepend(Litewind::Checked)
ActionView::Helpers::TagHelper.prepend(Litewind::Checked)
