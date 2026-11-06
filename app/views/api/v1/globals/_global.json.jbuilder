# frozen_string_literal: true

# A global's data, secret-looking values masked (Redactable), and only what
# /api/v1/schema declares (DeliveryHelper).
json.extract! global, :id, :slug, :name
json.data delivered.data(global.fields, global.redacted_data)
json.extract! global, :updated_at
