# frozen_string_literal: true

# A global's data, secret-looking values masked (Redactable).
json.extract! global, :id, :slug, :name
json.data global.redacted_data
json.extract! global, :updated_at
