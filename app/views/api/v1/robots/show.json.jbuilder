# frozen_string_literal: true

json.data do
  json.text @robots.to_s
  json.mode @robots.custom? ? "custom" : "generated"
end
