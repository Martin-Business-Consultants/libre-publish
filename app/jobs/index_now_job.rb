# frozen_string_literal: true

# Tells IndexNow's search engines about pages that changed (IndexNow).
class IndexNowJob < ApplicationJob
  queue_as :default

  def perform(urls)
    response = IndexNow.submit(urls)
    Rails.logger.warn("[indexnow] #{response.code} #{response.body.to_s.truncate(200)}") if response && !response.is_a?(Net::HTTPSuccess)
  rescue StandardError => error
    Rails.logger.warn("[indexnow] #{error.class}: #{error.message}")
  end
end
