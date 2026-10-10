# frozen_string_literal: true

# Every asset the records point at, resolved, when there's a media library.
if assets
  json.included do
    json.assets assets
  end
end
