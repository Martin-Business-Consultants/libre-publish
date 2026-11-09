# frozen_string_literal: true

# A global's data, secret-looking values masked (Redactable).
json.extract! global, :id, :slug, :name
# Only the keys the schema declares (DeliveredData), secrets masked.
json.data (@delivered_data ||= DeliveredData.new).fields(global.fields, global.redacted_data || {})
json.extract! global, :updated_at
