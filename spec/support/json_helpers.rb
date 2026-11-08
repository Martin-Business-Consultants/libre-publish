# frozen_string_literal: true

# The last response's body, parsed: `json["data"]`.
module JsonHelpers
  def json = JSON.parse(response.body)
end

RSpec.configure { it.include JsonHelpers, type: :request }
