# frozen_string_literal: true

# One way to write a JSON value, so two programs reading the same data get
# the same bytes, and so the same digest: object keys sorted by their UTF-8
# bytes, no whitespace, `<`, `>`, `&`, U+2028 and U+2029 written as \uXXXX,
# control characters as \n, \r, \t, \b, \f or \u00XX, everything else as it
# is. Integers as integers; a float with no fraction as an integer (1.0 → 1),
# others as Ruby writes them. It is what the schema digest is taken over
# (DeliverySchema), and what the Astro integration (integrations/astro,
# src/schema/digest.ts) recomputes; the contract fixtures hold the two to it.
module CanonicalJson
  ESCAPES = {
    '"' => '\\"', "\\" => "\\\\", "\n" => "\\n", "\r" => "\\r", "\t" => "\\t", "\b" => "\\b", "\f" => "\\f"
  }.freeze

  module_function

  def generate(value)
    case value
    when nil then "null"
    when true then "true"
    when false then "false"
    when String, Symbol then string(value.to_s)
    when Integer then value.to_s
    when Float then float(value)
    when Array then "[#{value.map { generate(it) }.join(",")}]"
    when Hash
      pairs = value.map { |k, v| [k.to_s, v] }
      "{#{pairs.sort_by { |k, _| k.b }.map { |k, v| "#{string(k)}:#{generate(v)}" }.join(",")}}"
    else
      generate(value.as_json)
    end
  end

  def digest(value)
    "sha256:#{Digest::SHA256.hexdigest(generate(value))}"
  end

  def string(str)
    out = +'"'
    str.each_char do |char|
      code = char.ord
      out << if ESCAPES.key?(char) then ESCAPES[char]
      elsif code < 0x20 || char == "<" || char == ">" || char == "&" || code == 0x2028 || code == 0x2029
        format("\\u%04x", code)
      else char
      end
    end
    out << '"'
  end

  def float(value)
    return "null" unless value.finite?
    return value.to_i.to_s if value == value.to_i && value.abs < 1e21

    value.to_s
  end
end
