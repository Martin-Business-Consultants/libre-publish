# frozen_string_literal: true

json.data @redirects do |redirect|
  json.source redirect.source_path
  json.destination redirect.destination_url
  json.status redirect.status_code
  json.wildcard redirect.wildcard
end
json.meta({total: @redirects.size})
