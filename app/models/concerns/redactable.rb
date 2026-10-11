# frozen_string_literal: true

# Globals and settings are free-form, and some hold secrets (an API key, a
# webhook signing secret). What the API reads back has anything whose key
# name suggests a secret masked to its last four characters; writes still set
# the real value.
module Redactable
  extend ActiveSupport::Concern

  # The word alone or as a part of a key's name (smtp_password, github_token,
  # webhook_secret): `\b` would count "_" as part of the word.
  SECRET_KEY = /(?:\A|[_\-.])(api[_-]?key|secret|token|password|client[_-]?secret|hook[_-]?url)(?:\z|[_\-.])/i

  # A setting's keys named here are masked too: a deploy hook's URL is its
  # secret (anyone who has it can trigger builds).
  SECRET_FIELDS = {"deploy" => %w[url]}.freeze

  def redacted_data
    hidden = SECRET_FIELDS.fetch(try(:key).to_s, [])
    redact(data).then { |out| out.is_a?(Hash) ? out.to_h { |k, v| [k, hidden.include?(k.to_s) && v.is_a?(String) && v.present? ? mask(v) : v] } : out }
  end

  private

  def redact(value)
    case value
    when Hash
      value.each_with_object({}) do |(k, v), out|
        out[k] = if SECRET_KEY.match?(k.to_s) && v.is_a?(String) && !v.empty?
          mask(v)
        else
          redact(v)
        end
      end
    when Array
      value.map { |v| redact(v) }
    else
      value
    end
  end

  def mask(str)
    return "" if str.empty?

    "***#{str[-4..]}"
  end
end
