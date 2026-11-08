# frozen_string_literal: true

# What makes the CMS's headlessness visible in the admin: the JSON tab's
# client call, and the Developers screen's pieces.
module HeadlessHelper
  # The @librepublish/astro client call that reads the record at an API path,
  # live, from the delivery API (/api/v1).
  def api_json_client_call(path)
    path = path.split("?").first
    case path
    when %r{\A/api/pages/(.+)\z} then %(const { data: page } = await cms.page(#{$1.to_json});)
    when %r{\A/api/collections/([^/]+)/entries/([^/]+)\z} then %(const { data: entry } = await cms.entry(#{$1.to_json}, #{$2.to_json});)
    when %r{\A/api/globals/([^/]+)\z} then %(const { data: global } = await cms.global(#{$1.to_json});)
    end
  end

  # The `cms` command (and MCP tool) that returns the record at an API path.
  def api_json_cli_call(path)
    case path.split("?").first
    when %r{\A/api/pages/(.+)\z} then "cms page #{$1}"
    when %r{\A/api/collections/([^/]+)/entries/([^/]+)\z} then "cms entry #{$1} #{$2}"
    when %r{\A/api/globals/([^/]+)\z} then "cms global #{$1}"
    end
  end
end
