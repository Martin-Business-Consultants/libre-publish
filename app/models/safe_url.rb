# frozen_string_literal: true

# Which link addresses content may hold: the web (http, https), email and
# phone (mailto, tel), and anything without a scheme — a path, "#contact",
# "?q=". Never javascript:, data:, vbscript: or another scheme, which a link
# or button on the site (or in the editor's preview, signed in) would run.
# A browser drops tabs and newlines and ignores case in a scheme, so they're
# dropped here before it's read.
module SafeUrl
  SCHEMES = %w[http https mailto tel].freeze

  module_function

  def safe?(url)
    value = url.to_s.gsub(/[\u0000- \u007f]/, "")
    scheme = value[/\A([a-z][a-z0-9+.\-]*):/i, 1]
    scheme.nil? || SCHEMES.include?(scheme.downcase)
  end

  MESSAGE = "must be a web address (http or https), mailto:, tel:, or a path"
end
