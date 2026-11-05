# frozen_string_literal: true

# JSON as a digest hashes it, byte for byte what the Go core's
# canonicalJSON writes (Go's encoding/json of a decoded value) and what
# @librepublish/astro reproduces (src/schema/digest.ts): object keys sorted by
# their bytes, no whitespace, strings escaped as Go escapes them (`<`, `>`,
# `&`, U+2028 and U+2029 as \uXXXX; control characters as \n, \r, \t, \b, \f
# or \u00XX), integral numbers without a fraction.
#
#   CanonicalJson.digest({"b" => 1, "a" => "<"})  # => "sha256:…" of {"a":"<","b":1}
#
# A site checks the schema digest it's handed (meta.schema_digest,
# X-CMS-Schema-Digest) with the same rules, so these are the contract, held
# to the Go core's recorded digest by spec/contracts/delivery_contract_spec.rb.
module CanonicalJson
  ESCAPES = {"<" => "\\u003c", ">" => "\\u003e", "&" => "\\u0026", " " => "\\u2028", " " => "\\u2029"}.freeze

  module_function

  def generate(value)
    case value
    when Hash
      "{" + value.map { |key, item| [key.to_s, item] }.sort_by(&:first).map { |key, item| "#{string(key)}:#{generate(item)}" }.join(",") + "}"
    when Array then "[" + value.map { generate(it) }.join(",") + "]"
    when String, Symbol then string(value.to_s)
    when Integer then value.to_s
    when Float then number(value)
    when true then "true"
    when false then "false"
    when nil then "null"
    else generate(value.as_json)
    end
  end

  def digest(value) = "sha256:#{Digest::SHA256.hexdigest(generate(value))}"

  # Go's escaping on top of JSON's: Ruby already writes \b, \f, \n, \r, \t
  # and \u00XX (lowercase hex) for the other control characters, and leaves
  # "/" alone, as Go does.
  def string(text)
    JSON.generate(text.encode("UTF-8")).gsub(/[<>&  ]/, ESCAPES)
  end

  # Go writes a float64 the shortest way that reads back, without a fraction
  # when it has none (1.0 is 1) and with an exponent from 1e21.
  def number(value)
    return "null" unless value.finite?
    return value.to_i.to_s if value == value.to_i && value.abs < 1e21

    value.to_s.sub(/e\+?/, "e+").sub("e+-", "e-")
  end
end
